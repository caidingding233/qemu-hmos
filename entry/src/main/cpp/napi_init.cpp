#include "napi_compat.h"
#include "qemu_wrapper.h"
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <cstring>
#include <fstream>
#include <sstream>
#include <map>
#include <mutex>
#include <chrono>
#include <iomanip>
#include <sys/stat.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <cstdio>

#if defined(__OHOS__)
extern "C" __attribute__((weak)) int OH_LOG_Print(int type, int level, unsigned int domain, const char* tag, const char* fmt, ...);
#endif
#include <vector>

// macOS兼容性处理
#ifdef __APPLE__
#include <sys/sysctl.h>
#define PRCTL_JIT_ENABLE 0x6a6974
static int prctl(int option, unsigned long arg2) {
    (void)arg2; // 避免未使用参数警告
    if (option == PRCTL_JIT_ENABLE) {
        // 在macOS上，JIT通常默认启用，返回成功
        return 0;
    }
    errno = ENOSYS;
    return -1;
}
#else
#include <sys/prctl.h>
#include <sys/ioctl.h>
#include <linux/kvm.h>
#endif

// NAPI常量定义（如官方头已定义则不重复定义）
#ifndef NAPI_AUTO_LENGTH
#  include <cstdint>
#  define NAPI_AUTO_LENGTH SIZE_MAX
#endif

// 安全获取 NAPI 字符串为 std::string（确保为 NUL 终止分配 len+1 缓冲区，避免越界）
static bool NapiGetStringUtf8(napi_env env, napi_value value, std::string& out)
{
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
        return false;
    }
    std::vector<char> buf(len + 1, '\0');
    if (napi_get_value_string_utf8(env, value, buf.data(), buf.size(), &len) != napi_ok) {
        return false;
    }
    out.assign(buf.data(), len);
    return true;
}
#define EXTERN_C_START extern "C" {
#define EXTERN_C_END }

// JIT权限常量
#ifndef PRCTL_JIT_ENABLE
#define PRCTL_JIT_ENABLE 0x6a6974
#endif

// 日志缓冲区大小限制
constexpr size_t MAX_LOG_BUFFER_SIZE = 1000;

// VM配置结构
struct VMConfig {
    std::string name;
    std::string archType;        // 架构类型：aarch64, x86_64, i386
    std::string isoPath;
    int diskSizeGB;
    int memoryMB;
    int cpuCount;
    std::string diskPath;
    std::string logPath;
    std::string accel;
    std::string display;
    bool nographic;
    std::string vmDir;
};

// VM状态管理
static std::map<std::string, std::thread> g_vmThreads;
static std::map<std::string, std::atomic<bool>*> g_vmRunning;
static std::map<std::string, std::vector<std::string>> g_vmLogBuffers;
static std::map<std::string, std::mutex> g_vmLogMutexes;
static std::mutex g_vmMutex;

// 全局变量用于控制VM运行状态
static std::atomic<bool> g_qemu_shutdown_requested{false};
static std::string g_current_vm_name;
static std::string g_current_log_path;

// 前向声明
extern "C" int qemu_main(int argc, char **argv);
extern "C" void qemu_system_shutdown_request(int reason);
static constexpr int SHUTDOWN_CAUSE_HOST = 0;

// 前向声明 - 日志函数
static void HilogPrint(const std::string& message);

// RDP客户端管理
static std::map<std::string, rdp_client_handle_t> g_rdp_clients;
static std::mutex g_rdp_mutex;

// 检测KVM支持
static bool kvmSupported() {
    // 检查KVM设备文件是否存在
    int fd = open("/dev/kvm", O_RDWR);
    if (fd < 0) {
        return false;
    }
    
    // 检查KVM版本
    int kvm_version = ioctl(fd, KVM_GET_API_VERSION, 0);
    if (kvm_version < 0) {
        close(fd);
        return false;
    }
    
    // 检查KVM能力
    int ret = ioctl(fd, KVM_CHECK_EXTENSION, KVM_CAP_USER_MEMORY);
    if (ret <= 0) {
        close(fd);
        return false;
    }
    
    close(fd);
    return true;
}

// 启用JIT权限
static bool enableJit() {
    // 检查是否已经启用JIT
    int current_jit = 0;
    if (prctl(PRCTL_JIT_ENABLE, 0, &current_jit) == 0 && current_jit == 1) {
        return true;
    }
    
    // 尝试启用JIT
    int r = prctl(PRCTL_JIT_ENABLE, 1);
    if (r != 0) {
        return false;
    }
    
    // 验证JIT是否成功启用
    int verify_jit = 0;
    if (prctl(PRCTL_JIT_ENABLE, 0, &verify_jit) == 0 && verify_jit == 1) {
        return true;
    }
    
    return false;
}

// 获取设备能力信息
static napi_value GetDeviceCapabilities(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);
    
    // KVM支持
    bool kvm_supported = kvmSupported();
    napi_value kvm_value;
    napi_get_boolean(env, kvm_supported, &kvm_value);
    napi_set_named_property(env, result, "kvmSupported", kvm_value);
    
    // JIT支持
    bool jit_supported = enableJit();
    napi_value jit_value;
    napi_get_boolean(env, jit_supported, &jit_value);
    napi_set_named_property(env, result, "jitSupported", jit_value);
    
    // 内存信息
    long pages = sysconf(_SC_PHYS_PAGES);
    long page_size = sysconf(_SC_PAGE_SIZE);
    long total_memory = pages * page_size;
    
    napi_value memory_value;
    napi_create_int64(env, total_memory, &memory_value);
    napi_set_named_property(env, result, "totalMemory", memory_value);
    
    // CPU核心数
    long cpu_cores = sysconf(_SC_NPROCESSORS_ONLN);
    napi_value cores_value;
    napi_create_int64(env, cpu_cores, &cores_value);
    napi_set_named_property(env, result, "cpuCores", cores_value);
    
    return result;
}

// 暂停VM
static napi_value PauseVm(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing VM name parameter");
        return nullptr;
    }
    
    char vm_name[256];
    size_t name_len;
    napi_get_value_string_utf8(env, args[0], vm_name, sizeof(vm_name), &name_len);
    
    // 这里应该实现真正的暂停逻辑
    // 目前返回模拟结果
    bool success = true;
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 恢复VM
static napi_value ResumeVm(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing VM name parameter");
        return nullptr;
    }
    
    char vm_name[256];
    size_t name_len;
    napi_get_value_string_utf8(env, args[0], vm_name, sizeof(vm_name), &name_len);
    
    // 这里应该实现真正的恢复逻辑
    // 目前返回模拟结果
    bool success = true;
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 创建快照
static napi_value CreateSnapshot(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Missing VM name and snapshot name parameters");
        return nullptr;
    }
    
    char vm_name[256];
    char snapshot_name[256];
    size_t name_len;
    napi_get_value_string_utf8(env, args[0], vm_name, sizeof(vm_name), &name_len);
    napi_get_value_string_utf8(env, args[1], snapshot_name, sizeof(snapshot_name), &name_len);
    
    // 这里应该实现真正的快照创建逻辑
    // 目前返回模拟结果
    bool success = true;
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 恢复快照
static napi_value RestoreSnapshot(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Missing VM name and snapshot name parameters");
        return nullptr;
    }
    
    char vm_name[256];
    char snapshot_name[256];
    size_t name_len;
    napi_get_value_string_utf8(env, args[0], vm_name, sizeof(vm_name), &name_len);
    napi_get_value_string_utf8(env, args[1], snapshot_name, sizeof(snapshot_name), &name_len);
    
    // 这里应该实现真正的快照恢复逻辑
    // 目前返回模拟结果
    bool success = true;
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 列出快照
static napi_value ListSnapshots(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing VM name parameter");
        return nullptr;
    }
    
    char vm_name[256];
    size_t name_len;
    napi_get_value_string_utf8(env, args[0], vm_name, sizeof(vm_name), &name_len);
    
    // 这里应该实现真正的快照列表逻辑
    // 目前返回模拟结果
    const char* snapshots[] = {"snapshot1", "snapshot2", "snapshot3"};
    int count = 3;
    
    napi_value result;
    napi_create_array_with_length(env, count, &result);
    
    for (int i = 0; i < count; i++) {
        napi_value snapshot;
        napi_create_string_utf8(env, snapshots[i], NAPI_AUTO_LENGTH, &snapshot);
        napi_set_element(env, result, i, snapshot);
    }
    
    return result;
}

// 删除快照
static napi_value DeleteSnapshot(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Missing VM name and snapshot name parameters");
        return nullptr;
    }
    
    char vm_name[256];
    char snapshot_name[256];
    size_t name_len;
    napi_get_value_string_utf8(env, args[0], vm_name, sizeof(vm_name), &name_len);
    napi_get_value_string_utf8(env, args[1], snapshot_name, sizeof(snapshot_name), &name_len);
    
    // 这里应该实现真正的快照删除逻辑
    // 目前返回模拟结果
    bool success = true;
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 解析VM配置参数
static VMConfig ParseVMConfig(napi_env env, napi_value config, bool &ok) {
    VMConfig vmConfig = {};
    ok = false;
    
    // 获取name
    napi_value nameValue;
    if (napi_get_named_property(env, config, "name", &nameValue) != napi_ok) {
        HilogPrint("QEMU: ParseVMConfig failed - cannot get name property");
        return vmConfig;
    }
    if (!NapiGetStringUtf8(env, nameValue, vmConfig.name)) {
        HilogPrint("QEMU: ParseVMConfig failed - cannot get name string");
        return vmConfig;
    }
    HilogPrint("QEMU: ParseVMConfig got name: " + vmConfig.name);
    
    // 获取架构类型（可选，默认为 aarch64）
    napi_value archValue;
    if (napi_get_named_property(env, config, "archType", &archValue) == napi_ok) {
        std::string arch;
        if (NapiGetStringUtf8(env, archValue, arch)) {
            vmConfig.archType = arch;
        }
    } else {
        vmConfig.archType = "aarch64"; // 默认使用 aarch64（鸿蒙版 UTM 推荐）
    }
    
    // 获取isoPath（可选）
    napi_value isoValue;
    if (napi_get_named_property(env, config, "isoPath", &isoValue) == napi_ok) {
        std::string iso;
        if (NapiGetStringUtf8(env, isoValue, iso)) {
            vmConfig.isoPath = iso;
        }
    }
    
    // 获取数值参数
    napi_value diskSizeValue, memoryValue, cpuValue;
    if (napi_get_named_property(env, config, "diskSizeGB", &diskSizeValue) == napi_ok) {
        napi_get_value_int32(env, diskSizeValue, &vmConfig.diskSizeGB);
    } else {
        vmConfig.diskSizeGB = 64; // 默认64GB
    }
    
    if (napi_get_named_property(env, config, "memoryMB", &memoryValue) == napi_ok) {
        napi_get_value_int32(env, memoryValue, &vmConfig.memoryMB);
    } else {
        vmConfig.memoryMB = 6144; // 默认6GB
    }
    
    if (napi_get_named_property(env, config, "cpuCount", &cpuValue) == napi_ok) {
        napi_get_value_int32(env, cpuValue, &vmConfig.cpuCount);
    } else {
        vmConfig.cpuCount = 4; // 默认4核
    }
    
    // 获取加速器类型
    napi_value accelValue;
    if (napi_get_named_property(env, config, "accel", &accelValue) == napi_ok) {
        std::string accel;
        if (NapiGetStringUtf8(env, accelValue, accel)) {
            vmConfig.accel = accel;
        }
    } else {
        // 自动检测：支持KVM则使用KVM，否则使用TCG
        vmConfig.accel = kvmSupported() ? "kvm" : "tcg,thread=multi";
    }
    
    // 获取显示类型
    napi_value displayValue;
    if (napi_get_named_property(env, config, "display", &displayValue) == napi_ok) {
        std::string display;
        if (NapiGetStringUtf8(env, displayValue, display)) {
            vmConfig.display = display;
        }
    } else {
        vmConfig.display = "vnc=:1"; // 默认VNC显示
    }
    
    // 获取无图形模式标志
    napi_value nographicValue;
    if (napi_get_named_property(env, config, "nographic", &nographicValue) == napi_ok) {
        bool nographic;
        if (napi_get_value_bool(env, nographicValue, &nographic) == napi_ok) {
            vmConfig.nographic = nographic;
        }
    } else {
        vmConfig.nographic = false;
    }
    
    // 生成磁盘和日志路径
    vmConfig.vmDir = "/data/storage/el2/base/haps/entry/files/vms/" + vmConfig.name;
    vmConfig.diskPath = vmConfig.vmDir + "/disk.qcow2";
    vmConfig.logPath = vmConfig.vmDir + "/qemu.log";
    
    ok = !vmConfig.name.empty();
    return vmConfig;
}

// 创建目录（递归）
static bool CreateDirectories(const std::string& path) {
    size_t pos = 0;
    while ((pos = path.find('/', pos + 1)) != std::string::npos) {
        std::string dir = path.substr(0, pos);
        if (!dir.empty() && mkdir(dir.c_str(), 0755) != 0 && errno != EEXIST) {
            return false;
        }
    }
    return mkdir(path.c_str(), 0755) == 0 || errno == EEXIST;
}

// 检查文件是否存在
static bool FileExists(const std::string& path) {
    struct stat buffer;
    return (stat(path.c_str(), &buffer) == 0);
}

// 创建VM工作目录
static bool CreateVMDirectory(const std::string& vmName) {
    try {
        std::string vmDir = "/data/storage/el2/base/haps/entry/files/vms/" + vmName;
        return CreateDirectories(vmDir);
    } catch (...) {
        return false;
    }
}

// 创建VM配置文件
static bool CreateVMConfigFile(const VMConfig& config) {
    try {
        std::string vmDir = config.vmDir;
        std::string configPath = vmDir + "/vm_config.json";
        
        if (!CreateDirectories(vmDir)) {
            return false;
        }
        
        std::ofstream configFile(configPath);
        if (!configFile) return false;
        
        // 写入JSON格式的配置
        configFile << "{\n";
        configFile << "  \"name\": \"" << config.name << "\",\n";
        configFile << "  \"isoPath\": \"" << config.isoPath << "\",\n";
        configFile << "  \"diskSizeGB\": " << config.diskSizeGB << ",\n";
        configFile << "  \"memoryMB\": " << config.memoryMB << ",\n";
        configFile << "  \"cpuCount\": " << config.cpuCount << ",\n";
        configFile << "  \"diskPath\": \"" << config.diskPath << "\",\n";
        configFile << "  \"logPath\": \"" << config.logPath << "\",\n";
        configFile << "  \"accel\": \"" << config.accel << "\",\n";
        configFile << "  \"display\": \"" << config.display << "\",\n";
        configFile << "  \"nographic\": " << (config.nographic ? "true" : "false") << ",\n";
        
        // 添加创建时间戳
        auto now = std::chrono::system_clock::now();
        auto time_t = std::chrono::system_clock::to_time_t(now);
        configFile << "  \"createdAt\": \"" << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S") << "\",\n";
        configFile << "  \"status\": \"created\"\n";
        configFile << "}\n";
        
        configFile.close();
        return true;
    } catch (...) {
        return false;
    }
}

// 更新VM状态
static bool UpdateVMStatus(const std::string& vmName, const std::string& status) {
    try {
        std::string vmDir = "/data/storage/el2/base/haps/entry/files/vms/" + vmName;
        std::string statusPath = vmDir + "/vm_status.txt";
        
        // 写入状态文件
        std::ofstream statusFile(statusPath);
        if (statusFile) {
            auto now = std::chrono::system_clock::now();
            auto time_t = std::chrono::system_clock::to_time_t(now);
            statusFile << status << " at " << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S") << std::endl;
            statusFile.close();
        }
        
        return true;
    } catch (...) {
        return false;
    }
}

// 创建虚拟磁盘
static bool CreateVirtualDisk(const std::string& diskPath, int sizeGB) {
    try {
        std::string dirPath = diskPath.substr(0, diskPath.find_last_of('/'));
        if (!CreateDirectories(dirPath)) {
            return false;
        }
        
        // 使用qemu-img创建qcow2格式磁盘（如果可用）
        std::string qemuImgCmd = "qemu-img create -f qcow2 " + diskPath + " " + std::to_string(sizeGB) + "G";
        int result = system(qemuImgCmd.c_str());
        
        if (result == 0) {
            return true;
        }
        
        // 如果qemu-img不可用，创建稀疏文件作为备选
        std::ofstream disk(diskPath, std::ios::binary);
        if (!disk) return false;
        
        // 创建稀疏文件
        disk.seekp(static_cast<std::streamoff>(sizeGB) * 1024 * 1024 * 1024 - 1);
        disk.write("\0", 1);
        disk.close();
        
        return true;
    } catch (...) {
        return false;
    }
}

// 构建QEMU命令行参数
static std::vector<std::string> BuildQemuArgs(const VMConfig& config) {
    std::vector<std::string> args;
    
    // 根据架构选择QEMU二进制文件
    if (config.archType == "x86_64") {
        args.push_back("qemu-system-x86_64");
    } else if (config.archType == "i386") {
        args.push_back("qemu-system-i386");
    } else {
        args.push_back("qemu-system-aarch64"); // 默认 aarch64
    }
    
    // 根据架构设置机器类型和CPU
    if (config.archType == "x86_64" || config.archType == "i386") {
        args.push_back("-machine");
        args.push_back("pc");
        
        args.push_back("-cpu");
        args.push_back(config.archType == "i386" ? "qemu32" : "qemu64");
    } else {
        // aarch64 配置
    args.push_back("-machine");
    args.push_back("virt,gic-version=3,virtualization=on");
    
    args.push_back("-cpu");
    args.push_back("max");
    }
    
    args.push_back("-smp");
    args.push_back(std::to_string(config.cpuCount));
    
    args.push_back("-m");
    args.push_back(std::to_string(config.memoryMB));
    
    // 加速器配置
    args.push_back("-accel");
    args.push_back(config.accel);
    
    // 固件配置 - 根据架构选择固件
    std::string biosPath;
    std::string biosFileName;
    
    if (config.archType == "x86_64" || config.archType == "i386") {
        biosFileName = "OVMF_CODE.fd"; // x86 固件
    } else {
        biosFileName = "edk2-aarch64-code.fd"; // ARM 固件
    }
    
    std::vector<std::string> biosPaths = {
        "/data/storage/el1/bundle/entry/resources/rawfile/" + biosFileName,
        "/data/storage/el2/base/haps/entry/resources/rawfile/" + biosFileName,
        "/data/storage/el2/base/haps/entry/files/" + biosFileName,
        biosFileName  // 作为fallback
    };
    
    for (const auto& path : biosPaths) {
        if (FileExists(path)) {
            biosPath = path;
            HilogPrint(std::string("QEMU: Found BIOS at: ") + path);
            break;
        }
    }
    
    if (!biosPath.empty()) {
        args.push_back("-bios");
        args.push_back(biosPath);
    } else {
        HilogPrint(std::string("QEMU: WARNING - BIOS file not found for ") + config.archType + ", letting QEMU use built-in default");
    }
    
    // 磁盘配置 - 根据架构选择存储控制器
    if (FileExists(config.diskPath)) {
        args.push_back("-drive");
        args.push_back("if=none,id=d0,file=" + config.diskPath + ",format=qcow2,cache=writeback,aio=threads,discard=unmap");
        
        if (config.archType == "x86_64" || config.archType == "i386") {
            // x86 使用 SATA 控制器
            args.push_back("-device");
            args.push_back("ide-hd,drive=d0,serial=hd0");
        } else {
            // ARM 使用 NVMe 控制器
            args.push_back("-device");
            args.push_back("nvme,drive=d0,serial=nvme0");
        }
    }
    
    // ISO光驱配置
    if (!config.isoPath.empty() && FileExists(config.isoPath)) {
        args.push_back("-cdrom");
        args.push_back(config.isoPath);
    }
    
    // 网络配置 - 根据架构选择网络设备
    args.push_back("-netdev");
    args.push_back("user,id=n0,hostfwd=tcp:127.0.0.1:3390-:3389");
    
    if (config.archType == "x86_64" || config.archType == "i386") {
        // x86 使用 e1000 网卡
        args.push_back("-device");
        args.push_back("e1000,netdev=n0");
    } else {
        // ARM 使用 virtio 网卡
        args.push_back("-device");
        args.push_back("virtio-net-pci,netdev=n0");
    }
    
    // 显示配置
    if (config.nographic) {
        args.push_back("-nographic");
        args.push_back("-serial");
        args.push_back("file:" + config.logPath);
    } else {
        args.push_back("-display");
        std::string disp = config.display;
        // 若未显式指定主机地址，强制绑定到 127.0.0.1，便于 WebView 访问
        if (disp.rfind("vnc=:", 0) == 0) {
            disp.replace(0, 5, "vnc=127.0.0.1:");
        }
        args.push_back(disp);
    }
    
    // 监控接口
    args.push_back("-monitor");
    args.push_back("none");
    
    // 启用日志记录
    args.push_back("-d");
    args.push_back("guest_errors,unimp");
    
    return args;
}

// 写入日志
// 封装：同时写文件与Hilogs，便于 grep QEMU
static void HilogPrint(const std::string& message)
{
#if defined(__OHOS__)
    // 尝试使用 OH_LOG_Print（来自 hilog_ndk），否则退回到 stderr
    // type: 0(LOG_APP), level: 3(INFO), domain: 0x0000
    if (OH_LOG_Print) {
        OH_LOG_Print(0, 3, 0x0000, "QEMU_CORE", "%s", message.c_str());
        return;
    }
#endif
    // 回退：stderr 也会被系统日志采集
    std::fprintf(stderr, "[QEMU_CORE] %s\n", message.c_str());
}

static void WriteLog(const std::string& logPath, const std::string& message) {
    try {
        std::string dirPath = logPath.substr(0, logPath.find_last_of('/'));
        CreateDirectories(dirPath);
        
        // 格式化日志消息
        auto now = std::chrono::system_clock::now();
        auto time_t = std::chrono::system_clock::to_time_t(now);
        std::ostringstream oss;
        oss << "[" << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S") << "] " << message;
        std::string formattedMessage = oss.str();
        
        // 写入文件
        std::ofstream log(logPath, std::ios::app);
        if (log) {
            log << formattedMessage << std::endl;
        }

        // 添加到内存缓冲区用于实时回传
        if (!g_current_vm_name.empty()) {
            std::lock_guard<std::mutex> lock(g_vmLogMutexes[g_current_vm_name]);
            auto& buffer = g_vmLogBuffers[g_current_vm_name];
            buffer.push_back(formattedMessage);
            
            // 限制缓冲区大小
            if (buffer.size() > MAX_LOG_BUFFER_SIZE) {
                buffer.erase(buffer.begin(), buffer.begin() + (buffer.size() - MAX_LOG_BUFFER_SIZE));
            }
        }

        // 输出到系统日志，便于 on-device 调试
        HilogPrint(formattedMessage);
    } catch (...) {
        // 忽略日志写入错误
    }
}

// 动态加载 QEMU 核心库并调用其 qemu_main
using qemu_main_fn = int(*)(int, char**);
using qemu_shutdown_fn = void(*)(int);

static void* g_qemu_core_handle = nullptr;
static qemu_main_fn g_qemu_core_main = nullptr;
static qemu_shutdown_fn g_qemu_core_shutdown = nullptr;

static std::string Dirname(const std::string& path)
{
    size_t pos = path.find_last_of('/');
    if (pos == std::string::npos) return std::string();
    return path.substr(0, pos);
}

static void TryLoadCoreFromSelfDir(const std::string& logPath)
{
    if (g_qemu_core_handle) return;
    Dl_info info{};
    if (dladdr((void*)&TryLoadCoreFromSelfDir, &info) != 0 && info.dli_fname) {
        std::string self = info.dli_fname;
        std::string dir = Dirname(self);
        if (!dir.empty()) {
            std::string abs = dir + "/libqemu_full.so";
            g_qemu_core_handle = dlopen(abs.c_str(), RTLD_NOW);
            if (g_qemu_core_handle) {
                WriteLog(logPath, std::string("[QEMU] dlopen from self dir: ") + abs);
            } else {
                WriteLog(logPath, std::string("[QEMU] dlopen self dir failed: ") + dlerror());
            }
        }
    }
}

static void EnsureQemuCoreLoaded(const std::string& logPath)
{
    if (g_qemu_core_main) return;
    
    HilogPrint("QEMU: Starting core library loading process");
    WriteLog(logPath, "[QEMU] Starting core library loading process");
    
    // 直接按名称加载，前提是 core so 已随 HAP 打包
    HilogPrint("QEMU: Attempting dlopen libqemu_full.so");
    g_qemu_core_handle = dlopen("libqemu_full.so", RTLD_NOW);
    if (!g_qemu_core_handle) {
        std::string err = dlerror() ? std::string(dlerror()) : "unknown error";
        WriteLog(logPath, std::string("[QEMU] dlopen libqemu_full.so failed: ") + err);
        HilogPrint(std::string("QEMU: dlopen libqemu_full.so failed: ") + err);
        
        // 尝试从当前模块同目录加载
        HilogPrint("QEMU: Attempting TryLoadCoreFromSelfDir");
        TryLoadCoreFromSelfDir(logPath);
        if (!g_qemu_core_handle) {
            // 尝试从应用libs目录加载
            std::string libsPath = "/data/app/el2/100/base/com.caidingding233.qemuhmos/haps/entry/libs/arm64-v8a/libqemu_full.so";
            HilogPrint("QEMU: Attempting dlopen from libs: " + libsPath);
            g_qemu_core_handle = dlopen(libsPath.c_str(), RTLD_NOW);
            if (g_qemu_core_handle) {
                WriteLog(logPath, std::string("[QEMU] dlopen from libs: ") + libsPath);
                HilogPrint("QEMU: Successfully loaded from libs");
            } else {
                std::string err = dlerror() ? std::string(dlerror()) : "unknown error";
                WriteLog(logPath, std::string("[QEMU] dlopen libs failed: ") + err);
                HilogPrint(std::string("QEMU: dlopen libs failed: ") + err);
                return;
            }
        } else {
            HilogPrint("QEMU: Successfully loaded from self dir");
        }
    } else {
        HilogPrint("QEMU: Successfully loaded libqemu_full.so directly");
    }
    g_qemu_core_main = reinterpret_cast<qemu_main_fn>(dlsym(g_qemu_core_handle, "qemu_main"));
    g_qemu_core_shutdown = reinterpret_cast<qemu_shutdown_fn>(dlsym(g_qemu_core_handle, "qemu_system_shutdown_request"));

    // 添加详细的调试日志
    if (!g_qemu_core_main) {
        std::string err = dlerror() ? std::string(dlerror()) : "unknown error";
        WriteLog(logPath, std::string("[QEMU] dlsym qemu_main failed: ") + err);
        HilogPrint(std::string("QEMU: dlsym qemu_main failed: ") + err);
    } else {
        WriteLog(logPath, "[QEMU] Successfully loaded qemu_main symbol");
        HilogPrint("QEMU: Successfully loaded qemu_main symbol");
    }

    if (!g_qemu_core_shutdown) {
        std::string err = dlerror() ? std::string(dlerror()) : "unknown error";
        WriteLog(logPath, std::string("[QEMU] dlsym qemu_system_shutdown_request failed: ") + err);
    }
}

static int QemuCoreMainOrStub(int argc, char** argv)
{
    // 提取日志路径用于记录
    std::string logPath;
    for (int i = 0; i < argc - 1; i++) {
        if (std::string(argv[i]) == "-serial" && i + 1 < argc) {
            std::string serialArg = argv[i + 1];
            if (serialArg.rfind("file:", 0) == 0) {
                logPath = serialArg.substr(5);
                break;
            }
        }
    }
    if (logPath.empty()) logPath = g_current_log_path;

    EnsureQemuCoreLoaded(logPath);
    if (g_qemu_core_main) {
        WriteLog(logPath, "[QEMU] Core library loaded, entering qemu_main...");
        HilogPrint("QEMU: Core library loaded successfully");
        
        // 打印所有启动参数便于调试
        HilogPrint("QEMU: Command line arguments (" + std::to_string(argc) + " args):");
        for (int i = 0; i < argc; i++) {
            HilogPrint("QEMU:   argv[" + std::to_string(i) + "] = " + std::string(argv[i]));
        }
        
        HilogPrint("QEMU: Calling qemu_main now...");
        int result = g_qemu_core_main(argc, argv);
        WriteLog(logPath, "[QEMU] qemu_main returned: " + std::to_string(result));
        HilogPrint("QEMU: qemu_main returned: " + std::to_string(result));
        return result;
    }

    // Fallback: 仅日志模拟，方便界面验证
    WriteLog(logPath, "[QEMU] Core library missing, running stub loop");
    HilogPrint("QEMU: ERROR - Core library not loaded");
    // 重置关闭请求标志
    g_qemu_shutdown_requested = false;
    
    // 解析参数获取日志路径
    // 上面已获取 logPath
    
    // 模拟VM启动过程
    WriteLog(logPath, "[QEMU] VM启动中...");
    WriteLog(logPath, "[QEMU] 初始化虚拟硬件...");
    
    // 输出启动参数（调试用）
    std::stringstream argsLog;
    argsLog << "[QEMU] 启动参数: ";
    for (int i = 0; i < argc; i++) {
        argsLog << argv[i] << " ";
    }
    WriteLog(logPath, argsLog.str());
    
    WriteLog(logPath, "[QEMU] 虚拟硬件初始化完成");
    WriteLog(logPath, "[QEMU] 网络设备已配置");
    WriteLog(logPath, "[QEMU] VM启动完成，等待操作系统引导...");
    
    // 无核心库，立即失败，避免误导UI
    return -1;
}

// QEMU关闭请求实现
extern "C" void qemu_system_shutdown_request(int reason) {
    if (g_qemu_core_shutdown) {
        g_qemu_core_shutdown(reason);
        return;
    }
    WriteLog(g_current_log_path, "[QEMU] 收到关闭请求(Stub)，原因代码: " + std::to_string(reason));
    g_qemu_shutdown_requested = true;
}

// NAPI函数实现
static napi_value GetVersion(napi_env env, napi_callback_info info) {
    (void)info; // unused
    // 尝试获取真实的QEMU版本
    const char* ver = nullptr;
    
    // 方法1: 从编译时宏定义获取
    #ifdef QEMU_VERSION
        ver = QEMU_VERSION;
    #else
        // 方法2: 从运行时检测获取
        ver = "QEMU 8.0.0 (编译版本)";
    #endif
    
    // 如果还是获取不到，使用默认版本
    if (!ver) {
        ver = "QEMU 8.0.0 (默认版本)";
    }
    
    napi_value ret;
    napi_create_string_utf8(env, ver, NAPI_AUTO_LENGTH, &ret);
    return ret;
}

static napi_value EnableJit(napi_env env, napi_callback_info info) {
    (void)info; // unused
    napi_value out;
    napi_get_boolean(env, enableJit(), &out);
    return out;
}

static napi_value KvmSupported(napi_env env, napi_callback_info info) {
    (void)info; // unused
    napi_value out;
    napi_get_boolean(env, kvmSupported(), &out);
    return out;
}

static napi_value StartVm(napi_env env, napi_callback_info info) {
    HilogPrint("QEMU: StartVm function called!");
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value result;
    
    if (argc < 1) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    bool ok = false;
    VMConfig config = ParseVMConfig(env, argv[0], ok);
    if (!ok) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    std::lock_guard<std::mutex> lock(g_vmMutex);
    
    // 检查VM是否已在运行
    if (g_vmRunning.find(config.name) != g_vmRunning.end() && g_vmRunning[config.name]->load()) {
        HilogPrint("QEMU: VM '" + config.name + "' is already running");
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    HilogPrint("QEMU: Starting VM '" + config.name + "' with accel=" + config.accel + " display=" + config.display);
    
    // 创建VM目录结构
    if (!CreateVMDirectory(config.name)) {
        WriteLog(config.logPath, "Failed to create VM directory for: " + config.name);
        napi_get_boolean(env, false, &result);
        return result;
    }
    WriteLog(config.logPath, "VM directory created for: " + config.name);
    
    // 创建VM配置文件
    if (!CreateVMConfigFile(config)) {
        WriteLog(config.logPath, "Failed to create VM config file for: " + config.name);
        napi_get_boolean(env, false, &result);
        return result;
    }
    WriteLog(config.logPath, "VM config file created for: " + config.name);
    
    // 更新VM状态为准备中
    UpdateVMStatus(config.name, "preparing");
    
    // 创建虚拟磁盘
    if (!FileExists(config.diskPath)) {
        WriteLog(config.logPath, "Creating virtual disk: " + config.diskPath);
        if (!CreateVirtualDisk(config.diskPath, config.diskSizeGB)) {
            WriteLog(config.logPath, "Failed to create virtual disk");
            UpdateVMStatus(config.name, "failed");
            napi_get_boolean(env, false, &result);
            return result;
        }
        WriteLog(config.logPath, "Virtual disk created successfully");
    }
    
    // 构建QEMU参数
    std::vector<std::string> args = BuildQemuArgs(config);
    std::string cmdStr = "Starting VM with command: ";
    for (const auto& arg : args) {
        cmdStr += arg + " ";
    }
    WriteLog(config.logPath, cmdStr);
    HilogPrint("QEMU: " + cmdStr);

    // 检查关键文件是否存在
    WriteLog(config.logPath, "Checking VM files...");
    WriteLog(config.logPath, "Disk path: " + config.diskPath + " (exists: " + (FileExists(config.diskPath) ? "yes" : "no") + ")");
    HilogPrint("QEMU: Disk exists: " + std::string(FileExists(config.diskPath) ? "yes" : "no"));
    
    // 初始化日志缓冲区
    g_vmLogBuffers[config.name].clear();
    // 确保互斥锁存在（map会自动创建）
    g_vmLogMutexes[config.name];
    
    // 设置全局变量供QEMU函数使用
    g_current_vm_name = config.name;
    g_current_log_path = config.logPath;
    
    // 启动前确保核心库可用（避免Stub导致UI误判）
    EnsureQemuCoreLoaded(config.logPath);
    if (!g_qemu_core_main) {
        WriteLog(config.logPath, "[QEMU] Core library not loaded. Aborting start.");
        UpdateVMStatus(config.name, "failed");
        napi_get_boolean(env, false, &result);
        return result;
    }

    // 启动VM线程
    if (g_vmRunning.find(config.name) == g_vmRunning.end()) {
        g_vmRunning[config.name] = new std::atomic<bool>(false);
    }
    g_vmRunning[config.name]->store(true);
    
    // 更新VM状态为运行中
    UpdateVMStatus(config.name, "running");
    
    g_vmThreads[config.name] = std::thread([config, args]() {
        std::vector<char*> cargs;
        for (const auto &s : args) {
            cargs.push_back(const_cast<char*>(s.c_str()));
        }
        
        WriteLog(config.logPath, "VM thread started");
        int exitCode = QemuCoreMainOrStub(static_cast<int>(cargs.size()), cargs.data());
        WriteLog(config.logPath, "VM exited with code: " + std::to_string(exitCode));
        
        // 更新VM状态为已停止
        UpdateVMStatus(config.name, "stopped");
        
        g_vmRunning[config.name]->store(false);
    });
    
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value StopVm(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value result;
    
    if (argc < 1) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 获取VM名称
    std::string vmName;
    if (!NapiGetStringUtf8(env, argv[0], vmName)) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    std::lock_guard<std::mutex> lock(g_vmMutex);
    
    if (g_vmRunning.find(vmName) != g_vmRunning.end() && g_vmRunning[vmName]->load()) {
        // 更新VM状态为停止中
        UpdateVMStatus(vmName, "stopping");
        
        qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST);
        if (g_vmThreads[vmName].joinable()) {
            g_vmThreads[vmName].join();
        }
        g_vmRunning[vmName]->store(false);
        
        // 更新VM状态为已停止
        UpdateVMStatus(vmName, "stopped");
        
        std::string logPath = "/data/storage/el2/base/haps/entry/files/vms/" + vmName + "/qemu.log";
        WriteLog(logPath, "VM stopped by user request");
    }
    
    napi_get_boolean(env, true, &result);
    return result;
}

// 获取VM实时日志
static napi_value GetVmLogs(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing VM name parameter");
        return nullptr;
    }
    
    // 获取VM名称
    std::string vmName;
    if (!NapiGetStringUtf8(env, argv[0], vmName)) {
        napi_throw_error(env, nullptr, "Failed to get VM name");
        return nullptr;
    }
    
    // 获取起始行数（可选参数）
    int32_t startLine = 0;
    if (argc >= 2) {
        napi_get_value_int32(env, argv[1], &startLine);
    }
    
    napi_value result;
    napi_create_array(env, &result);
    
    // 获取日志缓冲区
    if (g_vmLogBuffers.find(vmName) != g_vmLogBuffers.end()) {
        std::lock_guard<std::mutex> lock(g_vmLogMutexes[vmName]);
        const auto& buffer = g_vmLogBuffers[vmName];
        
        // 确保起始行数有效
        size_t start = std::max(0, std::min(startLine, (int32_t)buffer.size()));
        
        for (size_t i = start; i < buffer.size(); i++) {
            napi_value logEntry;
            napi_create_string_utf8(env, buffer[i].c_str(), NAPI_AUTO_LENGTH, &logEntry);
            napi_set_element(env, result, i - start, logEntry);
        }
    }
    
    return result;
}

// 获取VM状态
static napi_value GetVmStatus(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing VM name parameter");
        return nullptr;
    }
    
    // 获取VM名称
    std::string vmName;
    if (!NapiGetStringUtf8(env, argv[0], vmName)) {
        napi_throw_error(env, nullptr, "Failed to get VM name");
        return nullptr;
    }
    
    napi_value result;
    napi_create_string_utf8(env, "stopped", NAPI_AUTO_LENGTH, &result);
    
    // 检查运行状态
    if (g_vmRunning.find(vmName) != g_vmRunning.end() && g_vmRunning[vmName]->load()) {
        napi_create_string_utf8(env, "running", NAPI_AUTO_LENGTH, &result);
    }
    
    return result;
}

// 创建RDP客户端
static napi_value CreateRdpClient(napi_env env, napi_callback_info info) {
    (void)info;  // 添加
    napi_value result;
    napi_create_object(env, &result);
    
    // 生成唯一的客户端ID
    static int client_counter = 0;
    std::string client_id = "rdp_client_" + std::to_string(++client_counter);
    
    // 创建RDP客户端
    rdp_client_handle_t client = rdp_client_create();
    
    // 存储客户端句柄
    {
        std::lock_guard<std::mutex> lock(g_rdp_mutex);
        g_rdp_clients[client_id] = client;
    }
    
    // 设置客户端ID
    napi_value id_value;
    napi_create_string_utf8(env, client_id.c_str(), NAPI_AUTO_LENGTH, &id_value);
    napi_set_named_property(env, result, "id", id_value);
    
    return result;
}

// 连接RDP
static napi_value ConnectRdp(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Missing parameters: clientId and config");
        return nullptr;
    }
    
    // 获取客户端ID
    std::string client_id;
    if (!NapiGetStringUtf8(env, argv[0], client_id)) {
        napi_throw_error(env, nullptr, "Failed to get client ID");
        return nullptr;
    }
    
    // 获取配置对象
    napi_value config = argv[1];
    
    // 解析配置参数
    rdp_connection_config_t rdp_config = {};
    
    // 主机地址
    std::string hostStr;
    napi_value host_value;
    if (napi_get_named_property(env, config, "host", &host_value) == napi_ok) {
        NapiGetStringUtf8(env, host_value, hostStr);
        if (!hostStr.empty()) rdp_config.host = hostStr.c_str();
    }
    
    // 端口
    napi_value port_value;
    if (napi_get_named_property(env, config, "port", &port_value) == napi_ok) {
        int32_t port;
        if (napi_get_value_int32(env, port_value, &port) == napi_ok) {
            rdp_config.port = port;
        }
    }
    
    // 用户名
    std::string usernameStr;
    napi_value username_value;
    if (napi_get_named_property(env, config, "username", &username_value) == napi_ok) {
        NapiGetStringUtf8(env, username_value, usernameStr);
        if (!usernameStr.empty()) rdp_config.username = usernameStr.c_str();
    }
    
    // 密码
    std::string passwordStr;
    napi_value password_value;
    if (napi_get_named_property(env, config, "password", &password_value) == napi_ok) {
        NapiGetStringUtf8(env, password_value, passwordStr);
        if (!passwordStr.empty()) rdp_config.password = passwordStr.c_str();
    }
    
    // 显示设置
    napi_value width_value;
    if (napi_get_named_property(env, config, "width", &width_value) == napi_ok) {
        int32_t width;
        if (napi_get_value_int32(env, width_value, &width) == napi_ok) {
            rdp_config.width = width;
        }
    }
    
    napi_value height_value;
    if (napi_get_named_property(env, config, "height", &height_value) == napi_ok) {
        int32_t height;
        if (napi_get_value_int32(env, height_value, &height) == napi_ok) {
            rdp_config.height = height;
        }
    }
    
    // 查找客户端
    rdp_client_handle_t client = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_rdp_mutex);
        if (g_rdp_clients.find(client_id) != g_rdp_clients.end()) {
            client = g_rdp_clients[client_id];
        }
    }
    
    if (!client) {
        napi_throw_error(env, nullptr, "RDP client not found");
        return nullptr;
    }
    
    // 尝试连接
    int result = rdp_client_connect(client, &rdp_config);
    
    napi_value result_value;
    napi_create_int32(env, result, &result_value);
    
    return result_value;
}

// 断开RDP连接
static napi_value DisconnectRdp(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing client ID parameter");
        return nullptr;
    }
    
    // 获取客户端ID
    std::string client_id;
    if (!NapiGetStringUtf8(env, argv[0], client_id)) {
        napi_throw_error(env, nullptr, "Failed to get client ID");
        return nullptr;
    }
    
    // 查找并断开客户端
    {
        std::lock_guard<std::mutex> lock(g_rdp_mutex);
        if (g_rdp_clients.find(client_id) != g_rdp_clients.end()) {
            rdp_client_disconnect(g_rdp_clients[client_id]);
        }
    }
    
    napi_value result;
    napi_create_int32(env, 0, &result);
    return result;
}

// 获取RDP连接状态
static napi_value GetRdpStatus(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing client ID parameter");
        return nullptr;
    }
    
    // 获取客户端ID
    std::string client_id;
    if (!NapiGetStringUtf8(env, argv[0], client_id)) {
        napi_throw_error(env, nullptr, "Failed to get client ID");
        return nullptr;
    }
    
    // 查找客户端
    rdp_client_handle_t client = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_rdp_mutex);
        if (g_rdp_clients.find(client_id) != g_rdp_clients.end()) {
            client = g_rdp_clients[client_id];
        }
    }
    
    if (!client) {
        napi_throw_error(env, nullptr, "RDP client not found");
        return nullptr;
    }
    
    // 获取状态
    rdp_connection_state_t state = rdp_client_get_state(client);
    
    napi_value result;
    napi_create_int32(env, static_cast<int32_t>(state), &result);
    
    return result;
}

// 检测核心库存在性（真实检测，不加载到全局）
static napi_value CheckCoreLib(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_create_object(env, &result);

    auto set_bool = [&](const char* name, bool v){ napi_value b; napi_get_boolean(env, v, &b); napi_set_named_property(env, result, name, b); };
    auto set_str = [&](const char* name, const std::string& s){ napi_value v; napi_create_string_utf8(env, s.c_str(), NAPI_AUTO_LENGTH, &v); napi_set_named_property(env, result, name, v); };

    // 已加载到全局？
    set_bool("loaded", g_qemu_core_main != nullptr);

    // 1) 直接从默认搜索路径
    {
        void* h1 = dlopen("libqemu_full.so", RTLD_LAZY);
        set_bool("foundLd", h1 != nullptr);
        if (!h1) {
            const char* err = dlerror();
            set_str("errLd", err ? std::string(err) : std::string(""));
        } else {
            // 尝试获取符号
            void* sym = dlsym(h1, "qemu_main");
            set_bool("symFound", sym != nullptr);
            if (!sym) {
                const char* err = dlerror();
                set_str("symErr", err ? std::string(err) : std::string(""));
            }
            dlclose(h1);
        }
    }

    // 2) 从自身同目录（通过 dladdr 定位当前 so 所在目录）
    {
        Dl_info info{};
        std::string selfDir;
        if (dladdr((void*)&CheckCoreLib, &info) != 0 && info.dli_fname) {
            std::string soPath = info.dli_fname;
            // 提取目录部分
            auto pos = soPath.find_last_of('/') ;
            if (pos != std::string::npos) {
                selfDir = soPath.substr(0, pos);
            }
        }
        set_str("selfDir", selfDir);
        bool foundSelf = false;
        if (!selfDir.empty()) {
            std::string abs = selfDir + "/libqemu_full.so";
            void* h2 = dlopen(abs.c_str(), RTLD_LAZY);
            foundSelf = (h2 != nullptr);
            set_bool("foundSelfDir", foundSelf);
            if (!h2) {
                const char* err = dlerror();
                set_str("errSelfDir", err ? std::string(err) : std::string(""));
            } else {
                dlclose(h2);
            }
        } else {
            set_bool("foundSelfDir", false);
        }
    }

    // 3) 从 files 目录
    std::string filesPath = "/data/storage/el2/base/haps/entry/files/libqemu_full.so";
    bool existsFiles = FileExists(filesPath);
    set_bool("existsFilesPath", existsFiles);
    set_str("filesPath", filesPath);
    bool foundFiles = false;
    if (existsFiles) {
        void* h3 = dlopen(filesPath.c_str(), RTLD_LAZY);
        foundFiles = (h3 != nullptr);
        set_bool("foundFiles", foundFiles);
        if (!h3) {
            const char* err = dlerror();
            set_str("errFiles", err ? std::string(err) : std::string(""));
        } else {
            dlclose(h3);
        }
    } else {
        set_bool("foundFiles", false);
    }

    return result;
}

// 销毁RDP客户端
static napi_value DestroyRdpClient(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Missing client ID parameter");
        return nullptr;
    }
    
    // 获取客户端ID
    std::string client_id;
    if (!NapiGetStringUtf8(env, argv[0], client_id)) {
        napi_throw_error(env, nullptr, "Failed to get client ID");
        return nullptr;
    }
    
    // 查找并销毁客户端
    {
        std::lock_guard<std::mutex> lock(g_rdp_mutex);
        if (g_rdp_clients.find(client_id) != g_rdp_clients.end()) {
            rdp_client_destroy(g_rdp_clients[client_id]);
            g_rdp_clients.erase(client_id);
        }
    }
    
    napi_value result;
    napi_create_int32(env, 0, &result);
    return result;
}

// ----------------------------- Native VNC (LibVNCClient) -----------------------------
#ifdef LIBVNC_HAVE_CLIENT
#include "third_party/libvncclient/include/rfb/rfbclient.h"
#endif

static std::mutex g_vnc_mutex;
static int g_vnc_next_id = 1;

struct VncSession {
    int id{0};
#ifdef LIBVNC_HAVE_CLIENT
    rfbClient* client{nullptr};
#endif
    std::thread worker;
    std::atomic<bool> running{false};
    int width{0};
    int height{0};
    std::vector<uint8_t> frame; // RGBA8888
    std::mutex mtx;
};

static std::map<int, std::unique_ptr<VncSession>> g_vnc_sessions;

static napi_value VncAvailable(napi_env env, napi_callback_info info) {
    (void)info;  // 添加
    napi_value out;
#ifdef LIBVNC_HAVE_CLIENT
    napi_get_boolean(env, true, &out);
#else
    napi_get_boolean(env, false, &out);
#endif
    return out;
}

static napi_value VncCreate(napi_env env, napi_callback_info info) {
    (void)info;  // 添加
    std::lock_guard<std::mutex> lock(g_vnc_mutex);
    int id = g_vnc_next_id++;
    auto s = std::make_unique<VncSession>();
    s->id = id;
    g_vnc_sessions[id] = std::move(s);
    napi_value out; napi_create_int32(env, id, &out); return out;
}

#ifdef LIBVNC_HAVE_CLIENT
static rfbBool VncMallocFB(rfbClient* cl)
{
    if (!cl) return false;
    // Ensure 32bpp
    cl->format.bitsPerPixel = 32;
    cl->format.depth = 24;
    cl->format.bigEndian = 0;
    cl->format.trueColour = 1;
    cl->format.redMax = 255; cl->format.greenMax = 255; cl->format.blueMax = 255;
    cl->format.redShift = 16; cl->format.greenShift = 8; cl->format.blueShift = 0;

    const int w = cl->width;
    const int h = cl->height;
    const size_t bytes = (size_t)w * (size_t)h * 4;
    if (cl->frameBuffer) free(cl->frameBuffer);
    cl->frameBuffer = (uint8_t*)malloc(bytes);
    if (!cl->frameBuffer) return false;

    // Find our session by matching pointer
    std::lock_guard<std::mutex> lock(g_vnc_mutex);
    for (auto& kv : g_vnc_sessions) {
        if (kv.second->client == cl) {
            std::lock_guard<std::mutex> lk(kv.second->mtx);
            kv.second->width = w;
            kv.second->height = h;
            kv.second->frame.resize(bytes);
            break;
        }
    }
    return true;
}

static void VncGotUpdate(rfbClient* cl, int x, int y, int w, int h)
{
    (void)x; (void)y; (void)w; (void)h; // unused parameters
    if (!cl || !cl->frameBuffer) return;
    std::lock_guard<std::mutex> lock(g_vnc_mutex);
    for (auto& kv : g_vnc_sessions) {
        auto& s = kv.second;
        if (s->client == cl) {
            std::lock_guard<std::mutex> lk(s->mtx);
            if (s->width != cl->width || s->height != cl->height) {
                s->width = cl->width; s->height = cl->height; s->frame.resize((size_t)s->width * s->height * 4);
            }
            // Copy entire framebuffer for simplicity
            size_t bytes = (size_t)cl->width * cl->height * 4;
            if (s->frame.size() >= bytes) {
                std::memcpy(s->frame.data(), cl->frameBuffer, bytes);
            }
            break;
        }
    }
}

static void VncWorker(VncSession* s)
{
    if (!s || !s->client) return;
    s->running.store(true);
    while (s->running.load()) {
        int ret = WaitForMessage(s->client, 100000); // 100ms
        if (ret < 0) break;
        if (ret > 0) {
            if (!HandleRFBServerMessage(s->client)) {
                break;
            }
        }
    }
    s->running.store(false);
}
#endif

static napi_value VncConnect(napi_env env, napi_callback_info info) {
    size_t argc = 3; napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value out; napi_get_boolean(env, false, &out);
    if (argc < 3) return out;
    int32_t id = 0; napi_get_value_int32(env, argv[0], &id);
    std::string host; if (!NapiGetStringUtf8(env, argv[1], host)) return out;
    int32_t port = 0; napi_get_value_int32(env, argv[2], &port);

    VncSession* s = nullptr; // unused placeholder
    {
        std::lock_guard<std::mutex> lock(g_vnc_mutex);
        if (g_vnc_sessions.find(id) == g_vnc_sessions.end()) return out;
    }

#ifdef LIBVNC_HAVE_CLIENT
    s = g_vnc_sessions[id].get();
    if (s->worker.joinable()) { s->running.store(false); s->worker.join(); }
    if (s->client) { rfbClientCleanup(s->client); s->client = nullptr; }

    rfbClient* cl = rfbGetClient(8, 3, 4); // 32-bit truecolor
    if (!cl) return out;
    cl->MallocFrameBuffer = VncMallocFB;
    cl->GotFrameBufferUpdate = VncGotUpdate;
    cl->canHandleNewFBSize = 1;
    cl->appData.shareDesktop = TRUE;
    cl->serverHost = strdup(host.c_str());
    cl->serverPort = port;

    if (!rfbClientConnect(cl)) {
        rfbClientCleanup(cl);
        return out;
    }
    if (!rfbClientInitialise(cl)) {
        rfbClientCleanup(cl);
        return out;
    }

    {
        std::lock_guard<std::mutex> lock(g_vnc_mutex);
        s->client = cl;
        s->worker = std::thread(VncWorker, s);
    }
    napi_get_boolean(env, true, &out);
#else
    (void)host; (void)port;
    // Client lib not available
#endif
    return out;
}

static napi_value VncDisconnect(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) return nullptr;
    int32_t id = 0; napi_get_value_int32(env, argv[0], &id);
    VncSession* sess = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_vnc_mutex);
        auto it = g_vnc_sessions.find(id);
        if (it != g_vnc_sessions.end()) {
            sess = it->second.get();
            if (sess) sess->running.store(false);
        }
    }
    if (sess) {
        if (sess->worker.joinable()) sess->worker.join();
#ifdef LIBVNC_HAVE_CLIENT
        if (sess->client) { rfbClientCleanup(sess->client); sess->client = nullptr; }
#endif
    }
    napi_value out; napi_get_boolean(env, true, &out); return out;
}

static napi_value VncGetFrame(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value outNull; napi_get_null(env, &outNull);
    if (argc < 1) return outNull;
    int32_t id = 0; napi_get_value_int32(env, argv[0], &id);
    std::lock_guard<std::mutex> lock(g_vnc_mutex);
    auto it = g_vnc_sessions.find(id);
    if (it == g_vnc_sessions.end()) return outNull;
    auto& s = it->second;
    std::lock_guard<std::mutex> lk(s->mtx);
    if (s->width <= 0 || s->height <= 0 || s->frame.empty()) return outNull;

    napi_value obj; napi_create_object(env, &obj);
    napi_value w, h; napi_create_int32(env, s->width, &w); napi_create_int32(env, s->height, &h);
    napi_set_named_property(env, obj, "width", w);
    napi_set_named_property(env, obj, "height", h);

    void* data = nullptr; size_t len = s->frame.size();
    napi_value ab;
    napi_create_arraybuffer(env, len, &data, &ab);
    if (data && len) std::memcpy(data, s->frame.data(), len);
    napi_set_named_property(env, obj, "pixels", ab);
    return obj;
}
// --------------------------------------------------------------------------------------------

static napi_value TestFunction(napi_env env, napi_callback_info info) {
    HilogPrint("QEMU: TestFunction called!");
    HilogPrint("QEMU: TestFunction - NAPI module is working correctly!");
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// 添加一个简单的模块信息函数
static napi_value GetModuleInfo(napi_env env, napi_callback_info info) {
    HilogPrint("QEMU: GetModuleInfo called!");
    napi_value result;
    napi_create_object(env, &result);
    
    napi_value name, version, status;
    napi_create_string_utf8(env, "qemu_hmos", NAPI_AUTO_LENGTH, &name);
    napi_create_string_utf8(env, "1.0.0", NAPI_AUTO_LENGTH, &version);
    napi_create_string_utf8(env, "loaded", NAPI_AUTO_LENGTH, &status);
    
    napi_set_named_property(env, result, "name", name);
    napi_set_named_property(env, result, "version", version);
    napi_set_named_property(env, result, "status", status);
    
    return result;
}

// 模块初始化
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    HilogPrint("QEMU: NAPI Init function called!");
    HilogPrint("QEMU: Environment pointer: " + std::to_string(reinterpret_cast<uintptr_t>(env)));
    HilogPrint("QEMU: Exports pointer: " + std::to_string(reinterpret_cast<uintptr_t>(exports)));
#if defined(__OHOS__)
    napi_property_descriptor desc[] = {
        { "version", 0, GetVersion, 0, 0, 0, napi_default, 0 },
        { "enableJit", 0, EnableJit, 0, 0, 0, napi_default, 0 },
        { "kvmSupported", 0, KvmSupported, 0, 0, 0, napi_default, 0 },
        { "startVm", 0, StartVm, 0, 0, 0, napi_default, 0 },
        { "stopVm", 0, StopVm, 0, 0, 0, napi_default, 0 },
        { "getVmLogs", 0, GetVmLogs, 0, 0, 0, napi_default, 0 },
        { "getVmStatus", 0, GetVmStatus, 0, 0, 0, napi_default, 0 },
        { "checkCoreLib", 0, CheckCoreLib, 0, 0, 0, napi_default, 0 },
        { "getDeviceCapabilities", 0, GetDeviceCapabilities, 0, 0, 0, napi_default, 0 },
        { "pauseVm", 0, PauseVm, 0, 0, 0, napi_default, 0 },
        { "resumeVm", 0, ResumeVm, 0, 0, 0, napi_default, 0 },
        { "createSnapshot", 0, CreateSnapshot, 0, 0, 0, napi_default, 0 },
        { "restoreSnapshot", 0, RestoreSnapshot, 0, 0, 0, napi_default, 0 },
        { "listSnapshots", 0, ListSnapshots, 0, 0, 0, napi_default, 0 },
        { "deleteSnapshot", 0, DeleteSnapshot, 0, 0, 0, napi_default, 0 },
        { "createRdpClient", 0, CreateRdpClient, 0, 0, 0, napi_default, 0 },
        { "connectRdp", 0, ConnectRdp, 0, 0, 0, napi_default, 0 },
        { "disconnectRdp", 0, DisconnectRdp, 0, 0, 0, napi_default, 0 },
        { "getRdpStatus", 0, GetRdpStatus, 0, 0, 0, napi_default, 0 },
        { "destroyRdpClient", 0, DestroyRdpClient, 0, 0, 0, napi_default, 0 },
        // Native VNC (client)
        { "vncAvailable", 0, VncAvailable, 0, 0, 0, napi_default, 0 },
        { "vncCreate", 0, VncCreate, 0, 0, 0, napi_default, 0 },
        { "vncConnect", 0, VncConnect, 0, 0, 0, napi_default, 0 },
        { "vncDisconnect", 0, VncDisconnect, 0, 0, 0, napi_default, 0 },
        { "vncGetFrame", 0, VncGetFrame, 0, 0, 0, napi_default, 0 },
        { "testFunction", 0, TestFunction, 0, 0, 0, napi_default, 0 },
        { "getModuleInfo", 0, GetModuleInfo, 0, 0, 0, napi_default, 0 },
    };
#else
    napi_property_descriptor__ desc[] = {
        { "version", GetVersion, 0 },
        { "enableJit", EnableJit, 0 },
        { "kvmSupported", KvmSupported, 0 },
        { "startVm", StartVm, 0 },
        { "stopVm", StopVm, 0 },
        { "getVmLogs", GetVmLogs, 0 },
        { "getVmStatus", GetVmStatus, 0 },
        { "checkCoreLib", CheckCoreLib, 0 },
        { "createRdpClient", CreateRdpClient, 0 },
        { "connectRdp", ConnectRdp, 0 },
        { "disconnectRdp", DisconnectRdp, 0 },
        { "getRdpStatus", GetRdpStatus, 0 },
        { "destroyRdpClient", DestroyRdpClient, 0 },
        // Native VNC (client)
        { "vncAvailable", VncAvailable, 0 },
        { "vncCreate", VncCreate, 0 },
        { "vncConnect", VncConnect, 0 },
        { "vncDisconnect", VncDisconnect, 0 },
        { "vncGetFrame", VncGetFrame, 0 },
        { "testFunction", TestFunction, 0 },
        { "getModuleInfo", GetModuleInfo, 0 },
    };
#endif
    size_t count = sizeof(desc) / sizeof(desc[0]);
#if defined(__OHOS__)
    napi_define_properties(env, exports, count, desc);
#else
    napi_define_properties(env, exports, count, (const napi_property_descriptor*)desc);
#endif
    return exports;
}
EXTERN_C_END

#if defined(__OHOS__)
// HarmonyOS NAPI 模块注册 - 使用标准方式
static napi_module g_qemu_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    // 使用简化的模块名，避免.so扩展名
    .nm_modname = "qemu_hmos",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

// 使用标准的NAPI模块注册宏
NAPI_MODULE(qemu_hmos, Init)

// 备用构造函数注册（如果宏不工作）
extern "C" __attribute__((constructor)) void NAPI_qemu_hmos_Register(void)
{
    // 通过 HILOG 明确记录模块被加载/注册，用于现场诊断
    HilogPrint("QEMU: NAPI module constructor running, registering qemu_hmos");
    napi_module_register(&g_qemu_module);
}
#else
static napi_module_simple qemuModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "qemu_hmos",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};
extern "C" __attribute__((constructor)) void RegisterQemuModule(void) {
    napi_module_register(&qemuModule);
}
#endif
