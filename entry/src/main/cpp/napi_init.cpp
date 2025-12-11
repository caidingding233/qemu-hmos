#include "napi_compat.h"
#include "qemu_wrapper.h"
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
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
#include <hilog/log.h>
// 定义日志 domain 和 tag
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xA00000
#define LOG_TAG "QEMU_NAPI"

// 早期初始化已禁用 - 避免与 HarmonyOS 运行时冲突
// __attribute__((constructor(101))) static void qemu_so_loaded(void) {
//     OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, ">>> libqemu_hmos.so LOADED <<<");
// }
#endif
#include <vector>

// 前向声明：qemu_wrapper.cpp 中定义的 C 函数
extern "C" {
    bool qemu_pause_vm_by_name(const char* vm_name);
    bool qemu_resume_vm_by_name(const char* vm_name);
    bool qemu_create_snapshot_by_name(const char* vm_name, const char* snapshot_name);
    bool qemu_restore_snapshot_by_name(const char* vm_name, const char* snapshot_name);
    int qemu_list_snapshots_by_name(const char* vm_name, char** out_snapshots, int max_count);
    bool qemu_delete_snapshot_by_name(const char* vm_name, const char* snapshot_name);
}

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
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
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

// 全局控制台回调
static napi_threadsafe_function g_consoleCallback = nullptr;

// JS 回调包装器
static void ConsoleJsCallback(napi_env env, napi_value js_cb, void* context, void* data) {
    std::string* msg = static_cast<std::string*>(data);
    if (!msg) return;
    
    napi_value undefined, js_string;
    napi_get_undefined(env, &undefined);
    napi_create_string_utf8(env, msg->c_str(), msg->length(), &js_string);
    napi_call_function(env, undefined, js_cb, 1, &js_string, nullptr);
    
    delete msg;
}

// 捕获 stdout/stderr 并重定向到 hilog
class CaptureQemuOutput {
public:
    CaptureQemuOutput() {
        // 创建管道
        if (pipe(stdout_pipe) == -1 || pipe(stderr_pipe) == -1 || pipe(stdin_pipe) == -1) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to create pipes");
            return;
        }

        // 保存原始文件描述符
        stdout_backup = dup(STDOUT_FILENO);
        stderr_backup = dup(STDERR_FILENO);
        stdin_backup = dup(STDIN_FILENO);

        // 重定向 stdout/stderr 到管道写端
        if (dup2(stdout_pipe[1], STDOUT_FILENO) == -1 || dup2(stderr_pipe[1], STDERR_FILENO) == -1) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to dup2 stdout/stderr");
            return;
        }
        
        // 重定向 stdin 到管道读端
        if (dup2(stdin_pipe[0], STDIN_FILENO) == -1) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to dup2 stdin");
            return;
        }

        // 启动读取线程
        running = true;
        stdout_thread = std::thread(&CaptureQemuOutput::ReadThread, this, stdout_pipe[0], "QEMU_STDOUT");
        stderr_thread = std::thread(&CaptureQemuOutput::ReadThread, this, stderr_pipe[0], "QEMU_STDERR");
        
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "QEMU output capture started");
    }

    ~CaptureQemuOutput() {
        running = false;
        
        // 恢复原始文件描述符
        dup2(stdout_backup, STDOUT_FILENO);
        dup2(stderr_backup, STDERR_FILENO);
        dup2(stdin_backup, STDIN_FILENO);
        
        close(stdout_backup);
        close(stderr_backup);
        close(stdin_backup);
        
        close(stdout_pipe[1]); // 关闭写端，这将导致读端 EOF
        close(stderr_pipe[1]);
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);

        if (stdout_thread.joinable()) stdout_thread.join();
        if (stderr_thread.joinable()) stderr_thread.join();
        
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        
        // 释放回调
        if (g_consoleCallback) {
            napi_release_threadsafe_function(g_consoleCallback, napi_tsfn_abort);
            g_consoleCallback = nullptr;
        }
    }
    
    void WriteToStdin(const std::string& data) {
        if (stdin_pipe[1] != -1) {
            write(stdin_pipe[1], data.c_str(), data.length());
            // 不需要 fsync，管道通常是无缓冲的或行缓冲的
        }
    }

private:
    int stdout_pipe[2];
    int stderr_pipe[2];
    int stdin_pipe[2];
    int stdout_backup;
    int stderr_backup;
    int stdin_backup;
    std::thread stdout_thread;
    std::thread stderr_thread;
    std::atomic<bool> running;

    void ReadThread(int fd, const char* tag) {
        char buffer[1024];
        ssize_t n;
        while (running) {
            n = read(fd, buffer, sizeof(buffer) - 1);
            if (n > 0) {
                buffer[n] = '\0';
                
                // 发送给 JS (需要在 hilog 之前，保留换行符)
                if (g_consoleCallback) {
                    std::string* msg = new std::string(buffer);
                    napi_call_threadsafe_function(g_consoleCallback, msg, napi_tsfn_nonblocking);
                }
                
                // 移除换行符，hilog 会自动添加
                if (buffer[n-1] == '\n') buffer[n-1] = '\0';
                OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "[%s] %s", tag, buffer);
            } else if (n == 0) {
                break; // EOF
            } else {
                if (errno != EAGAIN && errno != EINTR) break;
            }
        }
    }
};

// 全局唯一实例
static std::unique_ptr<CaptureQemuOutput> g_logCapture;

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
    std::string sharedDir;       // 共享目录路径（virtio-9p）
    std::string efiFirmware;     // UEFI 固件路径
    std::string qemuDataDir;     // QEMU数据目录（包含keymaps，由ArkTS KeymapsManager提供）
    bool keymapsAvailable;       // ArkTS 是否已确认 keymaps 存在
    // 高级硬件配置（由 ArkTS 创建向导传入）
    std::string machine;         // 机器类型（如 virt、raspi3b）
    std::string displayDevice;   // 显卡设备（virtio-gpu、ramfb、none）
    std::string networkDevice;   // 网卡设备（virtio-net、e1000、rtl8139、none）
    std::string audioDevice;     // 声卡设备（hda、ac97、none）
};

// VM状态管理
static std::map<std::string, std::thread> g_vmThreads;
static std::map<std::string, std::atomic<bool>*> g_vmRunning;
static std::map<std::string, std::vector<std::string>> g_vmLogBuffers;
static std::map<std::string, std::mutex> g_vmLogMutexes;
static std::mutex g_vmMutex;

// 全局变量用于控制VM运行状态
// 使用显式构造避免静态初始化问题
static std::atomic<bool> g_qemu_shutdown_requested(false);
static std::string g_current_vm_name;
static std::string g_current_log_path;
static std::string g_current_arch_type;  // 当前 VM 的架构类型 (aarch64, x86_64, i386)

// VM 启动错误码
enum class VmStartError {
    SUCCESS = 0,
    CORE_LIB_MISSING = 1,
    INIT_FAILED = 2,
    LOOP_CRASHED = 3,
    DISK_CREATE_FAILED = 4,
    CONFIG_FAILED = 5,
    ALREADY_RUNNING = 6
};

// Promise 回调数据结构
struct VmStartCallbackData {
    napi_env env;
    napi_deferred deferred;
    std::string vmName;
    VmStartError error;
    int exitCode;
    std::string errorMessage;
};

// 存储每个 VM 的 threadsafe function 和 deferred
struct VmStartContext {
    napi_threadsafe_function tsfn;
    napi_deferred deferred;
    napi_env env;
};
static std::map<std::string, VmStartContext> g_vmStartCallbacks;

// 前向声明
extern "C" int qemu_main(int argc, char **argv);
extern "C" void qemu_system_shutdown_request(int reason);
static constexpr int SHUTDOWN_CAUSE_HOST = 0;

// 前向声明 - 日志函数
static void HilogPrint(const std::string& message);
static void WriteLog(const std::string& logPath, const std::string& message);

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

// 获取设备能力信息 + 常见机器类型列表
static napi_value GetDeviceCapabilities(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_object(env, &result);

    // KVM 支持
    bool kvm_supported = kvmSupported();
    napi_value kvm_value;
    napi_get_boolean(env, kvm_supported, &kvm_value);
    napi_set_named_property(env, result, "kvmSupported", kvm_value);

    // JIT 支持
    bool jit_supported = enableJit();
    napi_value jit_value;
    napi_get_boolean(env, jit_supported, &jit_value);
    napi_set_named_property(env, result, "jitSupported", jit_value);

    // 内存信息（字节数）
    long pages = sysconf(_SC_PHYS_PAGES);
    long page_size = sysconf(_SC_PAGE_SIZE);
    long total_memory = pages * page_size;

    napi_value memory_value;
    napi_create_int64(env, total_memory, &memory_value);
    napi_set_named_property(env, result, "totalMemory", memory_value);

    // CPU 核心数
    long cpu_cores = sysconf(_SC_NPROCESSORS_ONLN);
    napi_value cores_value;
    napi_create_int64(env, cpu_cores, &cores_value);
    napi_set_named_property(env, result, "cpuCores", cores_value);

    // 常见 aarch64 机器类型列表
    // 这里使用当前构建中实际使用的一组安全机器类型，后续可以扩展为直接从 QMP query-machines 读取。
    napi_value machines_array;
    napi_create_array(env, &machines_array);

    auto append_machine = [&](uint32_t index,
                              const char* id,
                              const char* name,
                              const char* desc) {
        napi_value mobj;
        napi_create_object(env, &mobj);

        napi_value vid;
        napi_create_string_utf8(env, id, NAPI_AUTO_LENGTH, &vid);
        napi_set_named_property(env, mobj, "id", vid);

        napi_value vname;
        napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &vname);
        napi_set_named_property(env, mobj, "name", vname);

        napi_value vdesc;
        napi_create_string_utf8(env, desc, NAPI_AUTO_LENGTH, &vdesc);
        napi_set_named_property(env, mobj, "desc", vdesc);

        napi_set_element(env, machines_array, index, mobj);
    };

    append_machine(0, "virt",       "virt (推荐)",           "通用 ARM 虚拟机平台，性能与兼容性最佳");
    append_machine(1, "virt-2.12",  "virt-2.12",             "virt 2.12 兼容版本，适合部分旧系统");
    append_machine(2, "vexpress-a15","vexpress-a15",         "ARM Versatile Express A15 开发板");
    append_machine(3, "vexpress-a9","vexpress-a9",           "ARM Versatile Express A9 开发板");
    append_machine(4, "raspi3b",    "Raspberry Pi 3B",       "树莓派 3B 模拟");
    append_machine(5, "sbsa-ref",   "SBSA 参考平台",         "适合测试通用 ARM 服务器软件");

    napi_set_named_property(env, result, "machines", machines_array);

    return result;
}

// ============================================================================
// 设备扫描器：异步版本，不阻塞主线程
// ============================================================================

// 全局缓存：扫描结果
static std::string g_cached_devices_json;
static bool g_devices_scanned = false;
static std::mutex g_scan_mutex;

// 异步工作上下文
struct ScanWorkContext {
    napi_async_work work;
    napi_deferred deferred;
    bool success;
    std::string result_json;
    std::string error_msg;
};

// 在工作线程中执行扫描（不能调用 NAPI）
static void ExecuteScanWork(napi_env env, void* data) {
    (void)env;  // 工作线程中不能使用 env
    auto* ctx = static_cast<ScanWorkContext*>(data);
    
    HilogPrint("QEMU: ExecuteScanWork - Starting in worker thread...");
    
    // 检查缓存
    {
        std::lock_guard<std::mutex> lock(g_scan_mutex);
        if (g_devices_scanned && !g_cached_devices_json.empty()) {
            ctx->success = true;
            ctx->result_json = g_cached_devices_json;
            HilogPrint("QEMU: ExecuteScanWork - Using cached results");
            return;
        }
    }
    
    // 由于 QEMU 库在 HarmonyOS 上的线程限制，
    // 我们无法在工作线程中安全地启动 QEMU 实例。
    // 因此，返回一个基于 qemu-system-aarch64 文档的设备列表。
    // 用户可以在创建 VM 后通过 probeQemuDevices() 获取实际支持的设备。
    
    // 构建设备列表 JSON（基于 QEMU 9.x for aarch64 的常见设备）
    std::string json = R"({
        "return": [
            {"name": "virtio-gpu-pci", "parent": "virtio-gpu-pci-base"},
            {"name": "virtio-gpu-gl-pci", "parent": "virtio-gpu-pci-base"},
            {"name": "ramfb", "parent": "device"},
            {"name": "bochs-display", "parent": "device"},
            {"name": "virtio-vga", "parent": "virtio-gpu-device"},
            {"name": "virtio-vga-gl", "parent": "virtio-gpu-device"},
            {"name": "qxl-vga", "parent": "pci-device"},
            {"name": "VGA", "parent": "pci-device"},
            {"name": "cirrus-vga", "parent": "pci-device"},
            {"name": "secondary-vga", "parent": "device"},
            {"name": "virtio-net-pci", "parent": "virtio-net-pci-base"},
            {"name": "virtio-net-pci-non-transitional", "parent": "virtio-net-pci-base"},
            {"name": "e1000", "parent": "pci-device"},
            {"name": "e1000e", "parent": "pci-device"},
            {"name": "e1000-82544gc", "parent": "e1000"},
            {"name": "e1000-82545em", "parent": "e1000"},
            {"name": "rtl8139", "parent": "pci-device"},
            {"name": "ne2k_pci", "parent": "pci-device"},
            {"name": "pcnet", "parent": "pci-device"},
            {"name": "vmxnet3", "parent": "pci-device"},
            {"name": "usb-net", "parent": "usb-device"},
            {"name": "ich9-intel-hda", "parent": "pci-device"},
            {"name": "intel-hda", "parent": "pci-device"},
            {"name": "hda-duplex", "parent": "hda-audio"},
            {"name": "hda-micro", "parent": "hda-audio"},
            {"name": "hda-output", "parent": "hda-audio"},
            {"name": "AC97", "parent": "pci-device"},
            {"name": "es1370", "parent": "pci-device"},
            {"name": "sb16", "parent": "isa-device"},
            {"name": "adlib", "parent": "isa-device"},
            {"name": "gus", "parent": "isa-device"},
            {"name": "cs4231a", "parent": "isa-device"},
            {"name": "usb-audio", "parent": "usb-device"},
            {"name": "virtio-sound-pci", "parent": "virtio-pci"},
            {"name": "virtio-blk-pci", "parent": "virtio-blk-pci-base"},
            {"name": "virtio-scsi-pci", "parent": "virtio-scsi-pci-base"},
            {"name": "nvme", "parent": "pci-device"},
            {"name": "usb-storage", "parent": "usb-device"},
            {"name": "virtio-serial-pci", "parent": "virtio-pci"},
            {"name": "usb-kbd", "parent": "usb-device"},
            {"name": "usb-mouse", "parent": "usb-device"},
            {"name": "usb-tablet", "parent": "usb-device"},
            {"name": "virtio-keyboard-pci", "parent": "virtio-pci"},
            {"name": "virtio-mouse-pci", "parent": "virtio-pci"},
            {"name": "virtio-tablet-pci", "parent": "virtio-pci"},
            {"name": "pci-bridge", "parent": "base-pci-bridge"},
            {"name": "pcie-root-port", "parent": "pcie-port"},
            {"name": "virtio-balloon-pci", "parent": "virtio-pci"},
            {"name": "virtio-rng-pci", "parent": "virtio-pci"},
            {"name": "qemu-xhci", "parent": "pci-device"},
            {"name": "nec-usb-xhci", "parent": "pci-device"},
            {"name": "ich9-usb-ehci1", "parent": "pci-device"},
            {"name": "ich9-usb-uhci1", "parent": "pci-device"},
            {"name": "usb-ehci", "parent": "pci-device"},
            {"name": "usb-host", "parent": "usb-device"}
        ],
        "source": "static-list",
        "note": "基于 QEMU 9.x aarch64 文档的设备列表，实际可用设备需要测试"
    })";
    
    ctx->success = true;
    ctx->result_json = json;
    
    // 缓存结果
    {
        std::lock_guard<std::mutex> lock(g_scan_mutex);
        g_cached_devices_json = json;
        g_devices_scanned = true;
    }
    
    HilogPrint("QEMU: ExecuteScanWork - Returned static device list");
}

// 在主线程中完成（可以调用 NAPI）
static void CompleteScanWork(napi_env env, napi_status status, void* data) {
    auto* ctx = static_cast<ScanWorkContext*>(data);
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (status == napi_ok && ctx->success) {
        napi_value success_val, json_val;
        napi_get_boolean(env, true, &success_val);
        napi_create_string_utf8(env, ctx->result_json.c_str(), NAPI_AUTO_LENGTH, &json_val);
        napi_set_named_property(env, result, "success", success_val);
        napi_set_named_property(env, result, "rawJson", json_val);
        
        napi_resolve_deferred(env, ctx->deferred, result);
    } else {
        napi_value success_val, error_val;
        napi_get_boolean(env, false, &success_val);
        napi_create_string_utf8(env, ctx->error_msg.empty() ? "扫描失败" : ctx->error_msg.c_str(), 
                                NAPI_AUTO_LENGTH, &error_val);
        napi_set_named_property(env, result, "success", success_val);
        napi_set_named_property(env, result, "error", error_val);
        
        napi_resolve_deferred(env, ctx->deferred, result);
    }
    
    // 清理
    napi_delete_async_work(env, ctx->work);
    delete ctx;
    
    HilogPrint("QEMU: CompleteScanWork - Done");
}

// 异步扫描设备（返回 Promise）
static napi_value ScanQemuDevicesAsync(napi_env env, napi_callback_info info) {
    (void)info;
    
    HilogPrint("QEMU: ScanQemuDevicesAsync - Creating async work...");
    
    // 创建 Promise
    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);
    
    // 创建上下文
    auto* ctx = new ScanWorkContext();
    ctx->deferred = deferred;
    ctx->success = false;
    
    // 创建异步工作
    napi_value work_name;
    napi_create_string_utf8(env, "ScanQemuDevices", NAPI_AUTO_LENGTH, &work_name);
    
    napi_create_async_work(env, nullptr, work_name,
                           ExecuteScanWork, CompleteScanWork,
                           ctx, &ctx->work);
    
    // 加入队列
    napi_queue_async_work(env, ctx->work);
    
    return promise;
}

// 同步版本（兼容旧代码，直接返回缓存或静态列表）
static napi_value ScanQemuDevices(napi_env env, napi_callback_info info) {
    (void)info;
    
    napi_value result;
    napi_create_object(env, &result);
    
    HilogPrint("QEMU: ScanQemuDevices - Sync version called");
    
    // 检查缓存
    {
        std::lock_guard<std::mutex> lock(g_scan_mutex);
        if (g_devices_scanned && !g_cached_devices_json.empty()) {
            napi_value success, json;
            napi_get_boolean(env, true, &success);
            napi_create_string_utf8(env, g_cached_devices_json.c_str(), NAPI_AUTO_LENGTH, &json);
            napi_set_named_property(env, result, "success", success);
            napi_set_named_property(env, result, "rawJson", json);
            napi_set_named_property(env, result, "cached", success);
            return result;
        }
    }
    
    // 无缓存时，触发一次异步扫描，然后返回提示
    napi_value success, note;
    napi_get_boolean(env, false, &success);
    napi_create_string_utf8(env, "请使用 scanQemuDevicesAsync() 异步扫描，或等待下次调用", NAPI_AUTO_LENGTH, &note);
    napi_set_named_property(env, result, "success", success);
    napi_set_named_property(env, result, "note", note);
    
    return result;
}

// 清除设备缓存（强制重新扫描）
static napi_value ClearDeviceCache(napi_env env, napi_callback_info info) {
    (void)info;
    g_cached_devices_json.clear();
    g_devices_scanned = false;
    HilogPrint("QEMU: Device cache cleared");
    
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// 兼容旧接口：返回缓存的设备列表或提示扫描
static napi_value GetSupportedDevices(napi_env env, napi_callback_info info) {
    (void)info;
    
    napi_value result;
    napi_create_object(env, &result);

    if (g_devices_scanned && !g_cached_devices_json.empty()) {
        // 有缓存，返回缓存
        napi_value rawJson;
        napi_create_string_utf8(env, g_cached_devices_json.c_str(), NAPI_AUTO_LENGTH, &rawJson);
        napi_set_named_property(env, result, "rawJson", rawJson);
        
        napi_value note;
        napi_create_string_utf8(env, "已从缓存加载设备列表", NAPI_AUTO_LENGTH, &note);
        napi_set_named_property(env, result, "note", note);
    } else {
        // 无缓存，提示扫描
        napi_value emptyArr;
        napi_create_array_with_length(env, 0, &emptyArr);
        napi_set_named_property(env, result, "machines", emptyArr);
        napi_set_named_property(env, result, "displays", emptyArr);
        napi_set_named_property(env, result, "networks", emptyArr);
        napi_set_named_property(env, result, "audios", emptyArr);
        
        napi_value note;
        napi_create_string_utf8(env, "请先调用 scanQemuDevices() 扫描设备列表", NAPI_AUTO_LENGTH, &note);
        napi_set_named_property(env, result, "note", note);
    }

    return result;
}

// ============================================================================
// QMP 设备动态探测（从运行中的 VM 获取真实设备列表）
// 这是获取 QEMU 真正支持的设备的最可靠方式
// ============================================================================

// 通过 QMP 查询 QEMU 支持的设备类型
// 参数：vmName - 虚拟机名称（用于定位 QMP socket）
static napi_value ProbeQemuDevices(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    napi_value result;
    napi_create_object(env, &result);
    
    // 设置默认返回值
    napi_value success;
    napi_get_boolean(env, false, &success);
    napi_set_named_property(env, result, "success", success);
    
    if (argc < 1) {
        napi_value msg;
        napi_create_string_utf8(env, "需要提供虚拟机名称", NAPI_AUTO_LENGTH, &msg);
        napi_set_named_property(env, result, "error", msg);
        return result;
    }
    
    std::string vmName;
    if (!NapiGetStringUtf8(env, args[0], vmName)) {
        napi_value msg;
        napi_create_string_utf8(env, "无效的虚拟机名称", NAPI_AUTO_LENGTH, &msg);
        napi_set_named_property(env, result, "error", msg);
        return result;
    }
    
    // 构建 QMP socket 路径
    std::string qmpSocketPath = "/data/storage/el2/base/haps/entry/files/vms/" + vmName + "/qmp.sock";
    
    // 检查 QMP socket 是否存在
    struct stat st;
    if (stat(qmpSocketPath.c_str(), &st) != 0) {
        napi_value msg;
        napi_create_string_utf8(env, 
            ("QMP socket 不存在，请先启动虚拟机: " + qmpSocketPath).c_str(), 
            NAPI_AUTO_LENGTH, &msg);
        napi_set_named_property(env, result, "error", msg);
        HilogPrint("QEMU: ProbeQemuDevices - QMP socket not found: " + qmpSocketPath);
        return result;
    }
    
    // 连接 QMP socket
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) {
        napi_value msg;
        napi_create_string_utf8(env, "创建 socket 失败", NAPI_AUTO_LENGTH, &msg);
        napi_set_named_property(env, result, "error", msg);
        return result;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, qmpSocketPath.c_str(), sizeof(addr.sun_path) - 1);
    
    if (connect(sockfd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sockfd);
        napi_value msg;
        napi_create_string_utf8(env, 
            ("连接 QMP socket 失败: " + std::string(strerror(errno))).c_str(), 
            NAPI_AUTO_LENGTH, &msg);
        napi_set_named_property(env, result, "error", msg);
        HilogPrint("QEMU: ProbeQemuDevices - connect failed: " + std::string(strerror(errno)));
        return result;
    }
    
    HilogPrint("QEMU: ProbeQemuDevices - connected to QMP socket");
    
    // 读取 QMP 欢迎消息
    char buffer[4096];
    ssize_t n = read(sockfd, buffer, sizeof(buffer) - 1);
    if (n > 0) {
        buffer[n] = '\0';
        HilogPrint(std::string("QEMU: QMP greeting: ") + buffer);
    }
    
    // 发送 qmp_capabilities 命令（必须先执行）
    const char* capCmd = "{\"execute\": \"qmp_capabilities\"}\n";
    write(sockfd, capCmd, strlen(capCmd));
    n = read(sockfd, buffer, sizeof(buffer) - 1);
    if (n > 0) buffer[n] = '\0';
    
    // 发送 qom-list-types 命令查询设备类型
    const char* listCmd = "{\"execute\": \"qom-list-types\", \"arguments\": {\"implements\": \"device\"}}\n";
    write(sockfd, listCmd, strlen(listCmd));
    
    // 读取响应
    std::string response;
    while ((n = read(sockfd, buffer, sizeof(buffer) - 1)) > 0) {
        buffer[n] = '\0';
        response += buffer;
        if (response.find("\"return\"") != std::string::npos || 
            response.find("\"error\"") != std::string::npos) {
            break;
        }
    }
    
    close(sockfd);
    
    HilogPrint("QEMU: ProbeQemuDevices - response length: " + std::to_string(response.size()));
    
    // 返回原始 QMP 响应（让 ArkTS 层解析 JSON）
    napi_get_boolean(env, true, &success);
    napi_set_named_property(env, result, "success", success);
    
    napi_value respVal;
    napi_create_string_utf8(env, response.c_str(), NAPI_AUTO_LENGTH, &respVal);
    napi_set_named_property(env, result, "qmpResponse", respVal);
    
    napi_value pathVal;
    napi_create_string_utf8(env, qmpSocketPath.c_str(), NAPI_AUTO_LENGTH, &pathVal);
    napi_set_named_property(env, result, "qmpSocket", pathVal);
    
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
    
    // 调用真正的暂停实现
    bool success = qemu_pause_vm_by_name(vm_name);
    
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
    
    // 调用真正的恢复实现
    bool success = qemu_resume_vm_by_name(vm_name);
    
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
    
    // 调用真正的快照创建实现
    bool success = qemu_create_snapshot_by_name(vm_name, snapshot_name);
    
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
    
    // 调用真正的快照恢复实现
    bool success = qemu_restore_snapshot_by_name(vm_name, snapshot_name);
    
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
    
    // 调用真正的快照列表实现
    const int max_snapshots = 64;
    char* snapshot_names[64] = {nullptr};
    int count = qemu_list_snapshots_by_name(vm_name, snapshot_names, max_snapshots);
    
    napi_value result;
    napi_create_array_with_length(env, count, &result);
    
    for (int i = 0; i < count; i++) {
        napi_value snapshot;
        if (snapshot_names[i]) {
            napi_create_string_utf8(env, snapshot_names[i], NAPI_AUTO_LENGTH, &snapshot);
            free(snapshot_names[i]);  // 释放 strdup 分配的内存
        } else {
            napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &snapshot);
        }
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
    
    // 调用真正的快照删除实现
    bool success = qemu_delete_snapshot_by_name(vm_name, snapshot_name);
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 解析VM配置参数
static VMConfig ParseVMConfig(napi_env env, napi_value config, bool &ok) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_PARSE", ">>> ParseVMConfig 开始 <<<");
    
    VMConfig vmConfig = {};
    ok = false;
    
    // 检查 config 参数是否有效
    napi_valuetype configType;
    if (napi_typeof(env, config, &configType) != napi_ok || configType != napi_object) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_PARSE", ">>> 配置参数无效或不是对象 <<<");
        return vmConfig;
    }
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_PARSE", ">>> 配置参数类型检查通过 <<<");
    
    // 获取name
    napi_value nameValue;
    if (napi_get_named_property(env, config, "name", &nameValue) != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_PARSE", ">>> 获取 name 属性失败 <<<");
        HilogPrint("QEMU: ParseVMConfig failed - cannot get name property");
        return vmConfig;
    }
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_PARSE", ">>> 获取 name 属性成功，准备读取字符串 <<<");
    
    if (!NapiGetStringUtf8(env, nameValue, vmConfig.name)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_PARSE", ">>> 读取 name 字符串失败 <<<");
        HilogPrint("QEMU: ParseVMConfig failed - cannot get name string");
        return vmConfig;
    }
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_PARSE", ">>> name = %{public}s <<<", vmConfig.name.c_str());
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
    // ============ 获取配置值并强制安全默认值 ============
    napi_value diskSizeValue, memoryValue, cpuValue;
    
    // 磁盘大小
    vmConfig.diskSizeGB = 32; // 安全默认值
    if (napi_get_named_property(env, config, "diskSizeGB", &diskSizeValue) == napi_ok) {
        int32_t diskVal = 0;
        napi_get_value_int32(env, diskSizeValue, &diskVal);
        if (diskVal > 0) {
            vmConfig.diskSizeGB = diskVal;
        }
    }
    
    // 内存大小 - 最小 512MB，默认 2048MB
    vmConfig.memoryMB = 2048; // 安全默认值
    if (napi_get_named_property(env, config, "memoryMB", &memoryValue) == napi_ok) {
        int32_t memVal = 0;
        napi_get_value_int32(env, memoryValue, &memVal);
        if (memVal >= 512) {
            vmConfig.memoryMB = memVal;
        } else if (memVal > 0) {
            vmConfig.memoryMB = 512; // 强制最小值
            HilogPrint("QEMU: Warning - memoryMB too small, using 512MB minimum");
        }
    }
    
    // CPU 核心数 - 最小 1，默认 2
    vmConfig.cpuCount = 2; // 安全默认值
    if (napi_get_named_property(env, config, "cpuCount", &cpuValue) == napi_ok) {
        int32_t cpuVal = 0;
        napi_get_value_int32(env, cpuValue, &cpuVal);
        if (cpuVal >= 1) {
            vmConfig.cpuCount = cpuVal;
        } else {
            HilogPrint("QEMU: Warning - cpuCount invalid, using 2 cores default");
        }
    }
    
    // 打印最终使用的配置值
    HilogPrint("QEMU: VM config - CPU=" + std::to_string(vmConfig.cpuCount) + 
               " MEM=" + std::to_string(vmConfig.memoryMB) + "MB" +
               " DISK=" + std::to_string(vmConfig.diskSizeGB) + "GB");
    
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
    
    // 获取 UEFI 固件路径（可选）
    napi_value efiFirmwareValue;
    if (napi_get_named_property(env, config, "efiFirmware", &efiFirmwareValue) == napi_ok) {
        std::string efiFirmware;
        if (NapiGetStringUtf8(env, efiFirmwareValue, efiFirmware)) {
            vmConfig.efiFirmware = efiFirmware;
            HilogPrint("QEMU: ParseVMConfig got efiFirmware: " + efiFirmware);
        }
    }
    
    // 获取共享目录路径（可选）
    napi_value sharedDirValue;
    if (napi_get_named_property(env, config, "sharedDir", &sharedDirValue) == napi_ok) {
        std::string sharedDir;
        if (NapiGetStringUtf8(env, sharedDirValue, sharedDir)) {
            vmConfig.sharedDir = sharedDir;
        }
    }
    
    // 获取 QEMU 数据目录路径（由 KeymapsManager 提供，包含 keymaps）
    napi_value qemuDataDirValue;
    if (napi_get_named_property(env, config, "qemuDataDir", &qemuDataDirValue) == napi_ok) {
        std::string qemuDataDir;
        if (NapiGetStringUtf8(env, qemuDataDirValue, qemuDataDir)) {
            vmConfig.qemuDataDir = qemuDataDir;
            HilogPrint("QEMU: ParseVMConfig got qemuDataDir: " + qemuDataDir);
        }
    }
    // ArkTS 是否确认 keymaps 可用
    napi_value keymapsAvailValue;
    if (napi_get_named_property(env, config, "keymapsAvailable", &keymapsAvailValue) == napi_ok) {
        bool km = false;
        if (napi_get_value_bool(env, keymapsAvailValue, &km) == napi_ok) {
            vmConfig.keymapsAvailable = km;
            HilogPrint(std::string("QEMU: ParseVMConfig keymapsAvailable = ") + (km ? "true" : "false"));
        }
    }

    // 获取高级硬件配置：机器 / 显卡 / 网卡 / 声卡
    napi_value machineValue;
    if (napi_get_named_property(env, config, "machine", &machineValue) == napi_ok) {
        std::string machine;
        if (NapiGetStringUtf8(env, machineValue, machine)) {
            vmConfig.machine = machine;
            HilogPrint("QEMU: ParseVMConfig got machine: " + machine);
        }
    }

    napi_value displayDeviceValue;
    if (napi_get_named_property(env, config, "displayDevice", &displayDeviceValue) == napi_ok) {
        std::string displayDev;
        if (NapiGetStringUtf8(env, displayDeviceValue, displayDev)) {
            vmConfig.displayDevice = displayDev;
            HilogPrint("QEMU: ParseVMConfig got displayDevice: " + displayDev);
        }
    }

    napi_value networkDeviceValue;
    if (napi_get_named_property(env, config, "networkDevice", &networkDeviceValue) == napi_ok) {
        std::string netDev;
        if (NapiGetStringUtf8(env, networkDeviceValue, netDev)) {
            vmConfig.networkDevice = netDev;
            HilogPrint("QEMU: ParseVMConfig got networkDevice: " + netDev);
        }
    }

    napi_value audioDeviceValue;
    if (napi_get_named_property(env, config, "audioDevice", &audioDeviceValue) == napi_ok) {
        std::string audioDev;
        if (NapiGetStringUtf8(env, audioDeviceValue, audioDev)) {
            vmConfig.audioDevice = audioDev;
            HilogPrint("QEMU: ParseVMConfig got audioDevice: " + audioDev);
        }
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

// 创建/更新 VM 高级硬件偏好文件（vmPerfence.json）
static bool CreateVmPerfenceFile(const VMConfig& config)
{
    try {
        std::string vmDir = config.vmDir;
        std::string perfPath = vmDir + "/vmPerfence.json";

        if (!CreateDirectories(vmDir)) {
            return false;
        }

        std::ofstream perf(perfPath);
        if (!perf) return false;

        // 简单 JSON，记录高级硬件配置，供后续 UI / 调试使用
        perf << "{\n";
        perf << "  \"machine\": \"" << config.machine << "\",\n";
        perf << "  \"displayDevice\": \"" << config.displayDevice << "\",\n";
        perf << "  \"networkDevice\": \"" << config.networkDevice << "\",\n";
        perf << "  \"audioDevice\": \"" << config.audioDevice << "\"\n";
        perf << "}\n";

        perf.close();
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
// QCOW2 文件头结构 (简化版)
#pragma pack(push, 1)
struct Qcow2Header {
    uint32_t magic;                // 0x514649fb
    uint32_t version;              // 3
    uint64_t backing_file_offset;  // 0
    uint32_t backing_file_size;    // 0
    uint32_t cluster_bits;         // 16 (64KB)
    uint64_t size;                 // disk size in bytes
    uint32_t crypt_method;         // 0
    uint32_t l1_size;              // L1 table entries
    uint64_t l1_table_offset;      // offset to L1 table
    uint64_t refcount_table_offset;// offset to refcount table
    uint32_t refcount_table_clusters; // 1
    uint32_t nb_snapshots;         // 0
    uint64_t snapshots_offset;     // 0
    // Version 3 additions
    uint64_t incompatible_features; // 0
    uint64_t compatible_features;   // 0
    uint64_t autoclear_features;    // 0
    uint32_t refcount_order;        // 4 (16-bit refcounts)
    uint32_t header_length;         // 104
};
#pragma pack(pop)

// 字节序转换（大端）
static uint32_t be32(uint32_t val) {
    return ((val & 0xff) << 24) | ((val & 0xff00) << 8) | ((val & 0xff0000) >> 8) | ((val & 0xff000000) >> 24);
}

static uint64_t be64(uint64_t val) {
    return ((uint64_t)be32(val & 0xffffffff) << 32) | be32(val >> 32);
}

// 创建 QCOW2 格式磁盘（不依赖外部命令）
static bool CreateQcow2Disk(const std::string& diskPath, uint64_t sizeBytes) {
    std::ofstream disk(diskPath, std::ios::binary);
    if (!disk) return false;
    
    const uint32_t cluster_bits = 16;  // 64KB clusters
    const uint64_t cluster_size = 1ULL << cluster_bits;
    
    // 计算 L1 表大小
    uint64_t l2_entries = cluster_size / 8;  // 每个 L2 表条目 8 字节
    uint64_t l1_entries = (sizeBytes + (l2_entries * cluster_size) - 1) / (l2_entries * cluster_size);
    if (l1_entries < 1) l1_entries = 1;
    
    // 偏移量
    uint64_t header_cluster = 0;
    uint64_t l1_table_offset = cluster_size;  // 第二个簇
    uint64_t refcount_table_offset = cluster_size * 2;  // 第三个簇
    
    // 创建文件头
    Qcow2Header header = {0};
    header.magic = be32(0x514649fb);  // "QFI\xfb"
    header.version = be32(3);
    header.backing_file_offset = 0;
    header.backing_file_size = 0;
    header.cluster_bits = be32(cluster_bits);
    header.size = be64(sizeBytes);
    header.crypt_method = 0;
    header.l1_size = be32(static_cast<uint32_t>(l1_entries));
    header.l1_table_offset = be64(l1_table_offset);
    header.refcount_table_offset = be64(refcount_table_offset);
    header.refcount_table_clusters = be32(1);
    header.nb_snapshots = 0;
    header.snapshots_offset = 0;
    header.incompatible_features = 0;
    header.compatible_features = 0;
    header.autoclear_features = 0;
    header.refcount_order = be32(4);  // 16-bit refcounts
    header.header_length = be32(104);
    
    // 写入文件头
    disk.write(reinterpret_cast<char*>(&header), sizeof(header));
    
    // 填充到第一个簇
    std::vector<char> zeros(cluster_size - sizeof(header), 0);
    disk.write(zeros.data(), zeros.size());
    
    // L1 表（全零）
    std::vector<char> l1_zeros(cluster_size, 0);
    disk.write(l1_zeros.data(), l1_zeros.size());
    
    // Refcount 表（全零）
    std::vector<char> refcount_zeros(cluster_size, 0);
    disk.write(refcount_zeros.data(), refcount_zeros.size());
    
    disk.close();
    return disk.good();
}

static bool CreateVirtualDisk(const std::string& diskPath, int sizeGB) {
    try {
        std::string dirPath = diskPath.substr(0, diskPath.find_last_of('/'));
        if (!CreateDirectories(dirPath)) {
            return false;
        }
        
        // 使用内置 QCOW2 创建函数（不依赖外部 qemu-img 命令）
        uint64_t sizeBytes = static_cast<uint64_t>(sizeGB) * 1024ULL * 1024ULL * 1024ULL;
        if (CreateQcow2Disk(diskPath, sizeBytes)) {
            HilogPrint("QEMU: Created QCOW2 disk: " + diskPath + " (" + std::to_string(sizeGB) + "GB)");
            return true;
        }
        
        // 如果 QCOW2 创建失败，创建稀疏 raw 文件作为备选
        HilogPrint("QEMU: QCOW2 creation failed, falling back to sparse raw file");
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
    
    // ============================================================
    // 设置 QEMU 数据目录 (-L 参数)
    // 这是修复 VNC 崩溃的关键：VNC 初始化需要 keymaps/en-us 文件
    // KeymapsManager.ets 会将 rawfile/keymaps 复制到沙盒目录
    // ============================================================
    
    // 优先使用从 ArkTS 传入的 qemuDataDir（由 KeymapsManager 提供）
    // 重要：HarmonyOS 沙盒文件系统在 C++ 层的 stat() 可能无法正确访问
    // 因此我们信任 ArkTS 层（KeymapsManager）的验证结果
    std::string qemuDataDir = config.qemuDataDir;
    
    HilogPrint("QEMU: [VNC_DEBUG] config.qemuDataDir = " + (qemuDataDir.empty() ? "(empty)" : qemuDataDir));
    
    // 如果 ArkTS 提供了 qemuDataDir，信任它（ArkTS 层已经验证过 keymaps 存在）
    // 注意：C++ 的 stat() 在 HarmonyOS 沙盒中可能返回错误的结果
    if (!qemuDataDir.empty()) {
        std::string keymapTest = qemuDataDir + "/keymaps/en-us";
        // 仅记录日志，不清空 qemuDataDir（信任 ArkTS 层的验证）
        if (FileExists(keymapTest)) {
            HilogPrint(std::string("QEMU: [VNC_DEBUG] C++ stat() confirms keymaps at: ") + qemuDataDir);
        } else {
            // C++ 的 stat() 可能在沙盒中失败，但 ArkTS 层已确认文件存在
            // 继续使用 ArkTS 提供的路径
            HilogPrint(std::string("QEMU: [VNC_DEBUG] C++ stat() failed for: ") + keymapTest);
            HilogPrint("QEMU: [VNC_DEBUG] Trusting ArkTS - keymaps should exist at: " + qemuDataDir);
            // 不再清空 qemuDataDir！
        }
    }
    
    // 仅当 ArkTS 没有提供 qemuDataDir 时，才尝试搜索默认位置
    if (qemuDataDir.empty()) {
        HilogPrint("QEMU: [VNC_DEBUG] ArkTS did not provide qemuDataDir, searching default locations...");
        
        std::vector<std::string> dataSearchPaths = {
            // 首选：KeymapsManager 复制的目标位置
            "/data/storage/el2/base/haps/entry/files/qemu_data",
            // 备选：不同的 filesDir 格式
            "/data/app/el2/100/base/com.cloudshin.aetherengine/haps/entry/files/qemu_data",
            // rawfile 直接访问（可能在某些设备上可用）
            "/data/storage/el1/bundle/entry/resources/rawfile",
            "/data/storage/el2/base/haps/entry/resources/rawfile",
        };
        
        for (const auto& path : dataSearchPaths) {
            std::string keymapTest = path + "/keymaps/en-us";
            HilogPrint(std::string("QEMU: [VNC_DEBUG] Checking: ") + keymapTest);
            if (FileExists(keymapTest)) {
                qemuDataDir = path;
                HilogPrint(std::string("QEMU: [VNC_DEBUG] FOUND keymaps at: ") + path);
                break;
            } else {
                HilogPrint(std::string("QEMU: [VNC_DEBUG] NOT FOUND: ") + keymapTest);
            }
        }
    }
    
    if (!qemuDataDir.empty()) {
        args.push_back("-L");
        args.push_back(qemuDataDir);
        HilogPrint(std::string("QEMU: Using data directory for VNC: ") + qemuDataDir);
    } else {
        HilogPrint("QEMU: WARNING - keymaps directory not found!");
        HilogPrint("QEMU: VNC will be DISABLED, falling back to headless mode");
        // 仍然设置一个默认路径（QEMU需要-L参数）
        args.push_back("-L");
        args.push_back("/data/storage/el2/base/haps/entry/files/qemu_data");
    }
    
    // 根据架构设置机器类型和CPU
    // 注意：当前 libqemu_full.so 仅编译了 aarch64 目标
    // x86_64/i386 需要重新编译 QEMU 才能支持
    if (config.archType == "x86_64" || config.archType == "i386") {
        // x86 架构目前不支持，打印警告并回退到 aarch64 virt
        HilogPrint("QEMU: WARNING - x86/x86_64 architecture is not supported in current build");
        HilogPrint("QEMU: WARNING - Falling back to aarch64 virt machine");
        args.push_back("-machine");
        args.push_back("virt,gic-version=3");
        args.push_back("-cpu");
        args.push_back("cortex-a72");
    } else {
        // aarch64 配置，支持从创建向导传入的 machine
        std::string machine = config.machine.empty() ? "virt" : config.machine;
        HilogPrint(std::string("QEMU: [HW] Machine = ") + machine);

        args.push_back("-machine");
        if (machine == "virt") {
            // 注意：virtualization=on 在 TCG 模式下可能导致问题
            // 仅在 KVM 模式下启用嵌套虚拟化
            if (config.accel == "kvm") {
                args.push_back("virt,gic-version=3,virtualization=on");
            } else {
                args.push_back("virt,gic-version=3");
            }
        } else {
            // 其他机器类型（如 raspi3b/raspi4b）直接传递，保持最小假设
            args.push_back(machine);
        }
        
        args.push_back("-cpu");
        // 使用 cortex-a72 而不是 max，max 在某些环境下可能有问题
        args.push_back("cortex-a72");
    }
    
    args.push_back("-smp");
    args.push_back(std::to_string(config.cpuCount));
    
    args.push_back("-m");
    args.push_back(std::to_string(config.memoryMB));
    
    // 加速器配置
    args.push_back("-accel");
    args.push_back(config.accel);
    
    // UEFI/BIOS 固件配置
    std::string firmwarePath = config.efiFirmware;
    
    // 如果未指定固件路径，尝试自动查找
    if (firmwarePath.empty()) {
        std::string firmwareFileName;
    if (config.archType == "x86_64" || config.archType == "i386") {
            firmwareFileName = "OVMF_CODE.fd"; // x86 UEFI 固件
    } else {
            firmwareFileName = "edk2-aarch64-code.fd"; // ARM64 UEFI 固件
    }
    
        std::vector<std::string> searchPaths = {
            // rawfile/ 目录（通过 FirmwareManager 复制到 files）
            "/data/storage/el1/bundle/entry/resources/rawfile/" + firmwareFileName,
            "/data/storage/el2/base/haps/entry/resources/rawfile/" + firmwareFileName,
            // files/ 目录（FirmwareManager 复制的目标位置）
            "/data/storage/el2/base/haps/entry/files/" + firmwareFileName,
            "/data/storage/el2/base/haps/entry/files/firmware/" + firmwareFileName,
            firmwareFileName  // 作为fallback
        };
    
        for (const auto& path : searchPaths) {
        if (FileExists(path)) {
                firmwarePath = path;
                HilogPrint(std::string("QEMU: Found firmware at: ") + path);
            break;
        }
    }
    }
    
    // 配置固件
    // 注意：HarmonyOS 沙盒文件系统在 C++ 层的 FileExists() 可能返回错误结果
    // 如果 ArkTS 层（FirmwareManager）已确认固件存在，我们应该信任它，但仍需验证可读性
    auto try_firmware_path = [&](std::string path) -> bool {
        if (path.empty()) return false;
        // 先尝试 stat
        if (!FileExists(path)) {
            HilogPrint("QEMU: [FIRMWARE] C++ stat() failed for: " + path);
        }
        // 再尝试 open/read
        int fwFd = open(path.c_str(), O_RDONLY);
        if (fwFd < 0) {
            HilogPrint("QEMU: [FIRMWARE] open() failed: " + path + " errno=" + std::to_string(errno));
            return false;
        }
        char buffer[1];
        ssize_t r = read(fwFd, buffer, 0);
        close(fwFd);
        if (r < 0) {
            HilogPrint("QEMU: [FIRMWARE] open ok but read failed: " + path + " errno=" + std::to_string(errno));
            return false;
        }
        HilogPrint("QEMU: [FIRMWARE] Verified readable: " + path);
        firmwarePath = path;
        return true;
    };

    bool firmwareExists = false;

    // 先尝试 ArkTS 传入的路径
    if (!firmwarePath.empty()) {
        firmwareExists = try_firmware_path(firmwarePath);
    }

    // 如果 ArkTS 路径不可读，尝试自动搜索内置/默认路径
    if (!firmwareExists) {
        std::string firmwareFileName;
        if (config.archType == "x86_64" || config.archType == "i386") {
            firmwareFileName = "OVMF_CODE.fd";
        } else {
            firmwareFileName = "edk2-aarch64-code.fd";
        }
        std::vector<std::string> searchPaths = {
            "/data/storage/el1/bundle/entry/resources/rawfile/" + firmwareFileName,
            "/data/storage/el2/base/haps/entry/resources/rawfile/" + firmwareFileName,
            "/data/storage/el2/base/haps/entry/files/" + firmwareFileName,
            "/data/storage/el2/base/haps/entry/files/firmware/" + firmwareFileName,
            firmwareFileName  // fallback
        };
        for (const auto& p : searchPaths) {
            if (try_firmware_path(p)) {
                firmwareExists = true;
                break;
            }
        }
    }

    if (firmwareExists) {
        if (config.archType == "aarch64") {
            // ARM64 使用 pflash 方式加载 UEFI
            args.push_back("-drive");
            args.push_back("file=" + firmwarePath + ",if=pflash,format=raw,unit=0,readonly=on");
            HilogPrint(std::string("QEMU: Using UEFI firmware (pflash): ") + firmwarePath);
        } else {
            // x86 使用 -bios 参数
            args.push_back("-bios");
            args.push_back(firmwarePath);
            HilogPrint(std::string("QEMU: Using BIOS firmware: ") + firmwarePath);
        }
    } else {
        HilogPrint(std::string("QEMU: WARNING - Firmware path is empty or inaccessible for ") + config.archType + ", VM may not boot properly");
    }
    
    // 磁盘配置
    // 注意：OHOS 版 QEMU 禁用了 linux-aio，简化磁盘参数避免崩溃
    if (FileExists(config.diskPath)) {
        // 使用最简单的 if=virtio 方式，让 QEMU 自动选择设备
        // 这比手动指定 -device virtio-blk-pci 更稳定
        args.push_back("-drive");
        args.push_back("file=" + config.diskPath + ",if=virtio,format=qcow2,cache=writeback");
        HilogPrint("QEMU: Disk configured with if=virtio: " + config.diskPath);
    } else {
        HilogPrint("QEMU: WARNING - Disk file not found: " + config.diskPath);
    }
    
    // ISO光驱配置
    // 注意：HarmonyOS 沙箱机制下，/storage/Users/currentUser/Download/ 等公共目录
    // 在 NAPI 层可能可以访问，但 QEMU 进程无法直接访问
    // 如果 ISO 在公共目录，需要先复制到沙箱目录
    if (!config.isoPath.empty()) {
        std::string isoPath = config.isoPath;
        bool isoAccessible = false;
        
        // 检查是否是 URI 格式（如 file://docs/storage/...），需要转换
        if (isoPath.find("file://") == 0) {
            HilogPrint("QEMU: [WARN] ISO path is URI format, may not work: " + isoPath);
        }
        
        // 检查是否是公共目录路径（沙箱外）
        bool isPublicPath = (isoPath.find("/storage/Users/") != std::string::npos ||
                            isoPath.find("/storage/media/") != std::string::npos ||
                            isoPath.find("/data/storage/el1/bundle/") == std::string::npos);
        
        if (isPublicPath) {
            HilogPrint("QEMU: [WARN] ISO is in public directory (sandbox issue possible): " + isoPath);
        }
        
        // 多重检查：stat + open + read 测试
        if (FileExists(isoPath)) {
            int isoFd = open(isoPath.c_str(), O_RDONLY);
            if (isoFd >= 0) {
                // 尝试读取几个字节，确认真的可以访问
                char testBuf[16];
                ssize_t readBytes = read(isoFd, testBuf, sizeof(testBuf));
                close(isoFd);
                
                if (readBytes > 0) {
                    isoAccessible = true;
                    HilogPrint("QEMU: [ISO] Verified readable: " + isoPath);
                } else {
                    HilogPrint("QEMU: [WARN] ISO open succeeded but read failed: " + isoPath + 
                               " readBytes=" + std::to_string(readBytes) + " errno=" + std::to_string(errno));
                }
            } else {
                HilogPrint("QEMU: [WARN] ISO open failed: " + isoPath + " errno=" + std::to_string(errno));
            }
        } else {
            HilogPrint("QEMU: [WARN] ISO stat failed (FileExists=false): " + isoPath);
        }
        
        if (isoAccessible) {
            args.push_back("-cdrom");
            args.push_back(isoPath);
            HilogPrint("QEMU: [ISO] CDROM configured: " + isoPath);
        } else {
            // ISO 不可访问，跳过 CDROM 配置
            // 这样 QEMU 不会因为打开 ISO 失败而 abort
            HilogPrint("QEMU: [WARN] ISO not accessible, SKIPPING CDROM to prevent crash");
            HilogPrint("QEMU: [WARN] 提示：请将 ISO 文件复制到应用沙箱目录，或使用应用内文件选择器");
            WriteLog(config.logPath, "[WARNING] ISO file not accessible from QEMU process: " + isoPath);
            WriteLog(config.logPath, "[WARNING] CDROM skipped. Copy ISO to app sandbox or use internal file picker.");
        }
    } else {
        HilogPrint("QEMU: [ISO] No ISO path configured, skipping CDROM");
    }

    // 启用 QEMU 自身的调试日志，方便定位崩溃原因
    // 将 QEMU 的日志输出到 vmDir/qemu.log（与我们自己的日志路径一致）
    if (!config.logPath.empty()) {
        args.push_back("-D");
        args.push_back(config.logPath);
        // 只打开 guest_errors，避免日志过大
        args.push_back("-d");
        args.push_back("guest_errors");
        HilogPrint(std::string("QEMU: [DEBUG] Logging enabled: ") + config.logPath);
        WriteLog(config.logPath, "[DEBUG] QEMU debug log enabled with -d guest_errors");
    }
    
    // ============================================================
    // 网络配置
    // - 增强启动(RDP): 需要完整端口转发（RDP 3389, SSH 22, etc）
    // - 普通启动(VNC): 基础网络即可
    // - 调试模式 / 用户选择无网卡: 关闭网络
    // ============================================================
    
    // 判断是否需要增强网络（通过display参数推断启动模式）
    bool needEnhancedNetwork = !config.nographic && 
                               config.display.find("websocket") == std::string::npos;

    // 从高级配置中读取网卡类型
    std::string netDev = config.networkDevice;
    if (netDev.empty()) {
        // 默认使用 e1000 网卡 - 更稳定，兼容性更好
        // virtio-net-pci 在某些配置下可能有初始化问题
        netDev = "e1000";
        HilogPrint("QEMU: [NET] Using default e1000 network device");
    }
    bool netDisabled = (netDev == "none");

    // 构建网卡设备参数：直接使用用户选择的设备，不做强制回退
    // 如果设备不兼容，QEMU 会报错，用户可以据此选择其他设备
    auto buildNetDeviceArg = [&](const std::string& dev) -> std::string {
        if (dev == "virtio-net" || dev == "virtio-net-pci") {
            HilogPrint("QEMU: [NET] Using virtio-net-pci network device");
            return "virtio-net-pci,netdev=n0";
        } else if (dev == "e1000") {
            HilogPrint("QEMU: [NET] Using e1000 network device (user selected)");
            return "e1000,netdev=n0";
        } else if (dev == "e1000e") {
            HilogPrint("QEMU: [NET] Using e1000e network device (user selected)");
            return "e1000e,netdev=n0";
        } else if (dev == "rtl8139") {
            HilogPrint("QEMU: [NET] Using rtl8139 network device (user selected)");
            return "rtl8139,netdev=n0";
        } else if (dev == "ne2k_pci") {
            HilogPrint("QEMU: [NET] Using ne2k_pci network device (user selected)");
            return "ne2k_pci,netdev=n0";
        } else if (dev == "vmxnet3") {
            HilogPrint("QEMU: [NET] Using vmxnet3 network device (user selected)");
            return "vmxnet3,netdev=n0";
        } else if (dev == "usb-net") {
            HilogPrint("QEMU: [NET] Using usb-net network device (user selected)");
            return "usb-net,netdev=n0";
        }
        // 未知设备：直接使用用户输入的值
        HilogPrint(std::string("QEMU: [NET] Using custom network device: ") + dev);
        return dev + ",netdev=n0";
    };
    
    if (config.nographic || netDisabled) {
        // 调试模式或用户显式关闭网络：禁用网络
        HilogPrint("QEMU: [NET] Network disabled (nographic or user disabled)");
        args.push_back("-net");
        args.push_back("none");
    } else if (needEnhancedNetwork) {
        // 增强启动：完整端口转发（支持RDP/SSH/HTTP等）
        HilogPrint(std::string("QEMU: [NET] Enhanced mode - full port forwarding enabled, netDev=") + netDev);
        std::string netdev = "user,id=n0";
        netdev += ",hostfwd=tcp:127.0.0.1:3390-:3389";  // RDP
        netdev += ",hostfwd=tcp:127.0.0.1:2222-:22";    // SSH
        netdev += ",hostfwd=tcp:127.0.0.1:8080-:80";    // HTTP
        netdev += ",hostfwd=tcp:127.0.0.1:8443-:443";   // HTTPS
    
        args.push_back("-netdev");
        args.push_back(netdev);
    
        // 添加网卡设备（根据高级设置选择具体型号）
        args.push_back("-device");
        args.push_back(buildNetDeviceArg(netDev));
    } else {
        // 普通启动(VNC)：基础用户网络
        HilogPrint(std::string("QEMU: [NET] Standard mode - basic user network, netDev=") + netDev);
        args.push_back("-netdev");
        args.push_back("user,id=n0");
        
        // 添加网卡设备
        args.push_back("-device");
        args.push_back(buildNetDeviceArg(netDev));
    }
    
    // ============================================================
    // 显示 / 控制台配置
    // - 当 config.nographic=true 时：完全无头 + 串口通过 stdio（TTL 调试用）
    // - 当 config.nographic=false 时：使用 VNC 显示（需要 keymaps 文件支持）
    // ============================================================
    // 
    // VNC 崩溃修复说明：
    // VNC 初始化时需要加载 keymaps/en-us 键盘映射文件，否则会 abort。
    // 解决方案：通过 -L 参数指定包含 keymaps 的数据目录。
    // 如果 keymaps 不存在，则回退到 -display none + virtio-gpu + screendump
    // ============================================================
    
    if (config.nographic) {
        HilogPrint("QEMU: [DEBUG] Headless mode enabled (nographic + serial TCP)");
        args.push_back("-nographic");
        // 串口使用TCP socket，可以通过 telnet localhost 4321 连接
        args.push_back("-serial");
        args.push_back("tcp:127.0.0.1:4321,server,nowait");
        HilogPrint("QEMU: [DEBUG] Serial console on tcp:127.0.0.1:4321");
    } else {
        // 检查 keymaps 是否可用，决定是否启用 VNC
        bool vncAvailable = false;
        std::string displayConfig = config.display;
        if (displayConfig.empty()) {
            displayConfig = "vnc=127.0.0.1:1";  // 默认 VNC 监听在 5901 端口
        }

        // keymaps 存在才认为 VNC 可用
        // ArkTS 会传入 keymapsAvailable 标记；否则再尝试本地路径检查
        if (config.keymapsAvailable) {
            vncAvailable = true;
            std::string keymapPath = qemuDataDir + "/keymaps/en-us";
            HilogPrint("QEMU: [VNC_DEBUG] ArkTS confirmed keymaps at: " + keymapPath);
        } else if (!qemuDataDir.empty()) {
            std::string keymapPath = qemuDataDir + "/keymaps/en-us";
            if (FileExists(keymapPath)) {
                vncAvailable = true;
                HilogPrint("QEMU: [VNC_DEBUG] C++ stat() found keymaps: " + keymapPath);
            } else {
                HilogPrint("QEMU: [VNC_DEBUG] keymaps missing at: " + keymapPath + ", VNC disabled");
            }
        } else {
            HilogPrint("QEMU: [VNC_DEBUG] qemuDataDir empty (ArkTS did not provide), VNC disabled");
        }
        
        if (vncAvailable) {
            // VNC 可用：使用 VNC 显示
            HilogPrint("QEMU: [DEBUG] VNC enabled (keymaps available)");
            
            // 解析显示配置
            
            // 检查是否是 VNC 配置
            if (displayConfig.find("vnc") != std::string::npos) {
                // 使用 -vnc 参数
                // 格式：-vnc <host>:<display>,websocket=<port>
                // noVNC 使用 WebSocket 协议，所以需要启用 websocket 支持
                std::string vncArg = displayConfig;
                if (vncArg.substr(0, 4) == "vnc=") {
                    vncArg = vncArg.substr(4);  // 移除 "vnc=" 前缀
                }
                
                // 检查是否已经有 websocket 参数，避免重复添加
                // config.display 可能已经包含 websocket=5701
                if (vncArg.find("websocket=") == std::string::npos) {
                    // 没有 websocket 参数，添加默认的
                    vncArg = vncArg + ",websocket=5700";
                    HilogPrint(std::string("QEMU: [DEBUG] VNC display: ") + vncArg + " (added WebSocket on port 5700)");
                } else {
                    HilogPrint(std::string("QEMU: [DEBUG] VNC display: ") + vncArg + " (websocket already configured)");
                }
                
                args.push_back("-vnc");
                args.push_back(vncArg);
            } else {
                // 其他显示类型
                args.push_back("-display");
                args.push_back(displayConfig);
            }
        
            HilogPrint("QEMU: [DEBUG] VNC mode enabled");
        } else {
            // VNC 不可用：回退到无显示模式
            HilogPrint("QEMU: [DEBUG] VNC disabled (keymaps not found), using headless mode");
            args.push_back("-display");
            args.push_back("none");
            // 不添加任何显示设备，避免崩溃
            displayConfig = "none";  // 标记为无显示模式
        }
       
        // 根据高级设置选择显卡设备（仅在启用图形时）
        // 直接使用用户选择的设备，不做强制回退
        // 如果设备不兼容，QEMU 会报错，用户可以据此选择其他设备
        if (displayConfig != "none" && !config.displayDevice.empty() && config.displayDevice != "none") {
            args.push_back("-device");
            std::string displayDev = config.displayDevice;
            
            if (displayDev == "virtio-gpu" || displayDev == "virtio-gpu-pci") {
                args.push_back("virtio-gpu-pci");
                HilogPrint("QEMU: [HW] Using virtio-gpu-pci as display device");
            } else if (displayDev == "virtio-gpu-gl" || displayDev == "virtio-gpu-gl-pci") {
                args.push_back("virtio-gpu-gl-pci");
                HilogPrint("QEMU: [HW] Using virtio-gpu-gl-pci as display device");
            } else if (displayDev == "ramfb") {
                args.push_back("ramfb");
                HilogPrint("QEMU: [HW] Using ramfb as display device");
            } else if (displayDev == "virtio-vga") {
                args.push_back("virtio-vga");
                HilogPrint("QEMU: [HW] Using virtio-vga as display device (user selected)");
            } else if (displayDev == "qxl-vga") {
                args.push_back("qxl-vga");
                HilogPrint("QEMU: [HW] Using qxl-vga as display device (user selected)");
            } else if (displayDev == "cirrus-vga") {
                args.push_back("cirrus-vga");
                HilogPrint("QEMU: [HW] Using cirrus-vga as display device (user selected)");
            } else if (displayDev == "VGA") {
                args.push_back("VGA");
                HilogPrint("QEMU: [HW] Using VGA as display device (user selected)");
            } else {
                // 未知设备：直接使用用户输入的值
                args.push_back(displayDev);
                HilogPrint(std::string("QEMU: [HW] Using custom display device: ") + displayDev);
            }
        } else {
            HilogPrint("QEMU: [HW] No extra display device configured");
        }

        // 串口绑定到 TCP socket，用户可以通过网络连接进行交互
        // 格式：telnet localhost 4321
        args.push_back("-serial");
        args.push_back("tcp:127.0.0.1:4321,server,nowait");
        HilogPrint("QEMU: [DEBUG] Serial console on tcp:127.0.0.1:4321");
    }

    // 声卡配置
    // 注意：sb16, es1370, gus, adlib, cs4231a 是 ISA 设备，只存在于 x86 架构
    // 在 ARM64 (qemu-system-aarch64) 上使用会导致崩溃
    if (!config.audioDevice.empty() && config.audioDevice != "none") {
        std::string audioDev = config.audioDevice;
        
        // ISA 设备黑名单（x86-only，在 ARM64 会崩溃）
        bool isIsaDevice = (audioDev == "sb16" || audioDev == "es1370" || 
                           audioDev == "gus" || audioDev == "adlib" || 
                           audioDev == "cs4231a");
        
        if (isIsaDevice && config.archType != "x86_64" && config.archType != "i386") {
            // ISA 设备在 ARM64 上不可用，跳过并记录警告
            HilogPrint("QEMU: [WARNING] Audio device '" + audioDev + "' is ISA/x86-only, SKIPPING on ARM64 to prevent crash!");
        } else if (audioDev == "hda" || audioDev == "intel-hda") {
            // intel-hda 是 HDA 控制器，需要搭配 hda-duplex codec 才能工作
            args.push_back("-device");
            args.push_back("intel-hda");
            args.push_back("-device");
            args.push_back("hda-duplex");
            HilogPrint("QEMU: [HW] Audio device = HDA (intel-hda + hda-duplex)");
        } else if (audioDev == "ich9-intel-hda" || audioDev == "ich9-hda") {
            args.push_back("-device");
            args.push_back("ich9-intel-hda");
            args.push_back("-device");
            args.push_back("hda-duplex");
            HilogPrint("QEMU: [HW] Audio device = ICH9 HDA (ich9-intel-hda + hda-duplex)");
        } else if (audioDev == "ac97") {
            args.push_back("-device");
            args.push_back("AC97");
            HilogPrint("QEMU: [HW] Audio device = AC97");
        } else if (audioDev == "sb16" || audioDev == "es1370") {
            // 如果是 x86 架构，允许使用 ISA 设备
            args.push_back("-device");
            args.push_back(audioDev);
            HilogPrint("QEMU: [HW] Audio device = " + audioDev + " (ISA device, x86 mode)");
        } else {
            // 其他设备：直接使用用户输入的值
            args.push_back("-device");
            args.push_back(audioDev);
            HilogPrint(std::string("QEMU: [HW] Audio device = ") + audioDev + " (custom)");
        }
    } else {
        HilogPrint("QEMU: [HW] Audio disabled (no audio device)");
    }
    
    // 共享目录配置 (virtio-9p)
    // 暂时禁用，因为 virtio-9p 在某些情况下可能导致设备初始化失败
    // TODO: 在稳定后重新启用
    // std::string sharedPath = config.sharedDir;
    // if (sharedPath.empty()) {
    //     sharedPath = "/data/storage/el2/base/com.cloudshin.aetherengine/files/虚拟机磁盘/" + config.name;
    // }
    // struct stat st;
    // if (stat(sharedPath.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
    //     args.push_back("-fsdev");
    //     args.push_back("local,id=shared0,path=" + sharedPath + ",security_model=mapped-xattr");
    //     args.push_back("-device");
    //     args.push_back("virtio-9p-pci,fsdev=shared0,mount_tag=hostshare");
    // }
    HilogPrint("QEMU: [DEBUG] Shared folder disabled for stability");

    // QMP 监控接口 (用于查询 VM 状态)
    std::string qmpSocketPath = "/data/storage/el2/base/haps/entry/files/vms/" + config.name + "/qmp.sock";
    args.push_back("-qmp");
    args.push_back("unix:" + qmpSocketPath + ",server,nowait");
    
    // 监控接口：采用 QMP + guest 串口，主 monitor 关闭
    args.push_back("-monitor");
    args.push_back("none");
    
    // 暂时禁用 QEMU 日志，避免潜在的文件系统问题
    // args.push_back("-d");
    // args.push_back("guest_errors,unimp");
    
    return args;
}

// 写入日志
// 封装：同时写文件与Hilogs，便于 grep QEMU
static void HilogPrint(const std::string& message)
{
    // 添加空指针保护 - 确保 message 内容有效
    if (message.empty()) {
        return;  // 空消息不打印
    }
    
    const char* msg = message.c_str();
    if (!msg) {
        return;  // 极端情况保护
    }
    
#if defined(__OHOS__)
    // 使用 OH_LOG_Print
    // 注意：不检查 &OH_LOG_Print != nullptr，因为这个检查总是 true
    OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "QEMU_CORE", "%{public}s", msg);
    return;
#endif
    // 回退：stderr 也会被系统日志采集
    std::fprintf(stderr, "[QEMU_CORE] %s\n", msg);
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

// 动态加载 QEMU 核心库并调用其 API
// QEMU 共享库导出的 API：
//   void qemu_init(int argc, char **argv) - 初始化 QEMU
//   int qemu_main_loop(void) - 运行主循环
//   void qemu_cleanup(void) - 清理资源
//   void qemu_system_shutdown_request(int reason) - 请求关闭
// 类型定义（与 qemu_wrapper.h 中的全局变量兼容）
using qemu_main_loop_fn = int(*)(void);
using qemu_cleanup_fn = void(*)(void);
using qemu_shutdown_fn = void(*)(int);

// g_qemu_core_init 已在 qemu_wrapper.h 中声明为 extern
// int (*g_qemu_core_init)(int argc, char** argv);
static void* g_qemu_core_handle = nullptr;
static qemu_main_loop_fn g_qemu_core_main_loop = nullptr;
static qemu_cleanup_fn g_qemu_core_cleanup = nullptr;
static qemu_shutdown_fn g_qemu_core_shutdown = nullptr;
static bool g_qemu_initialized = false;

// 读取 dlerror() 的安全封装，避免重复调用导致 nullptr
static std::string SafeDlError()
{
    const char* err = dlerror();
    return err ? std::string(err) : std::string("unknown error");
}

static std::string Dirname(const std::string& path)
{
    size_t pos = path.find_last_of('/');
    if (pos == std::string::npos) return std::string();
    return path.substr(0, pos);
}

// Threadsafe function 回调：在主线程中 resolve/reject Promise
static void VmStartCallbackOnMainThread(napi_env env, napi_value js_callback, void* context, void* data)
{
    (void)js_callback;
    (void)context;
    
    VmStartCallbackData* callbackData = static_cast<VmStartCallbackData*>(data);
    if (!callbackData) return;
    
    napi_value result;
    if (callbackData->error == VmStartError::SUCCESS) {
        // 成功：resolve 返回 exitCode
        napi_create_object(env, &result);
        napi_value exitCodeVal, vmNameVal;
        napi_create_int32(env, callbackData->exitCode, &exitCodeVal);
        napi_create_string_utf8(env, callbackData->vmName.c_str(), NAPI_AUTO_LENGTH, &vmNameVal);
        napi_set_named_property(env, result, "exitCode", exitCodeVal);
        napi_set_named_property(env, result, "vmName", vmNameVal);
        napi_resolve_deferred(env, callbackData->deferred, result);
    } else {
        // 失败：reject 返回错误信息
        napi_value errorObj;
        napi_create_object(env, &errorObj);
        
        napi_value codeVal, messageVal, vmNameVal;
        napi_create_int32(env, static_cast<int>(callbackData->error), &codeVal);
        napi_create_string_utf8(env, callbackData->errorMessage.c_str(), NAPI_AUTO_LENGTH, &messageVal);
        napi_create_string_utf8(env, callbackData->vmName.c_str(), NAPI_AUTO_LENGTH, &vmNameVal);
        
        napi_set_named_property(env, errorObj, "code", codeVal);
        napi_set_named_property(env, errorObj, "message", messageVal);
        napi_set_named_property(env, errorObj, "vmName", vmNameVal);
        
        napi_reject_deferred(env, callbackData->deferred, errorObj);
    }
    
    delete callbackData;
}

// 辅助函数：在 VM 线程中调用 threadsafe function
static void NotifyVmStartResult(const std::string& vmName, VmStartError error, int exitCode, const std::string& errorMessage)
{
    std::lock_guard<std::mutex> lock(g_vmMutex);
    auto it = g_vmStartCallbacks.find(vmName);
    if (it == g_vmStartCallbacks.end()) return;
    
    auto* data = new VmStartCallbackData();
    data->env = it->second.env;
    data->deferred = it->second.deferred;
    data->vmName = vmName;
    data->error = error;
    data->exitCode = exitCode;
    data->errorMessage = errorMessage;
    
    napi_call_threadsafe_function(it->second.tsfn, data, napi_tsfn_blocking);
    napi_release_threadsafe_function(it->second.tsfn, napi_tsfn_release);
    g_vmStartCallbacks.erase(it);
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
                WriteLog(logPath, std::string("[QEMU] dlopen self dir failed: ") + SafeDlError());
            }
        }
    }
}

// 当前加载的架构（用于避免重复加载相同架构）
static std::string g_loaded_arch;

// 根据架构获取 .so 文件名
static std::string GetQemuLibName(const std::string& archType) {
    // 支持的架构: aarch64, x86_64, i386
    if (archType == "x86_64" || archType == "x86-64") {
        return "libqemu_x86_64.so";
    } else if (archType == "i386" || archType == "x86" || archType == "i686") {
        return "libqemu_i386.so";
    } else {
        // 默认使用 ARM64
        return "libqemu_aarch64.so";
    }
}

// ============ 诊断：详细追踪 dlopen 过程 ============
// 支持多架构加载：根据 archType 加载对应的 libqemu_{arch}.so
static void EnsureQemuCoreLoaded(const std::string& logPath, const std::string& archType = "aarch64")
{
    std::string libName = GetQemuLibName(archType);
    
    // 如果已经加载了相同架构的库，直接返回
    if (g_qemu_core_init && g_loaded_arch == archType) {
        HilogPrint("QEMU: Library already loaded for arch: " + archType);
        return;
    }
    
    // 如果加载了不同架构的库，需要先卸载
    if (g_qemu_core_handle && g_loaded_arch != archType) {
        HilogPrint("QEMU: Unloading previous library for arch: " + g_loaded_arch);
        WriteLog(logPath, "[QEMU] Switching architecture from " + g_loaded_arch + " to " + archType);
        
        // 清理之前加载的函数指针
        g_qemu_core_init = nullptr;
        g_qemu_core_main_loop = nullptr;
        g_qemu_core_cleanup = nullptr;
        g_qemu_core_shutdown = nullptr;
        
        // 卸载之前的库
        dlclose(g_qemu_core_handle);
        g_qemu_core_handle = nullptr;
        g_loaded_arch.clear();
    }
    
    if (g_qemu_core_init) return;
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", "========== 开始加载 %s ==========", libName.c_str());
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", "目标架构: %s", archType.c_str());
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", "警告: 此操作将执行 ~748 个 constructor 函数");
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", "如果下一条日志没出现，说明 dlopen 导致崩溃");
    
    HilogPrint("QEMU: Starting core library loading process for " + archType);
    WriteLog(logPath, "[QEMU] Loading library: " + libName + " for arch: " + archType);
    
    // 直接按名称加载，前提是 core so 已随 HAP 打包
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", ">>> 即将调用 dlopen(\"%s\", RTLD_NOW) <<<", libName.c_str());
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", ">>> 如果没有后续日志，崩溃发生在 dlopen/constructor 中 <<<");
    
    HilogPrint("QEMU: Attempting dlopen " + libName);
    g_qemu_core_handle = dlopen(libName.c_str(), RTLD_NOW);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", ">>> dlopen 返回: %p <<<", g_qemu_core_handle);
    
    // 如果直接加载失败，尝试兼容性名称 libqemu_full.so
    if (!g_qemu_core_handle && archType == "aarch64") {
        HilogPrint("QEMU: Trying fallback libqemu_full.so");
        g_qemu_core_handle = dlopen("libqemu_full.so", RTLD_NOW);
    }
    
    if (!g_qemu_core_handle) {
        std::string err = SafeDlError();
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_LOAD", "dlopen 失败: %s", err.c_str());
        WriteLog(logPath, std::string("[QEMU] dlopen " + libName + " failed: ") + err);
        HilogPrint(std::string("QEMU: dlopen " + libName + " failed: ") + err);
        
        // ============ 优先从 files 目录加载（ArkTS 层已提取 rawfile 到此处）============
        std::string filesPath = "/data/storage/el2/base/haps/entry/files/" + libName;
        HilogPrint("QEMU: Attempting dlopen from files: " + filesPath);
        g_qemu_core_handle = dlopen(filesPath.c_str(), RTLD_NOW);
        if (g_qemu_core_handle) {
            WriteLog(logPath, std::string("[QEMU] dlopen from files SUCCESS: ") + filesPath);
            HilogPrint("QEMU: Successfully loaded from files dir!");
        } else {
            std::string filesErr = SafeDlError();
            WriteLog(logPath, std::string("[QEMU] dlopen files failed: ") + filesErr);
            HilogPrint(std::string("QEMU: dlopen files failed: ") + filesErr);
            
            // 尝试从当前模块同目录加载
            HilogPrint("QEMU: Attempting TryLoadCoreFromSelfDir");
            TryLoadCoreFromSelfDir(logPath);
            if (!g_qemu_core_handle) {
                // 尝试从应用libs目录加载（可能因命名空间被拒绝）
                std::string libsPath = "/data/app/el2/100/base/com.cloudshin.aetherengine/haps/entry/libs/arm64-v8a/" + libName;
                HilogPrint("QEMU: Attempting dlopen from libs: " + libsPath);
                g_qemu_core_handle = dlopen(libsPath.c_str(), RTLD_NOW);
                if (g_qemu_core_handle) {
                    WriteLog(logPath, std::string("[QEMU] dlopen from libs: ") + libsPath);
                    HilogPrint("QEMU: Successfully loaded from libs");
                } else {
                    std::string libsErr = SafeDlError();
                    WriteLog(logPath, std::string("[QEMU] dlopen libs failed: ") + libsErr);
                    HilogPrint(std::string("QEMU: dlopen libs failed: ") + libsErr);
                    
                    // 所有尝试都失败了
                    WriteLog(logPath, "[QEMU] Core library not loaded. Aborting start.");
                    WriteLog(logPath, "[QEMU] Please ensure " + libName + " is properly installed in the app bundle.");
                    return;
                }
            } else {
                HilogPrint("QEMU: Successfully loaded from self dir");
            }
        }
    } else {
        HilogPrint("QEMU: Successfully loaded " + libName + " directly");
    }
    
    // 记录已加载的架构
    g_loaded_arch = archType;

    // ============ 诊断：详细追踪 dlsym 过程 ============
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> 开始 dlsym 查找符号 <<<");
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> handle = %p <<<", g_qemu_core_handle);
    
    // 清除之前的错误
    dlerror();
    
    // 加载 QEMU API 符号 - 逐个加载并检查
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> 查找 qemu_init <<<");
    g_qemu_core_init = reinterpret_cast<int(*)(int, char**)>(dlsym(g_qemu_core_handle, "qemu_init"));
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> qemu_init = %p <<<", (void*)g_qemu_core_init);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> 查找 qemu_main_loop <<<");
    g_qemu_core_main_loop = reinterpret_cast<qemu_main_loop_fn>(dlsym(g_qemu_core_handle, "qemu_main_loop"));
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> qemu_main_loop = %p <<<", (void*)g_qemu_core_main_loop);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> 查找 qemu_cleanup <<<");
    g_qemu_core_cleanup = reinterpret_cast<qemu_cleanup_fn>(dlsym(g_qemu_core_handle, "qemu_cleanup"));
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> qemu_cleanup = %p <<<", (void*)g_qemu_core_cleanup);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> 查找 qemu_system_shutdown_request <<<");
    g_qemu_core_shutdown = reinterpret_cast<qemu_shutdown_fn>(dlsym(g_qemu_core_handle, "qemu_system_shutdown_request"));
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> qemu_system_shutdown_request = %p <<<", (void*)g_qemu_core_shutdown);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_SYM", ">>> dlsym 完成 <<<");

    // 添加详细的调试日志
    if (!g_qemu_core_init) {
        std::string err = SafeDlError();
        WriteLog(logPath, std::string("[QEMU] dlsym qemu_init failed: ") + err);
        HilogPrint(std::string("QEMU: dlsym qemu_init failed: ") + err);
    } else {
        WriteLog(logPath, "[QEMU] Successfully loaded qemu_init symbol");
        HilogPrint("QEMU: Successfully loaded qemu_init symbol");
    }

    if (!g_qemu_core_main_loop) {
        std::string err = SafeDlError();
        WriteLog(logPath, std::string("[QEMU] dlsym qemu_main_loop failed: ") + err);
        HilogPrint(std::string("QEMU: dlsym qemu_main_loop failed: ") + err);
    } else {
        WriteLog(logPath, "[QEMU] Successfully loaded qemu_main_loop symbol");
        HilogPrint("QEMU: Successfully loaded qemu_main_loop symbol");
    }

    if (!g_qemu_core_cleanup) {
        WriteLog(logPath, "[QEMU] dlsym qemu_cleanup failed (optional)");
    }

    if (!g_qemu_core_shutdown) {
        WriteLog(logPath, "[QEMU] dlsym qemu_system_shutdown_request failed (optional)");
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

    // 使用全局变量中保存的架构类型
    std::string archType = g_current_arch_type.empty() ? "aarch64" : g_current_arch_type;
    EnsureQemuCoreLoaded(logPath, archType);
    if (g_qemu_core_init && g_qemu_core_main_loop) {
        WriteLog(logPath, "[QEMU] Core library loaded, initializing QEMU...");
        HilogPrint("QEMU: Core library loaded successfully");
        
        // 打印所有启动参数便于调试
        HilogPrint("QEMU: Command line arguments (" + std::to_string(argc) + " args):");
        for (int i = 0; i < argc; i++) {
            HilogPrint("QEMU:   argv[" + std::to_string(i) + "] = " + std::string(argv[i]));
        }
        
        // 使用新的 QEMU API：先 init，再 main_loop
        HilogPrint("QEMU: Calling qemu_init now...");
        WriteLog(logPath, "[QEMU] Calling qemu_init...");
        
        // ============ 添加崩溃保护和详细诊断 ============
        // 在调用 qemu_init 前同步日志
        fflush(stdout);
        fflush(stderr);
        
        // 设置信号处理以捕获崩溃
        struct sigaction sa_old, sa_new;
        memset(&sa_new, 0, sizeof(sa_new));
        sa_new.sa_handler = [](int sig) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_CRASH", 
                ">>> QEMU 崩溃！信号: %d <<<", sig);
            // 不要在这里调用 exit()，让系统处理
        };
        sigaction(SIGSEGV, &sa_new, &sa_old);
        sigaction(SIGABRT, &sa_new, &sa_old);
        sigaction(SIGBUS, &sa_new, &sa_old);
        
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_INIT", 
            ">>> 即将调用 qemu_init，参数数量: %d <<<", argc);
        
        // ============ 设置 QEMU 环境变量 ============
        // 这些环境变量可能有助于 QEMU 正常初始化
        setenv("QEMU_AUDIO_DRV", "none", 1);  // 禁用音频
        setenv("DISPLAY", "", 1);  // 无显示环境
        
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_INIT", 
            ">>> 环境变量已设置 <<<");
        
        // ============ 使用用户的实际配置 ============
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_INIT", 
            ">>> 使用用户配置，%d 个参数 <<<", argc);
        
        // 打印每个参数用于调试
        for (int i = 0; i < argc; i++) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_ARG", 
                "[%d] = %s", i, argv[i]);
        }
        
        // 直接使用用户配置
        g_qemu_core_init(argc, argv);
        
        // 恢复信号处理
        sigaction(SIGSEGV, &sa_old, nullptr);
        sigaction(SIGABRT, &sa_old, nullptr);
        sigaction(SIGBUS, &sa_old, nullptr);
        
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_INIT", 
            ">>> qemu_init 返回成功！<<<");
        
        g_qemu_initialized = true;
        
        HilogPrint("QEMU: qemu_init completed, entering main loop...");
        WriteLog(logPath, "[QEMU] qemu_init completed, entering qemu_main_loop...");
        int result = g_qemu_core_main_loop();
        
        // 主循环结束，进行清理
        WriteLog(logPath, "[QEMU] qemu_main_loop returned: " + std::to_string(result));
        HilogPrint("QEMU: qemu_main_loop returned: " + std::to_string(result));
        
        if (g_qemu_core_cleanup) {
            HilogPrint("QEMU: Calling qemu_cleanup...");
            WriteLog(logPath, "[QEMU] Calling qemu_cleanup...");
            g_qemu_core_cleanup();
            WriteLog(logPath, "[QEMU] qemu_cleanup completed");
        }
        g_qemu_initialized = false;
        
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

// 辅助函数：创建并返回拒绝的 Promise
static napi_value CreateRejectedPromise(napi_env env, VmStartError error, const std::string& message, const std::string& vmName) {
    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);
    
    napi_value errorObj;
    napi_create_object(env, &errorObj);
    
    napi_value codeVal, messageVal, vmNameVal;
    napi_create_int32(env, static_cast<int>(error), &codeVal);
    napi_create_string_utf8(env, message.c_str(), NAPI_AUTO_LENGTH, &messageVal);
    napi_create_string_utf8(env, vmName.c_str(), NAPI_AUTO_LENGTH, &vmNameVal);
    
    napi_set_named_property(env, errorObj, "code", codeVal);
    napi_set_named_property(env, errorObj, "message", messageVal);
    napi_set_named_property(env, errorObj, "vmName", vmNameVal);
    
    napi_reject_deferred(env, deferred, errorObj);
    return promise;
}

static napi_value StartVm(napi_env env, napi_callback_info info) {
    // ============ 诊断：在任何操作之前打印日志 ============
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_START", ">>> StartVm 函数入口 <<<");
    
    HilogPrint("QEMU: StartVm function called!");
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_START", ">>> 获取参数成功, argc=%{public}zu <<<", argc);
    
    // 返回 Promise
    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);
    
    if (argc < 1) {
        return CreateRejectedPromise(env, VmStartError::CONFIG_FAILED, "No config provided", "");
    }
    
    bool ok = false;
    VMConfig config = ParseVMConfig(env, argv[0], ok);
    if (!ok) {
        return CreateRejectedPromise(env, VmStartError::CONFIG_FAILED, "Invalid config", "");
    }
    
    std::lock_guard<std::mutex> lock(g_vmMutex);
    
    // 检查VM是否已在运行
    if (g_vmRunning.find(config.name) != g_vmRunning.end() && g_vmRunning[config.name]->load()) {
        HilogPrint("QEMU: VM '" + config.name + "' is already running");
        return CreateRejectedPromise(env, VmStartError::ALREADY_RUNNING, "VM is already running", config.name);
    }
    
    HilogPrint("QEMU: Starting VM '" + config.name + "' with accel=" + config.accel + " display=" + config.display);
    
    // 创建VM目录结构
    if (!CreateVMDirectory(config.name)) {
        WriteLog(config.logPath, "Failed to create VM directory for: " + config.name);
        return CreateRejectedPromise(env, VmStartError::CONFIG_FAILED, "Failed to create VM directory", config.name);
    }
    WriteLog(config.logPath, "VM directory created for: " + config.name);
    
    // 创建VM配置文件
    if (!CreateVMConfigFile(config)) {
        WriteLog(config.logPath, "Failed to create VM config file for: " + config.name);
        return CreateRejectedPromise(env, VmStartError::CONFIG_FAILED, "Failed to create VM config file", config.name);
    }
    WriteLog(config.logPath, "VM config file created for: " + config.name);

    // 创建 VM 高级硬件偏好文件（vmPerfence.json），忽略失败
    if (!CreateVmPerfenceFile(config)) {
        WriteLog(config.logPath, "Warning: Failed to create vmPerfence.json for: " + config.name);
    } else {
        WriteLog(config.logPath, "VM perfence file created for: " + config.name);
    }
    
    // 更新VM状态为准备中
    UpdateVMStatus(config.name, "preparing");
    
    // 创建虚拟磁盘
    if (!FileExists(config.diskPath)) {
        WriteLog(config.logPath, "Creating virtual disk: " + config.diskPath);
        if (!CreateVirtualDisk(config.diskPath, config.diskSizeGB)) {
            WriteLog(config.logPath, "Failed to create virtual disk");
            UpdateVMStatus(config.name, "failed");
            return CreateRejectedPromise(env, VmStartError::DISK_CREATE_FAILED, "Failed to create virtual disk", config.name);
        }
        WriteLog(config.logPath, "Virtual disk created successfully");
    }
    
    // ========== 打印用户选择的设备配置 ==========
    WriteLog(config.logPath, "========== Device Configuration ==========");
    WriteLog(config.logPath, "[CONFIG] Machine: " + (config.machine.empty() ? "virt (default)" : config.machine));
    WriteLog(config.logPath, "[CONFIG] Display Device: " + (config.displayDevice.empty() ? "none (default)" : config.displayDevice));
    WriteLog(config.logPath, "[CONFIG] Network Device: " + (config.networkDevice.empty() ? "virtio-net (default)" : config.networkDevice));
    WriteLog(config.logPath, "[CONFIG] Audio Device: " + (config.audioDevice.empty() ? "none (default)" : config.audioDevice));
    WriteLog(config.logPath, "[CONFIG] Memory: " + std::to_string(config.memoryMB) + " MB");
    WriteLog(config.logPath, "[CONFIG] CPU Count: " + std::to_string(config.cpuCount));
    WriteLog(config.logPath, "[CONFIG] QEMU Data Dir: " + (config.qemuDataDir.empty() ? "(not set)" : config.qemuDataDir));
    WriteLog(config.logPath, "==========================================");
    
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
    g_current_arch_type = config.archType.empty() ? "aarch64" : config.archType;
    
    // 启动前确保核心库可用（根据架构加载对应的 .so）
    std::string archType = config.archType.empty() ? "aarch64" : config.archType;
    WriteLog(config.logPath, "[QEMU] Loading QEMU core for architecture: " + archType);
    EnsureQemuCoreLoaded(config.logPath, archType);
    if (!g_qemu_core_init || !g_qemu_core_main_loop) {
        WriteLog(config.logPath, "[QEMU] Core library not loaded. Aborting start.");
        std::string libName = GetQemuLibName(archType);
        WriteLog(config.logPath, "[QEMU] Please ensure " + libName + " is properly installed in the app bundle.");
        UpdateVMStatus(config.name, "failed");
        return CreateRejectedPromise(env, VmStartError::CORE_LIB_MISSING, 
            libName + " not found or failed to load. Please check app installation.", config.name);
    }

    // 创建 threadsafe function 用于回调
    napi_value resourceName;
    napi_create_string_utf8(env, "VmStartCallback", NAPI_AUTO_LENGTH, &resourceName);
    
    napi_threadsafe_function tsfn;
    napi_status status = napi_create_threadsafe_function(
        env, nullptr, nullptr, resourceName,
        0, 1, nullptr, nullptr, nullptr,
        VmStartCallbackOnMainThread, &tsfn);
    
    if (status != napi_ok) {
        WriteLog(config.logPath, "[QEMU] Failed to create threadsafe function");
        UpdateVMStatus(config.name, "failed");
        return CreateRejectedPromise(env, VmStartError::INIT_FAILED, "Failed to create callback", config.name);
    }
    
    // 存储 threadsafe function 和 deferred
    VmStartContext ctx;
    ctx.tsfn = tsfn;
    ctx.deferred = deferred;
    ctx.env = env;
    g_vmStartCallbacks[config.name] = ctx;

    // 启动VM线程
    if (g_vmRunning.find(config.name) == g_vmRunning.end()) {
        g_vmRunning[config.name] = new std::atomic<bool>(false);
    }
    g_vmRunning[config.name]->store(true);
    
    // 更新VM状态为运行中
    UpdateVMStatus(config.name, "running");
    
    // 保存 vmName 用于在回调中使用
    std::string vmName = config.name;
    
    g_vmThreads[config.name] = std::thread([config, args, vmName]() {
        std::vector<char*> cargs;
        for (const auto &s : args) {
            cargs.push_back(const_cast<char*>(s.c_str()));
        }

        // 在进入 QEMU 主循环前启动 stdout/stderr/stdin 捕获
        g_logCapture = std::make_unique<CaptureQemuOutput>();

        WriteLog(config.logPath, "VM thread started");
        // 这里也通过 Hilog 打一条，方便在设备上直接看到 VM 主线程已启动
        HilogPrint("QEMU: VM thread started for VM '" + vmName + "'");
        int exitCode = QemuCoreMainOrStub(static_cast<int>(cargs.size()), cargs.data());
        WriteLog(config.logPath, "VM exited with code: " + std::to_string(exitCode));

        // 退出后释放捕获器，恢复文件描述符并释放 JS 回调
        g_logCapture.reset();
        
        // 更新VM状态为已停止
        UpdateVMStatus(config.name, "stopped");
        g_vmRunning[config.name]->store(false);
        
        // 通知 ArkTS 层 VM 已退出
        VmStartError error = (exitCode == 0) ? VmStartError::SUCCESS : VmStartError::LOOP_CRASHED;
        std::string errorMsg = (exitCode == 0) ? "" : "VM exited with code " + std::to_string(exitCode);
        NotifyVmStartResult(vmName, error, exitCode, errorMsg);
    });
    
    // 返回 Promise（将在 VM 退出时 resolve/reject）
    return promise;
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

// 通过 QMP Unix socket 查询 VM 真实状态
static std::string QueryVmStatusViaQmp(const std::string& vmName) {
    std::string socketPath = "/data/storage/el2/base/haps/entry/files/vms/" + vmName + "/qmp.sock";
    
    // 创建 Unix socket
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        HilogPrint("QMP: Failed to create socket");
        return "unknown";
    }
    
    // 设置非阻塞超时
    struct timeval tv;
    tv.tv_sec = 2;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    
    // 连接到 QMP socket
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);
    
    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sock);
        HilogPrint("QMP: Failed to connect to " + socketPath);
        return "stopped";  // 无法连接说明 VM 未运行
    }
    
    // 读取 QMP greeting
    char buffer[4096];
    ssize_t n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (n <= 0) {
        close(sock);
        return "unknown";
    }
    buffer[n] = '\0';
    
    // 发送 qmp_capabilities 命令进入命令模式
    const char* capCmd = "{\"execute\": \"qmp_capabilities\"}\n";
    if (send(sock, capCmd, strlen(capCmd), 0) <= 0) {
        close(sock);
        return "unknown";
    }
    
    // 读取响应
    n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (n <= 0) {
        close(sock);
        return "unknown";
    }
    buffer[n] = '\0';
    
    // 发送 query-status 命令
    const char* statusCmd = "{\"execute\": \"query-status\"}\n";
    if (send(sock, statusCmd, strlen(statusCmd), 0) <= 0) {
        close(sock);
        return "unknown";
    }
    
    // 读取状态响应
    n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    close(sock);
    
    if (n <= 0) {
        return "unknown";
    }
    buffer[n] = '\0';
    
    std::string response(buffer);
    HilogPrint("QMP: Status response: " + response);
    
    // 简单解析 JSON 响应
    // 响应格式: {"return": {"running": true, "status": "running", ...}}
    if (response.find("\"running\": true") != std::string::npos || 
        response.find("\"running\":true") != std::string::npos) {
        return "running";
    } else if (response.find("\"status\": \"paused\"") != std::string::npos ||
               response.find("\"status\":\"paused\"") != std::string::npos) {
        return "paused";
    } else if (response.find("\"status\": \"shutdown\"") != std::string::npos ||
               response.find("\"status\":\"shutdown\"") != std::string::npos) {
        return "shutdown";
    } else if (response.find("\"status\": \"prelaunch\"") != std::string::npos) {
        return "starting";
    }
    
    return "stopped";
}

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
    
    std::string status = "stopped";
    
    // 加锁访问 g_vmRunning，避免数据竞争
    {
        std::lock_guard<std::mutex> lock(g_vmMutex);
        // 首先检查本地运行状态标志
        auto it = g_vmRunning.find(vmName);
        if (it != g_vmRunning.end() && it->second && it->second->load()) {
            // VM 线程在运行，尝试通过 QMP 获取真实状态
            status = QueryVmStatusViaQmp(vmName);
            
            // 如果 QMP 查询失败但线程还在运行，返回 running
            if (status == "stopped" || status == "unknown") {
                status = "running";
            }
        }
    }

    napi_value result;
    napi_create_string_utf8(env, status.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// ============================================================
// QMP screendump - 通过 QMP 获取屏幕截图
// 由于 VNC 后端崩溃，使用 -display none + virtio-gpu + screendump 作为替代方案
// ============================================================

static bool TakeScreenshotViaQmp(const std::string& vmName, const std::string& outputPath) {
    std::string socketPath = "/data/storage/el2/base/haps/entry/files/vms/" + vmName + "/qmp.sock";
    
    HilogPrint("QMP: Taking screenshot for VM: " + vmName);
    HilogPrint("QMP: Output path: " + outputPath);
    
    // 创建 Unix socket
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        HilogPrint("QMP screendump: Failed to create socket");
        return false;
    }
    
    // 设置超时
    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    
    // 连接到 QMP socket
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);
    
    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sock);
        HilogPrint("QMP screendump: Failed to connect to socket");
        return false;
    }
    
    char buffer[4096];
    ssize_t n;
    
    // 读取 QMP greeting
    n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (n <= 0) {
        close(sock);
        HilogPrint("QMP screendump: Failed to read greeting");
        return false;
    }
    buffer[n] = '\0';
    HilogPrint(std::string("QMP greeting: ") + buffer);
    
    // 发送 qmp_capabilities
    const char* capCmd = "{\"execute\": \"qmp_capabilities\"}\n";
    if (send(sock, capCmd, strlen(capCmd), 0) <= 0) {
        close(sock);
        HilogPrint("QMP screendump: Failed to send qmp_capabilities");
        return false;
    }
    
    n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (n <= 0) {
        close(sock);
        HilogPrint("QMP screendump: Failed to read capabilities response");
        return false;
    }
    buffer[n] = '\0';
    HilogPrint(std::string("QMP capabilities response: ") + buffer);
    
    // 发送 screendump 命令
    // 格式: {"execute": "screendump", "arguments": {"filename": "/path/to/file.ppm"}}
    std::string screendumpCmd = "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"" + outputPath + "\"}}\n";
    HilogPrint("QMP screendump command: " + screendumpCmd);
    
    if (send(sock, screendumpCmd.c_str(), screendumpCmd.length(), 0) <= 0) {
        close(sock);
        HilogPrint("QMP screendump: Failed to send screendump command");
        return false;
    }
    
    // 等待响应
    n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    close(sock);
    
    if (n <= 0) {
        HilogPrint("QMP screendump: No response");
        return false;
    }
    buffer[n] = '\0';
    HilogPrint(std::string("QMP screendump response: ") + buffer);
    
    // 检查响应是否成功
    std::string response(buffer);
    if (response.find("\"return\"") != std::string::npos && 
        response.find("\"error\"") == std::string::npos) {
        HilogPrint("QMP screendump: Success");
        return true;
    }
    
    HilogPrint("QMP screendump: Failed - " + response);
    return false;
}

static napi_value TakeScreenshot(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Missing parameters: vmName, outputPath");
        return nullptr;
    }
    
    std::string vmName, outputPath;
    if (!NapiGetStringUtf8(env, argv[0], vmName) || !NapiGetStringUtf8(env, argv[1], outputPath)) {
        napi_throw_error(env, nullptr, "Failed to get string parameters");
        return nullptr;
    }
    
    bool success = TakeScreenshotViaQmp(vmName, outputPath);
    
    napi_value result;
    napi_get_boolean(env, success, &result);
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
    int result = qemu_rdp_client_connect(client, &rdp_config);
    
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
            qemu_rdp_client_disconnect(g_rdp_clients[client_id]);
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
// ============ 诊断工具：追踪 dlopen 崩溃位置 ============
// 这个函数会详细记录 dlopen 过程中的每一步
static napi_value CheckCoreLib(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value result;
    napi_create_object(env, &result);

    auto set_bool = [&](const char* name, bool v){ napi_value b; napi_get_boolean(env, v, &b); napi_set_named_property(env, result, name, b); };
    auto set_str = [&](const char* name, const std::string& s){ napi_value v; napi_create_string_utf8(env, s.c_str(), NAPI_AUTO_LENGTH, &v); napi_set_named_property(env, result, name, v); };

    // ============ 添加详细的崩溃诊断日志 ============
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "========== CheckCoreLib 开始 ==========");
    
    // 已加载到全局？
    bool alreadyLoaded = g_qemu_core_init != nullptr && g_qemu_core_main_loop != nullptr;
    set_bool("loaded", alreadyLoaded);
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤0: 检查是否已加载 = %s", alreadyLoaded ? "是" : "否");

    // 获取库路径
    Dl_info dlinfo{};
    std::string selfDir;
    if (dladdr((void*)&CheckCoreLib, &dlinfo) != 0 && dlinfo.dli_fname) {
        std::string soPath = dlinfo.dli_fname;
        auto pos = soPath.find_last_of('/');
        if (pos != std::string::npos) {
            selfDir = soPath.substr(0, pos);
        }
    }
    set_str("selfDir", selfDir);
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤1: 库目录 = %s", selfDir.c_str());

    // ============ 关键测试：使用 RTLD_NOLOAD 检查是否已在内存中 ============
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤2: 尝试 RTLD_NOLOAD（不触发constructor）...");
    void* h_noload = dlopen("libqemu_full.so", RTLD_LAZY | RTLD_NOLOAD);
    if (h_noload) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤2: 库已在内存中！");
        set_bool("alreadyInMemory", true);
        dlclose(h_noload);
    } else {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤2: 库未在内存中，需要加载");
        set_bool("alreadyInMemory", false);
    }

    // ============ 暂时跳过实际的 dlopen 以避免崩溃 ============
    // 如果需要测试 dlopen，取消下面的注释
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤3: 跳过 dlopen 以避免崩溃");
    set_bool("foundLd", false);
    set_bool("foundSelfDir", false);
    set_bool("foundFiles", false);
    set_bool("symFound", false);
    set_str("errLd", "dlopen 被跳过以避免崩溃（748个constructor）");
    
    /*
    // ============ 危险区域：实际的 dlopen 调用 ============
    // 取消注释以测试
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤3: 准备调用 dlopen（危险！）...");
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", ">>> 如果下一条日志没出现，说明 dlopen/constructor 导致崩溃 <<<");
    
    void* h1 = dlopen("libqemu_full.so", RTLD_LAZY);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤4: dlopen 返回 = %p", h1);
    set_bool("foundLd", h1 != nullptr);
    
    if (!h1) {
        const char* err = dlerror();
        set_str("errLd", err ? std::string(err) : std::string(""));
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤4: dlopen 失败: %s", err ? err : "unknown");
    } else {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤5: dlopen 成功，尝试 dlsym...");
        void* sym_init = dlsym(h1, "qemu_init");
        void* sym_loop = dlsym(h1, "qemu_main_loop");
        set_bool("symFound", sym_init != nullptr && sym_loop != nullptr);
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤5: qemu_init=%p, qemu_main_loop=%p", sym_init, sym_loop);
        
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤6: 准备 dlclose...");
        dlclose(h1);
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "步骤6: dlclose 完成");
    }
    */

    // 从 files 目录
    std::string filesPath = "/data/storage/el2/base/haps/entry/files/libqemu_full.so";
    bool existsFiles = FileExists(filesPath);
    set_bool("existsFilesPath", existsFiles);
    set_str("filesPath", filesPath);

    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, "QEMU_DIAG", "========== CheckCoreLib 结束 ==========");
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

// ================== RDP 超时处理和强制关闭 ==================

// 检查 RDP 连接是否超时（返回超时秒数，0表示未超时）
static napi_value RdpCheckTimeout(napi_env env, napi_callback_info info) {
    (void)info;
    int timeout_sec = rdp_check_timeout();
    napi_value result;
    napi_create_int32(env, timeout_sec, &result);
    return result;
}

// 设置 RDP 超时时间（秒）
static napi_value RdpSetTimeout(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc >= 1) {
        int32_t seconds = 30;
        napi_get_value_int32(env, argv[0], &seconds);
        rdp_set_timeout(seconds);
    }
    
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// 请求取消 RDP 连接
static napi_value RdpRequestCancel(napi_env env, napi_callback_info info) {
    (void)info;
    rdp_request_cancel();
    HilogPrint("RDP cancel requested");
    
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// 强制清理 RDP 连接（即使线程卡住也能清理）
static napi_value RdpForceCleanup(napi_env env, napi_callback_info info) {
    (void)info;
    HilogPrint("RDP force cleanup initiated");
    rdp_force_cleanup();
    HilogPrint("RDP force cleanup completed");
    
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// 获取 RDP 状态字符串 (disconnected/connecting/connected/timeout/cancelling)
static napi_value RdpGetStatusString(napi_env env, napi_callback_info info) {
    (void)info;
    const char* status = rdp_get_status_string();
    
    napi_value result;
    napi_create_string_utf8(env, status, strlen(status), &result);
    return result;
}

// ----------------------------- Native VNC (LibVNCClient) -----------------------------
#ifdef LIBVNC_HAVE_CLIENT
#include "third_party/libvncclient/include/rfb/rfbclient.h"
#endif

static std::mutex g_vnc_mutex;
static int g_vnc_next_id = 1;

struct VncSession {
    int id = 0;
#ifdef LIBVNC_HAVE_CLIENT
    rfbClient* client = nullptr;
#endif
    std::thread worker;
    std::atomic<bool> running;  // 在构造函数中初始化
    int width = 0;
    int height = 0;
    std::vector<uint8_t> frame; // RGBA8888
    std::mutex mtx;
    
    VncSession() : running(false) {}
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

// ============================================================================
// Windows 11 配置相关 NAPI 函数
// ============================================================================

/**
 * 设置 TPM 2.0 虚拟设备
 * 参数: vmName (string)
 * 返回: { success: boolean, socketPath?: string, stateDir?: string, error?: string }
 */
static napi_value SetupTpm(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (argc < 1) {
        napi_value errVal;
        napi_create_string_utf8(env, "需要虚拟机名称参数", NAPI_AUTO_LENGTH, &errVal);
        napi_set_named_property(env, result, "error", errVal);
        napi_value successVal;
        napi_get_boolean(env, false, &successVal);
        napi_set_named_property(env, result, "success", successVal);
        return result;
    }
    
    char vmName[256] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], vmName, sizeof(vmName), &len);
    
    tpm_setup_result_t tpmResult;
    int ret = qemu_setup_tpm(vmName, &tpmResult);
    
    napi_value successVal;
    napi_get_boolean(env, tpmResult.success != 0, &successVal);
    napi_set_named_property(env, result, "success", successVal);
    
    if (tpmResult.success) {
        if (tpmResult.socket_path) {
            napi_value pathVal;
            napi_create_string_utf8(env, tpmResult.socket_path, NAPI_AUTO_LENGTH, &pathVal);
            napi_set_named_property(env, result, "socketPath", pathVal);
        }
        if (tpmResult.state_dir) {
            napi_value dirVal;
            napi_create_string_utf8(env, tpmResult.state_dir, NAPI_AUTO_LENGTH, &dirVal);
            napi_set_named_property(env, result, "stateDir", dirVal);
        }
    } else if (tpmResult.error_message) {
        napi_value errVal;
        napi_create_string_utf8(env, tpmResult.error_message, NAPI_AUTO_LENGTH, &errVal);
        napi_set_named_property(env, result, "error", errVal);
    }
    
    return result;
}

/**
 * 设置 UEFI 固件
 * 参数: vmName (string)
 * 返回: { success: boolean, codePath?: string, varsPath?: string, error?: string }
 */
static napi_value SetupUefi(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    napi_value result;
    napi_create_object(env, &result);
    
    if (argc < 1) {
        napi_value errVal;
        napi_create_string_utf8(env, "需要虚拟机名称参数", NAPI_AUTO_LENGTH, &errVal);
        napi_set_named_property(env, result, "error", errVal);
        napi_value successVal;
        napi_get_boolean(env, false, &successVal);
        napi_set_named_property(env, result, "success", successVal);
        return result;
    }
    
    char vmName[256] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], vmName, sizeof(vmName), &len);
    
    uefi_setup_result_t uefiResult;
    int ret = qemu_setup_uefi(vmName, &uefiResult);
    
    napi_value successVal;
    napi_get_boolean(env, uefiResult.success != 0, &successVal);
    napi_set_named_property(env, result, "success", successVal);
    
    if (uefiResult.success) {
        if (uefiResult.code_path) {
            napi_value pathVal;
            napi_create_string_utf8(env, uefiResult.code_path, NAPI_AUTO_LENGTH, &pathVal);
            napi_set_named_property(env, result, "codePath", pathVal);
        }
        if (uefiResult.vars_path) {
            napi_value varsVal;
            napi_create_string_utf8(env, uefiResult.vars_path, NAPI_AUTO_LENGTH, &varsVal);
            napi_set_named_property(env, result, "varsPath", varsVal);
        }
    } else if (uefiResult.error_message) {
        napi_value errVal;
        napi_create_string_utf8(env, uefiResult.error_message, NAPI_AUTO_LENGTH, &errVal);
        napi_set_named_property(env, result, "error", errVal);
    }
    
    return result;
}

/**
 * 检查 Windows 11 兼容性
 * 参数: vmName (string, 可选)
 * 返回: { tpmAvailable, uefiAvailable, secureBootAvailable, overallCompatible, ... }
 */
static napi_value CheckWin11Compatibility(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    const char* vmName = nullptr;
    char vmNameBuf[256] = {0};
    if (argc >= 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, argv[0], vmNameBuf, sizeof(vmNameBuf), &len);
        if (len > 0) vmName = vmNameBuf;
    }
    
    win11_compatibility_result_t compat;
    qemu_check_win11_compatibility(vmName, &compat);
    
    napi_value result;
    napi_create_object(env, &result);
    
    napi_value tpmVal, uefiVal, sbVal, overallVal;
    napi_get_boolean(env, compat.tpm_available != 0, &tpmVal);
    napi_get_boolean(env, compat.uefi_available != 0, &uefiVal);
    napi_get_boolean(env, compat.secure_boot_available != 0, &sbVal);
    napi_get_boolean(env, compat.overall_compatible != 0, &overallVal);
    
    napi_set_named_property(env, result, "tpmAvailable", tpmVal);
    napi_set_named_property(env, result, "uefiAvailable", uefiVal);
    napi_set_named_property(env, result, "secureBootAvailable", sbVal);
    napi_set_named_property(env, result, "overallCompatible", overallVal);
    
    if (compat.tpm_status) {
        napi_value statusVal;
        napi_create_string_utf8(env, compat.tpm_status, NAPI_AUTO_LENGTH, &statusVal);
        napi_set_named_property(env, result, "tpmStatus", statusVal);
    }
    if (compat.uefi_status) {
        napi_value statusVal;
        napi_create_string_utf8(env, compat.uefi_status, NAPI_AUTO_LENGTH, &statusVal);
        napi_set_named_property(env, result, "uefiStatus", statusVal);
    }
    if (compat.secure_boot_status) {
        napi_value statusVal;
        napi_create_string_utf8(env, compat.secure_boot_status, NAPI_AUTO_LENGTH, &statusVal);
        napi_set_named_property(env, result, "secureBootStatus", statusVal);
    }
    
    return result;
}

/**
 * 启用/禁用 Secure Boot
 * 参数: vmName (string), enable (boolean)
 * 返回: boolean
 */
static napi_value EnableSecureBoot(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 2) {
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    char vmName[256] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], vmName, sizeof(vmName), &len);
    
    bool enable = false;
    napi_get_value_bool(env, argv[1], &enable);
    
    int ret = qemu_enable_secure_boot(vmName, enable ? 1 : 0);
    
    napi_value result;
    napi_get_boolean(env, ret == 0, &result);
    return result;
}

// 写入 VM 控制台
static napi_value WriteToVmConsole(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        return nullptr;
    }

    char buffer[1024];
    size_t len;
    napi_get_value_string_utf8(env, args[0], buffer, sizeof(buffer), &len);

    if (g_logCapture) {
        // 添加换行符如果需要
        std::string data(buffer, len);
        g_logCapture->WriteToStdin(data);
    }

    return nullptr;
}

// 设置控制台回调
static napi_value SetConsoleCallback(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) return nullptr;
    
    napi_value resourceName;
    napi_create_string_utf8(env, "ConsoleCallback", NAPI_AUTO_LENGTH, &resourceName);
    
    // 如果已有回调，先释放
    if (g_consoleCallback) {
        napi_release_threadsafe_function(g_consoleCallback, napi_tsfn_abort);
    }
    
    napi_create_threadsafe_function(env, args[0], nullptr, resourceName, 0, 1, nullptr, nullptr, nullptr, ConsoleJsCallback, &g_consoleCallback);
    
    return nullptr;
}

/**
 * 生成 Windows 11 优化的 QEMU 命令参数
 * 参数: vmName (string), memoryMb (number), diskPath (string), isoPath (string)
 * 返回: string
 */
static napi_value BuildWin11Args(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    if (argc < 4) {
        napi_value result;
        napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &result);
        return result;
    }
    
    char vmName[256] = {0};
    char diskPath[512] = {0};
    char isoPath[512] = {0};
    size_t len = 0;
    
    napi_get_value_string_utf8(env, argv[0], vmName, sizeof(vmName), &len);
    
    int32_t memoryMb = 4096;
    napi_get_value_int32(env, argv[1], &memoryMb);
    
    napi_get_value_string_utf8(env, argv[2], diskPath, sizeof(diskPath), &len);
    napi_get_value_string_utf8(env, argv[3], isoPath, sizeof(isoPath), &len);
    
    const char* args = qemu_build_win11_args(vmName, memoryMb, diskPath, isoPath);
    
    napi_value result;
    napi_create_string_utf8(env, args ? args : "", NAPI_AUTO_LENGTH, &result);
    return result;
}

/**
 * 检查 UEFI 是否可用
 * 返回: boolean
 */
static napi_value IsUefiAvailable(napi_env env, napi_callback_info info) {
    int available = qemu_is_uefi_available();
    napi_value result;
    napi_get_boolean(env, available != 0, &result);
    return result;
}

/**
 * 检查 TPM 是否可用
 * 参数: vmName (string, 可选)
 * 返回: boolean
 */
static napi_value IsTpmAvailable(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    
    const char* vmName = nullptr;
    char vmNameBuf[256] = {0};
    if (argc >= 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, argv[0], vmNameBuf, sizeof(vmNameBuf), &len);
        if (len > 0) vmName = vmNameBuf;
    }
    
    int available = qemu_is_tpm_available(vmName);
    napi_value result;
    napi_get_boolean(env, available != 0, &result);
    return result;
}

// ============================================================================

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
    HilogPrint("QEMU: ========================================");
    HilogPrint("QEMU: NAPI Init function called!");
    HilogPrint("QEMU: Environment pointer: " + std::to_string(reinterpret_cast<uintptr_t>(env)));
    HilogPrint("QEMU: Exports pointer: " + std::to_string(reinterpret_cast<uintptr_t>(exports)));
    HilogPrint("QEMU: Module name: qemu_hmos");
    HilogPrint("QEMU: ========================================");
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
        { "getSupportedDevices", 0, GetSupportedDevices, 0, 0, 0, napi_default, 0 },
        { "scanQemuDevices", 0, ScanQemuDevices, 0, 0, 0, napi_default, 0 },
        { "scanQemuDevicesAsync", 0, ScanQemuDevicesAsync, 0, 0, 0, napi_default, 0 },
        { "clearDeviceCache", 0, ClearDeviceCache, 0, 0, 0, napi_default, 0 },
        { "probeQemuDevices", 0, ProbeQemuDevices, 0, 0, 0, napi_default, 0 },
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
        // RDP 超时处理
        { "rdpCheckTimeout", 0, RdpCheckTimeout, 0, 0, 0, napi_default, 0 },
        { "rdpSetTimeout", 0, RdpSetTimeout, 0, 0, 0, napi_default, 0 },
        { "rdpRequestCancel", 0, RdpRequestCancel, 0, 0, 0, napi_default, 0 },
        { "rdpForceCleanup", 0, RdpForceCleanup, 0, 0, 0, napi_default, 0 },
        { "rdpGetStatusString", 0, RdpGetStatusString, 0, 0, 0, napi_default, 0 },
        // Native VNC (client)
        { "vncAvailable", 0, VncAvailable, 0, 0, 0, napi_default, 0 },
        { "vncCreate", 0, VncCreate, 0, 0, 0, napi_default, 0 },
        { "vncConnect", 0, VncConnect, 0, 0, 0, napi_default, 0 },
        { "vncDisconnect", 0, VncDisconnect, 0, 0, 0, napi_default, 0 },
        { "vncGetFrame", 0, VncGetFrame, 0, 0, 0, napi_default, 0 },
        // Windows 11 配置相关
        { "setupTpm", 0, SetupTpm, 0, 0, 0, napi_default, 0 },
        { "setupUefi", 0, SetupUefi, 0, 0, 0, napi_default, 0 },
        { "checkWin11Compatibility", 0, CheckWin11Compatibility, 0, 0, 0, napi_default, 0 },
        { "enableSecureBoot", 0, EnableSecureBoot, 0, 0, 0, napi_default, 0 },
        { "buildWin11Args", 0, BuildWin11Args, 0, 0, 0, napi_default, 0 },
        { "isUefiAvailable", 0, IsUefiAvailable, 0, 0, 0, napi_default, 0 },
        { "isTpmAvailable", 0, IsTpmAvailable, 0, 0, 0, napi_default, 0 },
        { "testFunction", 0, TestFunction, 0, 0, 0, napi_default, 0 },
        { "getModuleInfo", 0, GetModuleInfo, 0, 0, 0, napi_default, 0 },
        { "writeToVmConsole", 0, WriteToVmConsole, 0, 0, 0, napi_default, 0 },
        { "setConsoleCallback", 0, SetConsoleCallback, 0, 0, 0, napi_default, 0 },
        // QMP screendump（VNC 替代方案）
        { "takeScreenshot", 0, TakeScreenshot, 0, 0, 0, napi_default, 0 },
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
        // RDP 超时处理
        { "rdpCheckTimeout", RdpCheckTimeout, 0 },
        { "rdpSetTimeout", RdpSetTimeout, 0 },
        { "rdpRequestCancel", RdpRequestCancel, 0 },
        { "rdpForceCleanup", RdpForceCleanup, 0 },
        { "rdpGetStatusString", RdpGetStatusString, 0 },
        // Native VNC (client)
        { "vncAvailable", VncAvailable, 0 },
        { "vncCreate", VncCreate, 0 },
        { "vncConnect", VncConnect, 0 },
        { "vncDisconnect", VncDisconnect, 0 },
        { "vncGetFrame", VncGetFrame, 0 },
        // Windows 11 配置相关
        { "setupTpm", SetupTpm, 0 },
        { "setupUefi", SetupUefi, 0 },
        { "checkWin11Compatibility", CheckWin11Compatibility, 0 },
        { "enableSecureBoot", EnableSecureBoot, 0 },
        { "buildWin11Args", BuildWin11Args, 0 },
        { "isUefiAvailable", IsUefiAvailable, 0 },
        { "isTpmAvailable", IsTpmAvailable, 0 },
        { "testFunction", TestFunction, 0 },
        { "getModuleInfo", GetModuleInfo, 0 },
        { "writeToVmConsole", WriteToVmConsole, 0 },
        { "setConsoleCallback", SetConsoleCallback, 0 },
        // QMP screendump（VNC 替代方案）
        { "takeScreenshot", TakeScreenshot, 0 },
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
// HarmonyOS NAPI 模块注册
// 使用 "qemu_hmos" 作为模块名（不能用 "entry"，那是保留名称会被 hvigor 覆盖）
// 对应 libqemu_hmos.so
// 只使用 NAPI_MODULE 宏进行注册，不要使用 __attribute__((constructor))
// 否则会导致双重注册冲突
NAPI_MODULE(qemu_hmos, Init)
#else
static napi_module_simple qemuModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "qemu_hmos",  // 模块名称必须与 ArkTS 中的 requireNativeModule('qemu_hmos') 匹配
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};
extern "C" __attribute__((constructor)) void RegisterQemuModule(void) {
    napi_module_register(&qemuModule);
}
#endif
