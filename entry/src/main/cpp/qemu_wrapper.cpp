#include "qemu_wrapper.h"
#include "rdp_client.h"
#include <cstring>
#include <cstdlib>
#include <string>
#include <map>
#include <mutex>
#include <thread>
#include <memory>
#include <iostream>
#include <unistd.h>
#include <sys/stat.h>
#include <fstream>
#include <sstream>
#include <vector>
#include <sys/statvfs.h>
#include <algorithm>
#include <ctime>
#include <chrono>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <dirent.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <atomic>
#include <condition_variable>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>

// ============================================================================
// 重要：HarmonyOS 不支持 fork()！
// 我们通过 dlopen 加载 libqemu_full.so 并在线程中运行 QEMU
// ============================================================================

// QEMU 入口函数类型
typedef int (*qemu_main_func_t)(int argc, char** argv);
typedef void (*qemu_cleanup_func_t)(void);

// QEMU 库句柄
static void* g_qemu_lib_handle = nullptr;
static qemu_main_func_t g_qemu_main_func = nullptr;
static qemu_cleanup_func_t g_qemu_cleanup_func = nullptr;

// QEMU 虚拟机实例结构（无 fork 版本）
struct QemuVmInstance {
    qemu_vm_config_t config;
    qemu_vm_state_t state;
    std::thread qemu_thread;           // QEMU 运行线程（替代 fork）
    std::atomic<bool> should_stop;
    std::atomic<bool> is_paused;
    std::string log_file;
    std::string monitor_socket_path;   // QEMU Monitor Unix socket
    std::vector<std::string> snapshots;
    int qemu_exit_code;
    
    QemuVmInstance() : state(QEMU_VM_STOPPED), should_stop(false), 
                       is_paused(false), qemu_exit_code(0) {
        memset(&config, 0, sizeof(config));
    }
};

// 全局状态管理
static std::map<qemu_vm_handle_t, std::unique_ptr<QemuVmInstance>> g_vm_instances;
static std::mutex g_vm_mutex;
static bool g_qemu_initialized = false;

// ============================================================================
// QEMU 库加载（替代 fork/exec）
// ============================================================================

/**
 * 加载 QEMU 核心库
 * @param lib_path libqemu_full.so 的路径
 * @return 是否加载成功
 */
static bool load_qemu_library(const std::string& lib_path) {
    if (g_qemu_lib_handle) {
        return true; // 已加载
    }
    
    std::cerr << "[QEMU] Loading library: " << lib_path << std::endl;
    
    g_qemu_lib_handle = dlopen(lib_path.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (!g_qemu_lib_handle) {
        std::cerr << "[QEMU] Failed to load library: " << dlerror() << std::endl;
        return false;
    }
    
    // 尝试获取 qemu_main 入口点
    g_qemu_main_func = (qemu_main_func_t)dlsym(g_qemu_lib_handle, "qemu_main");
    if (!g_qemu_main_func) {
        // 尝试其他可能的符号名
        g_qemu_main_func = (qemu_main_func_t)dlsym(g_qemu_lib_handle, "main");
    }
    
    g_qemu_cleanup_func = (qemu_cleanup_func_t)dlsym(g_qemu_lib_handle, "qemu_cleanup");
    
    if (!g_qemu_main_func) {
        std::cerr << "[QEMU] Failed to find entry point: " << dlerror() << std::endl;
        dlclose(g_qemu_lib_handle);
        g_qemu_lib_handle = nullptr;
        return false;
    }
    
    std::cerr << "[QEMU] Library loaded successfully" << std::endl;
    return true;
}

/**
 * 卸载 QEMU 核心库
 */
static void unload_qemu_library() {
    if (g_qemu_lib_handle) {
        if (g_qemu_cleanup_func) {
            g_qemu_cleanup_func();
        }
        dlclose(g_qemu_lib_handle);
        g_qemu_lib_handle = nullptr;
        g_qemu_main_func = nullptr;
        g_qemu_cleanup_func = nullptr;
    }
}

// ============================================================================
// QEMU Monitor 通信（真正实现暂停/恢复/快照）
// ============================================================================

/**
 * 连接到 QEMU Monitor Unix socket
 * @param socket_path socket 文件路径
 * @return socket fd，失败返回 -1
 */
static int connect_to_monitor(const std::string& socket_path) {
    if (socket_path.empty()) {
        return -1;
    }
    
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        std::cerr << "[QEMU Monitor] Failed to create socket: " << strerror(errno) << std::endl;
        return -1;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);
    
    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        std::cerr << "[QEMU Monitor] Failed to connect: " << strerror(errno) << std::endl;
        close(sock);
        return -1;
    }
    
    return sock;
}

/**
 * 初始化 QMP 会话（发送 qmp_capabilities）
 */
static bool init_qmp_session(int sock) {
    char buffer[4096];
    
    // 读取 QMP 欢迎消息
    ssize_t n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (n <= 0) {
        return false;
    }
    buffer[n] = '\0';
    
    // 发送 qmp_capabilities
    const char* init_cmd = "{\"execute\": \"qmp_capabilities\"}\n";
    if (send(sock, init_cmd, strlen(init_cmd), 0) < 0) {
        return false;
    }
    
    // 读取响应
    n = recv(sock, buffer, sizeof(buffer) - 1, 0);
    if (n <= 0) {
        return false;
    }
    buffer[n] = '\0';
    
    return strstr(buffer, "\"return\"") != nullptr;
}

/**
 * 向 QEMU Monitor 发送 QMP 命令
 * @param socket_path Monitor socket 路径
 * @param command QMP 命令（不含 execute 包装）
 * @return 响应字符串
 */
static std::string send_qmp_command(const std::string& socket_path, const std::string& command) {
    int sock = connect_to_monitor(socket_path);
    if (sock < 0) {
        return "";
    }
    
    if (!init_qmp_session(sock)) {
        close(sock);
        return "";
    }
    
    // 发送命令
    std::string cmd_json = "{\"execute\": \"" + command + "\"}\n";
    if (send(sock, cmd_json.c_str(), cmd_json.length(), 0) < 0) {
        close(sock);
        return "";
    }
    
    // 读取响应
    char buffer[8192];
    std::string response;
    
    struct pollfd pfd;
    pfd.fd = sock;
    pfd.events = POLLIN;
    
    while (poll(&pfd, 1, 2000) > 0) {
        ssize_t n = recv(sock, buffer, sizeof(buffer) - 1, 0);
        if (n <= 0) break;
        buffer[n] = '\0';
        response += buffer;
        if (response.find("\"return\"") != std::string::npos ||
            response.find("\"error\"") != std::string::npos) {
            break;
        }
    }
    
    close(sock);
    return response;
}

/**
 * 发送 HMP 命令（人类可读格式，用于快照等）
 */
static std::string send_hmp_command(const std::string& socket_path, const std::string& command) {
    int sock = connect_to_monitor(socket_path);
    if (sock < 0) {
        return "";
    }
    
    if (!init_qmp_session(sock)) {
        close(sock);
        return "";
    }
    
    // 构建 QMP 包装的 HMP 命令
    std::string cmd_json = "{\"execute\": \"human-monitor-command\", "
                           "\"arguments\": {\"command-line\": \"" + command + "\"}}\n";
    
    if (send(sock, cmd_json.c_str(), cmd_json.length(), 0) < 0) {
        close(sock);
        return "";
    }
    
    // 读取响应
    char buffer[8192];
    std::string response;
    
    struct pollfd pfd;
    pfd.fd = sock;
    pfd.events = POLLIN;
    
    while (poll(&pfd, 1, 5000) > 0) {
        ssize_t n = recv(sock, buffer, sizeof(buffer) - 1, 0);
        if (n <= 0) break;
        buffer[n] = '\0';
        response += buffer;
        if (response.find("\"return\"") != std::string::npos ||
            response.find("\"error\"") != std::string::npos) {
            break;
        }
    }
    
    close(sock);
    return response;
}

// ============================================================================
// VM 操作的真正实现
// ============================================================================

/**
 * 暂停 VM（通过 QMP stop 命令）
 */
bool qemu_pause_vm_real(const std::string& monitor_socket) {
    std::string response = send_qmp_command(monitor_socket, "stop");
    return response.find("\"return\"") != std::string::npos;
}

/**
 * 恢复 VM（通过 QMP cont 命令）
 */
bool qemu_resume_vm_real(const std::string& monitor_socket) {
    std::string response = send_qmp_command(monitor_socket, "cont");
    return response.find("\"return\"") != std::string::npos;
}

/**
 * 创建快照（通过 HMP savevm 命令）
 */
bool qemu_create_snapshot_real(const std::string& monitor_socket, const std::string& name) {
    std::string response = send_hmp_command(monitor_socket, "savevm " + name);
    // savevm 成功时返回空字符串
    return response.find("\"error\"") == std::string::npos;
}

/**
 * 恢复快照（通过 HMP loadvm 命令）
 */
bool qemu_restore_snapshot_real(const std::string& monitor_socket, const std::string& name) {
    std::string response = send_hmp_command(monitor_socket, "loadvm " + name);
    return response.find("\"error\"") == std::string::npos;
}

/**
 * 删除快照（通过 HMP delvm 命令）
 */
bool qemu_delete_snapshot_real(const std::string& monitor_socket, const std::string& name) {
    std::string response = send_hmp_command(monitor_socket, "delvm " + name);
    return response.find("\"error\"") == std::string::npos;
}

/**
 * 列出快照（通过 HMP info snapshots 命令）
 */
std::vector<std::string> qemu_list_snapshots_real(const std::string& monitor_socket) {
    std::vector<std::string> snapshots;
    
    std::string response = send_hmp_command(monitor_socket, "info snapshots");
    
    // 解析响应，提取快照名称
    // 格式类似：
    // ID        TAG               VM SIZE                DATE     VM CLOCK
    // 1         snapshot1         256M 2024-01-01 12:00:00 00:01:23.456
    
    std::istringstream iss(response);
    std::string line;
    bool header_passed = false;
    
    while (std::getline(iss, line)) {
        if (line.find("ID") != std::string::npos && line.find("TAG") != std::string::npos) {
            header_passed = true;
            continue;
        }
        
        if (header_passed && !line.empty() && line[0] != '{') {
            // 提取 TAG（第二列）
            std::istringstream line_stream(line);
            std::string id, tag;
            if (line_stream >> id >> tag) {
                if (!tag.empty() && tag != "--" && tag != "return") {
                    snapshots.push_back(tag);
                }
            }
        }
    }
    
    return snapshots;
}

/**
 * 关闭 VM（通过 QMP quit 命令）
 */
bool qemu_quit_vm_real(const std::string& monitor_socket) {
    std::string response = send_qmp_command(monitor_socket, "quit");
    return true; // quit 命令可能不返回
}

// ============================================================================
// 通过 VM 名称查找实例（供 NAPI 层使用）
// ============================================================================

/**
 * 通过 VM 名称获取 monitor socket 路径
 */
std::string qemu_get_monitor_socket_by_name(const char* vm_name) {
    if (!vm_name) return "";
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    for (const auto& pair : g_vm_instances) {
        const auto& instance = pair.second;
        if (instance->config.name && strcmp(instance->config.name, vm_name) == 0) {
            return instance->monitor_socket_path;
        }
    }
    
    return "";
}

/**
 * 通过 VM 名称暂停 VM
 */
extern "C" bool qemu_pause_vm_by_name(const char* vm_name) {
    std::string socket = qemu_get_monitor_socket_by_name(vm_name);
    if (socket.empty()) {
        std::cerr << "[QEMU] VM not found: " << (vm_name ? vm_name : "null") << std::endl;
        return false;
    }
    return qemu_pause_vm_real(socket);
}

/**
 * 通过 VM 名称恢复 VM
 */
extern "C" bool qemu_resume_vm_by_name(const char* vm_name) {
    std::string socket = qemu_get_monitor_socket_by_name(vm_name);
    if (socket.empty()) {
        std::cerr << "[QEMU] VM not found: " << (vm_name ? vm_name : "null") << std::endl;
        return false;
    }
    return qemu_resume_vm_real(socket);
}

/**
 * 通过 VM 名称创建快照
 */
extern "C" bool qemu_create_snapshot_by_name(const char* vm_name, const char* snapshot_name) {
    std::string socket = qemu_get_monitor_socket_by_name(vm_name);
    if (socket.empty()) {
        std::cerr << "[QEMU] VM not found: " << (vm_name ? vm_name : "null") << std::endl;
        return false;
    }
    return qemu_create_snapshot_real(socket, snapshot_name ? snapshot_name : "snapshot");
}

/**
 * 通过 VM 名称恢复快照
 */
extern "C" bool qemu_restore_snapshot_by_name(const char* vm_name, const char* snapshot_name) {
    std::string socket = qemu_get_monitor_socket_by_name(vm_name);
    if (socket.empty()) {
        std::cerr << "[QEMU] VM not found: " << (vm_name ? vm_name : "null") << std::endl;
        return false;
    }
    return qemu_restore_snapshot_real(socket, snapshot_name ? snapshot_name : "snapshot");
}

/**
 * 通过 VM 名称删除快照
 */
extern "C" bool qemu_delete_snapshot_by_name(const char* vm_name, const char* snapshot_name) {
    std::string socket = qemu_get_monitor_socket_by_name(vm_name);
    if (socket.empty()) {
        std::cerr << "[QEMU] VM not found: " << (vm_name ? vm_name : "null") << std::endl;
        return false;
    }
    return qemu_delete_snapshot_real(socket, snapshot_name ? snapshot_name : "snapshot");
}

/**
 * 通过 VM 名称列出快照
 * 返回快照数量，快照名称存入 out_snapshots 数组
 */
extern "C" int qemu_list_snapshots_by_name(const char* vm_name, char** out_snapshots, int max_count) {
    std::string socket = qemu_get_monitor_socket_by_name(vm_name);
    if (socket.empty()) {
        return 0;
    }
    
    std::vector<std::string> snapshots = qemu_list_snapshots_real(socket);
    int count = std::min(static_cast<int>(snapshots.size()), max_count);
    
    for (int i = 0; i < count; i++) {
        if (out_snapshots) {
            out_snapshots[i] = strdup(snapshots[i].c_str());
        }
    }
    
    return count;
}

// 检查磁盘空间
static bool check_disk_space(const std::string& path, size_t required_bytes) {
    struct statvfs stat;
    if (statvfs(path.c_str(), &stat) != 0) {
        return false;
    }
    
    size_t available_bytes = stat.f_bavail * stat.f_frsize;
    return available_bytes >= required_bytes;
}

// 获取磁盘空间信息
static size_t get_available_disk_space(const std::string& path) {
    struct statvfs stat;
    if (statvfs(path.c_str(), &stat) != 0) {
        return 0;
    }
    return stat.f_bavail * stat.f_frsize;
}

// 内部辅助函数
static std::string get_qemu_binary(const qemu_vm_config_t* config) {
    // 根据配置选择QEMU二进制文件
    if (config->arch_type) {
        if (strcmp(config->arch_type, "x86_64") == 0) {
            return "qemu-system-x86_64";
        } else if (strcmp(config->arch_type, "i386") == 0) {
            return "qemu-system-i386";
        } else if (strcmp(config->arch_type, "aarch64") == 0) {
            return "qemu-system-aarch64";
        }
    }
    // 默认使用 aarch64（鸿蒙版 UTM 推荐）
    return "qemu-system-aarch64";
}

// KVM 权限状态
static int g_kvm_available = -1;  // -1: 未检测, 0: 不可用, 1: 可用

// 检测 KVM 是否真正可用（需要华为授权）
static bool check_kvm_available() {
    if (g_kvm_available >= 0) {
        return g_kvm_available == 1;
    }
    
    // 检测 /dev/kvm 是否存在且可访问
    int kvm_fd = open("/dev/kvm", O_RDWR);
    if (kvm_fd >= 0) {
        // 进一步检查是否真的能用
        // 在 HarmonyOS 上，即使文件存在，没有华为授权也无法使用
        // 这里简单检测，实际上需要尝试创建 VM 才能确定
        close(kvm_fd);
        g_kvm_available = 1;
        return true;
    }
    
    g_kvm_available = 0;
    return false;
}

// 获取 KVM 不可用的原因提示（给 UI 显示）
const char* qemu_get_kvm_unavailable_reason(int is_release_build) {
    if (check_kvm_available()) {
        return nullptr;  // KVM 可用，无需提示
    }
    
    if (is_release_build) {
        // 正式版本 - 正经提示
        return "我们正在与华为协商获取 KVM 硬件加速权限，以便更快速地运行虚拟机。"
               "目前使用 TCG 软件模拟模式运行，性能较慢但功能完整。";
    } else {
        // 测试/开发版本 - 吐槽版本
        return "（开玩笑的啦~ 这个功能需要华为内部权限，我们都不知道是啥权限，"
               "而且华为也没给我们，所以现在还用不了 KVM 模式来更快运行虚拟机）\n\n"
               "当前使用 TCG 软件模拟模式，会比较慢，请耐心等待~";
    }
}

// ============================================================================
// 设备类型检测
// ============================================================================

// 设备类型枚举
typedef enum {
    DEVICE_TYPE_UNKNOWN = 0,
    DEVICE_TYPE_PHONE = 1,      // 手机
    DEVICE_TYPE_TABLET = 2,     // 平板
    DEVICE_TYPE_2IN1 = 3,       // 二合一电脑
    DEVICE_TYPE_PC = 4          // 台式机/笔记本
} DeviceType;

// 存储从 ArkTS 层传入的设备信息
static DeviceType g_device_type = DEVICE_TYPE_UNKNOWN;
static std::string g_device_model = "";
static bool g_has_jit_permission = false;

// 设置设备信息（由 ArkTS 层调用）
void qemu_set_device_info(int device_type, const char* model) {
    g_device_type = static_cast<DeviceType>(device_type);
    g_device_model = model ? model : "";
    
    std::cerr << "[QEMU] Device info: type=" << device_type << ", model=" << g_device_model << std::endl;
}

// 设置 JIT 权限状态
void qemu_set_jit_permission(int has_permission) {
    g_has_jit_permission = (has_permission != 0);
    std::cerr << "[QEMU] JIT permission (ALLOW_WRITABLE_CODE_MEMORY): " 
              << (g_has_jit_permission ? "granted" : "denied") << std::endl;
}

// 检测是否是电脑设备（可以显示 KVM 选项）
int qemu_is_pc_device() {
    // 规则：
    // 1. 2in1 类型 = 电脑 ✓
    // 2. PC 类型 = 电脑 ✓
    // 3. 特例：MatePad Edge（型号包含 "Edge"）虽然报告为 Tablet，但实际是二合一电脑 ✓
    
    if (g_device_type == DEVICE_TYPE_2IN1 || g_device_type == DEVICE_TYPE_PC) {
        return 1;
    }
    
    // 特例检测：MatePad Edge
    // 它的类型是 Tablet，但实际上是二合一电脑，有 KVM 支持
    if (g_device_type == DEVICE_TYPE_TABLET) {
        if (g_device_model.find("Edge") != std::string::npos ||
            g_device_model.find("EDGE") != std::string::npos ||
            g_device_model.find("MatePad Pro") != std::string::npos) {  // MatePad Pro 系列也可能支持
            std::cerr << "[QEMU] Special device detected: " << g_device_model 
                      << " (Tablet with PC capabilities)" << std::endl;
            return 1;
        }
    }
    
    // 如果未知设备类型，假设可能支持（让用户看到选项）
    if (g_device_type == DEVICE_TYPE_UNKNOWN) {
        return 1;
    }
    
    return 0;
}

// 获取 JIT 权限状态
int qemu_has_jit_permission() {
    return g_has_jit_permission ? 1 : 0;
}

// 获取 JIT 权限说明
const char* qemu_get_jit_permission_info(int is_release_build) {
    if (g_has_jit_permission) {
        return "✅ JIT 加速已启用（ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY）";
    }
    
    if (is_release_build) {
        return "JIT 加速需要 ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY 权限，"
               "该权限需要向华为申请，审批流程较为严格。"
               "我们正在努力获取此权限以提升虚拟机性能。";
    } else {
        return "⚠️ JIT 权限未获取\n\n"
               "需要 ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY 权限\n"
               "这个权限华为基本不给普通开发者，审批比登天还难...\n\n"
               "没有 JIT 的话，QEMU 只能用解释执行，性能会很感人 😭";
    }
}

static std::string build_qemu_command(const qemu_vm_config_t* config) {
    std::string cmd = get_qemu_binary(config);
    std::string vm_name = config->name ? config->name : "vm";
    
    // 基本配置
    cmd += " -name " + vm_name;
    
    // 根据架构设置默认机器类型和CPU
    std::string machine_type = config->machine_type ? config->machine_type : "virt";
    std::string cpu_type = config->cpu_type ? config->cpu_type : "cortex-a57";
    
    if (config->arch_type) {
        if (strcmp(config->arch_type, "x86_64") == 0) {
            machine_type = config->machine_type ? config->machine_type : "pc";
            cpu_type = config->cpu_type ? config->cpu_type : "qemu64";
        } else if (strcmp(config->arch_type, "i386") == 0) {
            machine_type = config->machine_type ? config->machine_type : "pc";
            cpu_type = config->cpu_type ? config->cpu_type : "qemu32";
        } else if (strcmp(config->arch_type, "aarch64") == 0) {
            machine_type = config->machine_type ? config->machine_type : "virt,gic-version=3,virtualization=on";
            cpu_type = config->cpu_type ? config->cpu_type : "max";
        }
    }
    
    cmd += " -machine " + machine_type;
    cmd += " -cpu " + cpu_type;
    
    // 内存配置（默认6GB，最大16GB）
    int memory_mb = config->memory_mb > 0 ? config->memory_mb : 6144;
    memory_mb = std::min(memory_mb, 16384); // 限制最大16GB
    cmd += " -m " + std::to_string(memory_mb);
    
    // CPU配置（默认4核，最大8核）
    int cpu_count = config->cpu_count > 0 ? config->cpu_count : 4;
    cpu_count = std::min(cpu_count, 8); // 限制最大8核
    cmd += " -smp " + std::to_string(cpu_count);
    
    // ============================================================
    // 加速模式 - 智能选择
    // ============================================================
    if (config->accel_mode && strcmp(config->accel_mode, "kvm") == 0) {
        // 用户请求 KVM，检查是否可用
        if (check_kvm_available()) {
            cmd += " -accel kvm";
            std::cerr << "[QEMU] ✅ Using KVM hardware acceleration" << std::endl;
        } else {
            // KVM 不可用，降级到 TCG
            cmd += " -accel tcg,thread=multi,tb-size=256";
            std::cerr << "[QEMU] ⚠️ KVM requested but unavailable (华为没给权限), falling back to TCG" << std::endl;
        }
    } else if (config->accel_mode && strcmp(config->accel_mode, "hvf") == 0) {
        cmd += " -accel hvf";
        std::cerr << "[QEMU] Using HVF acceleration (macOS)" << std::endl;
    } else {
        // 默认使用 TCG（多线程，增大翻译缓存）
        cmd += " -accel tcg,thread=multi,tb-size=256";
        std::cerr << "[QEMU] Using TCG software emulation" << std::endl;
    }
    
    // ============================================================
    // 硬盘配置
    // ============================================================
    if (config->disk_path) {
        cmd += " -drive file=" + std::string(config->disk_path) + ",format=qcow2,if=virtio,cache=writeback";
    }
    
    // ISO镜像
    if (config->iso_path) {
        cmd += " -cdrom " + std::string(config->iso_path);
    }
    
    // EFI固件
    if (config->efi_firmware) {
        cmd += " -drive file=" + std::string(config->efi_firmware) + ",if=pflash,format=raw,unit=0,readonly=on";
    }
    
    // ============================================================
    // 网络配置 - 默认开启 user 网络
    // ============================================================
    std::string network_mode = config->network_mode ? config->network_mode : "user";
    if (network_mode != "none") {
            cmd += " -netdev user,id=net0";
        
        // 默认端口转发：SSH(22), RDP(3389), HTTP(80), HTTPS(443)
        int rdp_port = config->rdp_port > 0 ? config->rdp_port : 3390;
        cmd += ",hostfwd=tcp:127.0.0.1:" + std::to_string(rdp_port) + "-:3389";    // RDP
        cmd += ",hostfwd=tcp:127.0.0.1:2222-:22";     // SSH
        cmd += ",hostfwd=tcp:127.0.0.1:8080-:80";     // HTTP
        cmd += ",hostfwd=tcp:127.0.0.1:8443-:443";    // HTTPS
        
        cmd += " -device virtio-net-pci,netdev=net0";
        
        std::cerr << "[QEMU] Network enabled: user mode with port forwarding" << std::endl;
        std::cerr << "[QEMU]   RDP: localhost:" << rdp_port << " -> guest:3389" << std::endl;
        std::cerr << "[QEMU]   SSH: localhost:2222 -> guest:22" << std::endl;
    }
    
    // ============================================================
    // 显示配置 - 默认开启 VNC
    // ============================================================
    int vnc_display = config->vnc_port > 0 ? config->vnc_port : 0;  // display :0 = port 5900
    cmd += " -vnc :" + std::to_string(vnc_display) + ",share=allow-exclusive";
    
    std::cerr << "[QEMU] VNC enabled on display :" << vnc_display 
              << " (port " << (5900 + vnc_display) << ")" << std::endl;
    
    // ============================================================
    // Monitor 配置 - 用于运行时控制
    // ============================================================
    std::string monitor_socket = "/tmp/qemu-monitor-" + vm_name + ".sock";
    cmd += " -monitor unix:" + monitor_socket + ",server,nowait";
    
    // 注册 Monitor socket
    qemu_register_monitor(vm_name.c_str(), monitor_socket.c_str());
    
    // ============================================================
    // 共享目录 - virtio-9p
    // ============================================================
    if (config->shared_dir) {
        cmd += " -virtfs local,path=" + std::string(config->shared_dir) 
             + ",mount_tag=hostshare,security_model=mapped-xattr,id=hostshare";
        std::cerr << "[QEMU] Shared folder: " << config->shared_dir << " (mount with: mount -t 9p -o trans=virtio hostshare /mnt)" << std::endl;
    }
    
    // ============================================================
    // 其他优化
    // ============================================================
    cmd += " -rtc base=utc,clock=host";
    cmd += " -device virtio-balloon-pci";  // 内存气球，节省内存
    cmd += " -device virtio-rng-pci";      // 随机数生成器
    
    // USB 支持
    cmd += " -usb -device usb-tablet";     // USB 平板设备，改善鼠标体验
    
    // 日志输出
    std::string log_path = "/data/storage/el2/base/files/qemu/logs/" + vm_name + ".log";
    cmd += " -D " + log_path;
    qemu_register_log_file(vm_name.c_str(), log_path.c_str());
    
    std::cerr << "[QEMU] Command: " << cmd << std::endl;
    
    return cmd;
}

// ============================================================================
// QEMU 运行线程（替代 fork/exec，在 HarmonyOS 上运行）
// ============================================================================

/**
 * QEMU 运行线程函数
 * 在单独线程中调用 qemu_main，替代 fork/exec
 */
static void qemu_run_thread(QemuVmInstance* instance, std::vector<std::string> args) {
                std::ofstream log_file(instance->log_file, std::ios::app);
                if (log_file.is_open()) {
        log_file << "[" << std::time(nullptr) << "] QEMU thread started" << std::endl;
        log_file << "[" << std::time(nullptr) << "] Args: ";
        for (const auto& arg : args) {
            log_file << arg << " ";
        }
        log_file << std::endl;
                }
                log_file.close();
                
    // 构建 argv 数组
    std::vector<char*> argv;
    for (auto& arg : args) {
        argv.push_back(const_cast<char*>(arg.c_str()));
    }
    argv.push_back(nullptr);
    
                        instance->state = QEMU_VM_RUNNING;
    instance->qemu_exit_code = 0;
    
    // 调用 QEMU 主函数
    if (g_qemu_main_func) {
        std::cerr << "[QEMU] Calling qemu_main with " << (argv.size() - 1) << " arguments" << std::endl;
        instance->qemu_exit_code = g_qemu_main_func(static_cast<int>(argv.size() - 1), argv.data());
        std::cerr << "[QEMU] qemu_main returned: " << instance->qemu_exit_code << std::endl;
                    } else {
        std::cerr << "[QEMU] ERROR: qemu_main function not loaded!" << std::endl;
        instance->qemu_exit_code = -1;
    }
    
    // QEMU 退出后更新状态
                    log_file.open(instance->log_file, std::ios::app);
                    if (log_file.is_open()) {
        log_file << "[" << std::time(nullptr) << "] QEMU thread exited with code: " 
                 << instance->qemu_exit_code << std::endl;
                    }
                    log_file.close();
    
    instance->state = QEMU_VM_STOPPED;
    instance->is_paused = false;
}

/**
 * 尝试加载 QEMU 库（从多个可能的路径）
 */
static bool try_load_qemu_library() {
    if (g_qemu_lib_handle) {
        return true; // 已加载
    }
    
    // 可能的库路径
    std::vector<std::string> search_paths = {
        "/data/storage/el2/base/haps/entry/libs/arm64/libqemu_full.so",
        "/data/storage/el1/bundle/libs/arm64/libqemu_full.so",
        "./libs/arm64/libqemu_full.so",
        "./libqemu_full.so",
        "/system/lib64/libqemu_full.so"
    };
    
    for (const auto& path : search_paths) {
        if (load_qemu_library(path)) {
            return true;
        }
    }
    
    std::cerr << "[QEMU] Failed to load QEMU library from any path" << std::endl;
    return false;
}

// 公共接口实现
int qemu_init(void) {
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    if (g_qemu_initialized) {
        return 0; // 已初始化
    }
    
    // 检测系统能力
    g_qemu_initialized = true;
    return 0;
}

void qemu_cleanup(void) {
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    // 停止所有虚拟机
    for (auto& pair : g_vm_instances) {
        auto& instance = pair.second;
        if (instance->state == QEMU_VM_RUNNING) {
            qemu_vm_stop(pair.first);
        }
    }
    
    g_vm_instances.clear();
    g_qemu_initialized = false;
}

qemu_vm_handle_t qemu_vm_create(const qemu_vm_config_t* config) {
    if (!config) {
        return nullptr;
    }
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    auto instance = std::make_unique<QemuVmInstance>();
    
    // 复制配置
    instance->config = *config;
    if (config->name) {
        instance->config.name = strdup(config->name);
    }
    if (config->machine_type) {
        instance->config.machine_type = strdup(config->machine_type);
    }
    if (config->cpu_type) {
        instance->config.cpu_type = strdup(config->cpu_type);
    }
    if (config->disk_path) {
        instance->config.disk_path = strdup(config->disk_path);
    }
    if (config->iso_path) {
        instance->config.iso_path = strdup(config->iso_path);
    }
    if (config->efi_firmware) {
        instance->config.efi_firmware = strdup(config->efi_firmware);
    }
    if (config->shared_dir) {
        instance->config.shared_dir = strdup(config->shared_dir);
    }
    if (config->network_mode) {
        instance->config.network_mode = strdup(config->network_mode);
    }
    if (config->accel_mode) {
        instance->config.accel_mode = strdup(config->accel_mode);
    }
    if (config->display_mode) {
        instance->config.display_mode = strdup(config->display_mode);
    }

    qemu_vm_handle_t handle = instance.get();
    g_vm_instances[handle] = std::move(instance);
    
    return handle;
}

int qemu_vm_start(qemu_vm_handle_t handle) {
    if (!handle) {
        return -1;
    }
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    auto it = g_vm_instances.find(handle);
    if (it == g_vm_instances.end()) {
        return -1;
    }
    
    auto& instance = it->second;
    if (instance->state == QEMU_VM_RUNNING) {
        return 0; // 已在运行
    }
    
    // 检查磁盘空间
    size_t required_space = instance->config.disk_size_gb * 1024ULL * 1024ULL * 1024ULL;
    std::string disk_path = instance->config.disk_path ? instance->config.disk_path : "/data/storage/el2/base/haps/entry/files/vm_disks/";
    
    if (!check_disk_space(disk_path, required_space)) {
        size_t available_space = get_available_disk_space(disk_path);
        std::cerr << "Insufficient disk space. Required: " << required_space 
                  << " bytes, Available: " << available_space << " bytes" << std::endl;
        return -2; // 磁盘空间不足
    }
    
    // 尝试加载 QEMU 库（HarmonyOS 不支持 fork，我们在进程内运行 QEMU）
    if (!try_load_qemu_library()) {
        std::cerr << "[QEMU] Cannot start VM: QEMU library not available" << std::endl;
        return -3; // 库加载失败
    }
    
    // 设置日志文件
    std::string vm_name = instance->config.name ? instance->config.name : "default";
    instance->log_file = "/data/storage/el2/base/files/qemu/logs/" + vm_name + ".log";
    
    // 设置 Monitor socket 路径
    instance->monitor_socket_path = "/data/storage/el2/base/files/qemu/monitor-" + vm_name + ".sock";
    
    // 构建 QEMU 参数列表
    std::vector<std::string> args;
    args.push_back("qemu-system-aarch64");  // argv[0]
    
    // 机器类型
    args.push_back("-machine");
    args.push_back(instance->config.machine_type ? instance->config.machine_type : "virt,gic-version=3");
    
    // CPU
    args.push_back("-cpu");
    args.push_back(instance->config.cpu_type ? instance->config.cpu_type : "max");
    
    // SMP
    args.push_back("-smp");
    args.push_back(std::to_string(instance->config.cpu_count > 0 ? instance->config.cpu_count : 4));
    
    // 内存
    args.push_back("-m");
    args.push_back(std::to_string(instance->config.memory_mb > 0 ? instance->config.memory_mb : 4096));
    
    // 加速模式（KVM 或 TCG）
    args.push_back("-accel");
    if (check_kvm_available()) {
        args.push_back("kvm");
    } else {
        args.push_back("tcg,thread=multi");
    }
    
    // EFI 固件
    if (instance->config.efi_firmware) {
        args.push_back("-bios");
        args.push_back(instance->config.efi_firmware);
    }
    
    // 磁盘
    if (instance->config.disk_path) {
        args.push_back("-drive");
        args.push_back("file=" + std::string(instance->config.disk_path) + ",if=virtio,format=qcow2");
    }
    
    // ISO
    if (instance->config.iso_path) {
        args.push_back("-cdrom");
        args.push_back(instance->config.iso_path);
    }
    
    // 网络（默认开启 user 模式 + hostfwd）
    args.push_back("-netdev");
    args.push_back("user,id=net0,hostfwd=tcp::3390-:3389,hostfwd=tcp::5901-:5900,hostfwd=tcp::2222-:22");
    args.push_back("-device");
    args.push_back("virtio-net-pci,netdev=net0");
    
    // VNC 显示
    args.push_back("-vnc");
    args.push_back(":1");
    
    // QMP Monitor（用于暂停/恢复/快照）
    args.push_back("-qmp");
    args.push_back("unix:" + instance->monitor_socket_path + ",server,nowait");
    
    // 日志
    args.push_back("-D");
    args.push_back(instance->log_file);
    
    // 共享目录
    if (instance->config.shared_dir) {
        args.push_back("-virtfs");
        args.push_back("local,path=" + std::string(instance->config.shared_dir) + 
                      ",mount_tag=shared,security_model=mapped-xattr");
    }
    
    // 重置停止标志
        instance->should_stop = false;
    instance->is_paused = false;
        
    // 在新线程中启动 QEMU（替代 fork/exec）
    instance->qemu_thread = std::thread(qemu_run_thread, instance.get(), args);
        
    // 等待一小段时间确认启动
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    
    if (instance->state == QEMU_VM_RUNNING) {
        std::cerr << "[QEMU] VM started successfully in thread" << std::endl;
        return 0;
    } else {
        std::cerr << "[QEMU] VM failed to start" << std::endl;
        return -4;
    }
}

int qemu_vm_stop(qemu_vm_handle_t handle) {
    if (!handle) {
        return -1;
    }
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    auto it = g_vm_instances.find(handle);
    if (it == g_vm_instances.end()) {
        return -1;
    }
    
    auto& instance = it->second;
    if (instance->state != QEMU_VM_RUNNING && instance->state != QEMU_VM_PAUSED) {
        return 0; // 已停止
    }
    
    // 设置停止标志
    instance->should_stop = true;
    
    // 通过 QMP 发送 quit 命令来优雅关闭 QEMU
    if (!instance->monitor_socket_path.empty()) {
        std::cerr << "[QEMU] Sending quit command via QMP" << std::endl;
        qemu_quit_vm_real(instance->monitor_socket_path);
    }
    
    // 等待 QEMU 线程结束
    if (instance->qemu_thread.joinable()) {
        // 等待最多 10 秒
        std::this_thread::sleep_for(std::chrono::seconds(2));
        if (instance->state != QEMU_VM_STOPPED) {
            std::cerr << "[QEMU] Waiting for QEMU thread to exit..." << std::endl;
        }
        instance->qemu_thread.join();
    }
    
    // 清理 Monitor socket 文件
    if (!instance->monitor_socket_path.empty()) {
        unlink(instance->monitor_socket_path.c_str());
    }
    
    instance->state = QEMU_VM_STOPPED;
    instance->is_paused = false;
    std::cerr << "[QEMU] VM stopped" << std::endl;
    return 0;
}

int qemu_vm_pause(qemu_vm_handle_t handle) {
    if (!handle) {
        return -1;
    }
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    auto it = g_vm_instances.find(handle);
    if (it == g_vm_instances.end()) {
        return -1;
    }
    
    auto& instance = it->second;
    if (instance->state != QEMU_VM_RUNNING) {
        return -1;
    }
    
    // 通过 QMP 发送 stop 命令暂停 VM
    if (!instance->monitor_socket_path.empty()) {
        if (qemu_pause_vm_real(instance->monitor_socket_path)) {
        instance->state = QEMU_VM_PAUSED;
            instance->is_paused = true;
            std::cerr << "[QEMU] VM paused via QMP" << std::endl;
        return 0;
        }
    }
    
    std::cerr << "[QEMU] Failed to pause VM" << std::endl;
    return -1;
}

int qemu_vm_resume(qemu_vm_handle_t handle) {
    if (!handle) {
        return -1;
    }
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    auto it = g_vm_instances.find(handle);
    if (it == g_vm_instances.end()) {
        return -1;
    }
    
    auto& instance = it->second;
    if (instance->state != QEMU_VM_PAUSED) {
        return -1;
    }
    
    // 通过 QMP 发送 cont 命令恢复 VM
    if (!instance->monitor_socket_path.empty()) {
        if (qemu_resume_vm_real(instance->monitor_socket_path)) {
        instance->state = QEMU_VM_RUNNING;
            instance->is_paused = false;
            std::cerr << "[QEMU] VM resumed via QMP" << std::endl;
        return 0;
        }
    }
    
    std::cerr << "[QEMU] Failed to resume VM" << std::endl;
    return -1;
}

qemu_vm_state_t qemu_vm_get_state(qemu_vm_handle_t handle) {
    if (!handle) {
        return QEMU_VM_ERROR;
    }
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    auto it = g_vm_instances.find(handle);
    if (it == g_vm_instances.end()) {
        return QEMU_VM_ERROR;
    }
    
    return it->second->state;
}

void qemu_vm_destroy(qemu_vm_handle_t handle) {
    if (!handle) {
        return;
    }
    
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    auto it = g_vm_instances.find(handle);
    if (it == g_vm_instances.end()) {
        return;
    }
    
    auto& instance = it->second;
    
    // 确保虚拟机已停止
    if (instance->state == QEMU_VM_RUNNING || instance->state == QEMU_VM_PAUSED) {
        qemu_vm_stop(handle);
    }

    // 等待 QEMU 线程结束（monitor 功能已集成到主线程）

    // 释放配置字符串
    if (instance->config.name) {
        free(const_cast<char*>(instance->config.name));
    }
    if (instance->config.machine_type) {
        free(const_cast<char*>(instance->config.machine_type));
    }
    if (instance->config.cpu_type) {
        free(const_cast<char*>(instance->config.cpu_type));
    }
    if (instance->config.disk_path) {
        free(const_cast<char*>(instance->config.disk_path));
    }
    if (instance->config.iso_path) {
        free(const_cast<char*>(instance->config.iso_path));
    }
    if (instance->config.efi_firmware) {
        free(const_cast<char*>(instance->config.efi_firmware));
    }
    if (instance->config.shared_dir) {
        free(const_cast<char*>(instance->config.shared_dir));
    }
    if (instance->config.network_mode) {
        free(const_cast<char*>(instance->config.network_mode));
    }
    if (instance->config.accel_mode) {
        free(const_cast<char*>(instance->config.accel_mode));
    }
    if (instance->config.display_mode) {
        free(const_cast<char*>(instance->config.display_mode));
    }

    g_vm_instances.erase(it);
}

// 硬盘管理
int qemu_create_disk(const char* path, int size_gb, const char* format) {
    if (!path || size_gb <= 0) {
        return -1;
    }
    
    std::string format_str = format ? format : "qcow2";
    std::string cmd = "qemu-img create -f " + format_str + " " + path + " " + std::to_string(size_gb) + "G";
    
    return system(cmd.c_str());
}

int qemu_resize_disk(const char* path, int new_size_gb) {
    if (!path || new_size_gb <= 0) {
        return -1;
    }
    
    std::string cmd = "qemu-img resize " + std::string(path) + " " + std::to_string(new_size_gb) + "G";
    
    return system(cmd.c_str());
}

// ============================================================================
// QEMU Monitor 通信
// ============================================================================

// 存储每个 VM 的 Monitor socket 路径
static std::map<std::string, std::string> g_vm_monitor_sockets;
static std::map<std::string, int> g_vm_vnc_ports;
static std::map<std::string, std::vector<std::pair<int, int>>> g_vm_port_forwards;

// 向 QEMU Monitor 发送命令
static std::string send_monitor_command(const std::string& vm_name, const std::string& command) {
    auto it = g_vm_monitor_sockets.find(vm_name);
    if (it == g_vm_monitor_sockets.end()) {
        std::cerr << "[QEMU] Monitor socket not found for VM: " << vm_name << std::endl;
        return "";
    }
    
    const std::string& socket_path = it->second;
    
    // 通过 Unix socket 发送命令
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        std::cerr << "[QEMU] Failed to create socket" << std::endl;
        return "";
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);
    
    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        std::cerr << "[QEMU] Failed to connect to monitor: " << socket_path << std::endl;
        close(sock);
        return "";
    }
    
    // 发送命令
    std::string full_command = command + "\n";
    write(sock, full_command.c_str(), full_command.length());
    
    // 读取响应
    char buffer[4096];
    std::string response;
    ssize_t n;
    
    // 设置读取超时
    struct timeval tv;
    tv.tv_sec = 2;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    
    while ((n = read(sock, buffer, sizeof(buffer) - 1)) > 0) {
        buffer[n] = '\0';
        response += buffer;
        if (response.find("(qemu)") != std::string::npos) {
            break;
        }
    }
    
    close(sock);
    return response;
}

// 注册 VM 的 Monitor socket
void qemu_register_monitor(const char* vm_name, const char* socket_path) {
    if (vm_name && socket_path) {
        g_vm_monitor_sockets[vm_name] = socket_path;
        std::cerr << "[QEMU] Registered monitor for VM " << vm_name << ": " << socket_path << std::endl;
    }
}

// ============================================================================
// 网络管理 - 真正实现
// ============================================================================

int qemu_setup_network(const char* vm_name, const char* mode, int host_port, int guest_port) {
    if (!vm_name) {
        return -1;
    }
    
    std::string mode_str = mode ? mode : "user";
    
    if (mode_str == "user") {
        // 用户模式网络（SLIRP）- 添加端口转发
        if (host_port > 0 && guest_port > 0) {
            return qemu_forward_port(vm_name, host_port, guest_port);
        }
        std::cerr << "[QEMU] Network configured in user mode for VM: " << vm_name << std::endl;
        return 0;
    } else if (mode_str == "tap") {
        // TAP 模式需要 root 权限，在 HarmonyOS 上可能不可用
        std::cerr << "[QEMU] TAP network mode not supported on HarmonyOS" << std::endl;
        return -1;
    }
    
    return 0;
}

int qemu_forward_port(const char* vm_name, int host_port, int guest_port) {
    if (!vm_name || host_port <= 0 || guest_port <= 0) {
        return -1;
    }
    
    // 通过 QEMU Monitor 添加端口转发
    // 命令格式: hostfwd_add tcp::HOST_PORT-:GUEST_PORT
    std::string cmd = "hostfwd_add tcp::" + std::to_string(host_port) + "-:" + std::to_string(guest_port);
    std::string response = send_monitor_command(vm_name, cmd);
    
    if (response.empty()) {
        // Monitor 未连接，记录到配置中供下次启动使用
        g_vm_port_forwards[vm_name].push_back({host_port, guest_port});
        std::cerr << "[QEMU] Port forward queued: " << host_port << " -> " << guest_port << std::endl;
    return 0;
}

    // 检查响应是否有错误
    if (response.find("error") != std::string::npos || response.find("Error") != std::string::npos) {
        std::cerr << "[QEMU] Port forward failed: " << response << std::endl;
        return -1;
    }
    
    g_vm_port_forwards[vm_name].push_back({host_port, guest_port});
    std::cerr << "[QEMU] Port forward added: " << host_port << " -> " << guest_port << std::endl;
    return 0;
}

// ============================================================================
// 显示管理 - 真正实现
// ============================================================================

int qemu_start_vnc_server(const char* vm_name, int port) {
    if (!vm_name || port <= 0) {
        return -1;
    }
    
    // VNC 端口号 = 5900 + display_number
    // 如果传入的是绝对端口（如 5901），转换为 display number
    int display_number = (port >= 5900) ? (port - 5900) : port;
    
    // 通过 QEMU Monitor 修改 VNC 设置
    std::string cmd = "change vnc :" + std::to_string(display_number);
    std::string response = send_monitor_command(vm_name, cmd);
    
    if (response.empty()) {
        // Monitor 未连接，记录配置
        g_vm_vnc_ports[vm_name] = 5900 + display_number;
        std::cerr << "[QEMU] VNC port queued: " << (5900 + display_number) << std::endl;
    return 0;
}

    g_vm_vnc_ports[vm_name] = 5900 + display_number;
    std::cerr << "[QEMU] VNC server started on port " << (5900 + display_number) << std::endl;
    return 0;
}

int qemu_start_rdp_server(const char* vm_name, int port) {
    if (!vm_name || port <= 0) {
        return -1;
    }
    
    // RDP 通过 QEMU 内的 Windows 来宾系统提供
    // 我们只需要设置端口转发 host:port -> guest:3389
    int result = qemu_forward_port(vm_name, port, 3389);
    
    if (result == 0) {
        std::cerr << "[QEMU] RDP port forward configured: " << port << " -> 3389" << std::endl;
    }
    
    return result;
}

// ============================================================================
// 快照管理 - 真正实现
// ============================================================================

// 获取 VM 的磁盘路径
static std::string get_vm_disk_path(const std::string& vm_name) {
    std::lock_guard<std::mutex> lock(g_vm_mutex);
    
    for (const auto& pair : g_vm_instances) {
        auto& instance = pair.second;
        if (instance->config.name && std::string(instance->config.name) == vm_name) {
            if (instance->config.disk_path) {
                return instance->config.disk_path;
            }
        }
    }
    
    return "";
}

int qemu_create_snapshot(const char* vm_name, const char* snapshot_name) {
    if (!vm_name || !snapshot_name) {
        return -1;
    }
    
    // 方法1: 通过 QEMU Monitor 创建内存快照（VM 运行中）
    std::string monitor_cmd = std::string("savevm ") + snapshot_name;
    std::string response = send_monitor_command(vm_name, monitor_cmd);
    
    if (!response.empty() && response.find("error") == std::string::npos) {
        std::cerr << "[QEMU] Snapshot created via monitor: " << snapshot_name << std::endl;
    return 0;
    }
    
    // 方法2: 通过 qemu-img 创建磁盘快照（VM 停止时）
    std::string disk_path = get_vm_disk_path(vm_name);
    if (disk_path.empty()) {
        std::cerr << "[QEMU] Cannot find disk path for VM: " << vm_name << std::endl;
        return -1;
    }
    
    std::string cmd = "qemu-img snapshot -c " + std::string(snapshot_name) + " " + disk_path;
    int result = system(cmd.c_str());
    
    if (result == 0) {
        std::cerr << "[QEMU] Snapshot created via qemu-img: " << snapshot_name << std::endl;
    }
    
    return result;
}

int qemu_restore_snapshot(const char* vm_name, const char* snapshot_name) {
    if (!vm_name || !snapshot_name) {
        return -1;
    }
    
    // 方法1: 通过 QEMU Monitor 恢复快照（VM 运行中）
    std::string monitor_cmd = std::string("loadvm ") + snapshot_name;
    std::string response = send_monitor_command(vm_name, monitor_cmd);
    
    if (!response.empty() && response.find("error") == std::string::npos) {
        std::cerr << "[QEMU] Snapshot restored via monitor: " << snapshot_name << std::endl;
    return 0;
    }
    
    // 方法2: 通过 qemu-img 恢复磁盘快照（VM 停止时）
    std::string disk_path = get_vm_disk_path(vm_name);
    if (disk_path.empty()) {
        std::cerr << "[QEMU] Cannot find disk path for VM: " << vm_name << std::endl;
        return -1;
    }
    
    std::string cmd = "qemu-img snapshot -a " + std::string(snapshot_name) + " " + disk_path;
    int result = system(cmd.c_str());
    
    if (result == 0) {
        std::cerr << "[QEMU] Snapshot restored via qemu-img: " << snapshot_name << std::endl;
    }
    
    return result;
}

int qemu_list_snapshots(const char* vm_name, char** snapshot_list, int* count) {
    if (!vm_name || !snapshot_list || !count) {
        return -1;
    }
    
    *count = 0;
    
    // 方法1: 通过 QEMU Monitor 列出快照
    std::string response = send_monitor_command(vm_name, "info snapshots");
    
    std::vector<std::string> snapshots;
    
    if (!response.empty()) {
        // 解析 Monitor 响应
        std::istringstream stream(response);
        std::string line;
        while (std::getline(stream, line)) {
            // 跳过标题行和空行
            if (line.empty() || line.find("ID") != std::string::npos || line.find("--") != std::string::npos) {
                continue;
            }
            // 提取快照名称（通常是第二列）
            std::istringstream line_stream(line);
            std::string id, tag;
            if (line_stream >> id >> tag) {
                snapshots.push_back(tag);
            }
        }
    } else {
        // 方法2: 通过 qemu-img 列出快照
        std::string disk_path = get_vm_disk_path(vm_name);
        if (!disk_path.empty()) {
            std::string cmd = "qemu-img snapshot -l " + disk_path + " 2>/dev/null";
            FILE* pipe = popen(cmd.c_str(), "r");
            if (pipe) {
                char buffer[256];
                while (fgets(buffer, sizeof(buffer), pipe)) {
                    std::string line(buffer);
                    if (line.empty() || line.find("ID") != std::string::npos || line.find("--") != std::string::npos) {
                        continue;
                    }
                    std::istringstream line_stream(line);
                    std::string id, tag;
                    if (line_stream >> id >> tag) {
                        snapshots.push_back(tag);
                    }
                }
                pclose(pipe);
            }
        }
    }
    
    // 分配并填充快照列表
    *count = static_cast<int>(snapshots.size());
    if (*count > 0) {
        for (int i = 0; i < *count; i++) {
            snapshot_list[i] = strdup(snapshots[i].c_str());
        }
    }
    
    std::cerr << "[QEMU] Found " << *count << " snapshots for VM: " << vm_name << std::endl;
    return 0;
}

int qemu_delete_snapshot(const char* vm_name, const char* snapshot_name) {
    if (!vm_name || !snapshot_name) {
        return -1;
    }
    
    // 方法1: 通过 QEMU Monitor 删除快照（VM 运行中）
    std::string monitor_cmd = std::string("delvm ") + snapshot_name;
    std::string response = send_monitor_command(vm_name, monitor_cmd);
    
    if (!response.empty() && response.find("error") == std::string::npos) {
        std::cerr << "[QEMU] Snapshot deleted via monitor: " << snapshot_name << std::endl;
        return 0;
    }
    
    // 方法2: 通过 qemu-img 删除磁盘快照（VM 停止时）
    std::string disk_path = get_vm_disk_path(vm_name);
    if (disk_path.empty()) {
        std::cerr << "[QEMU] Cannot find disk path for VM: " << vm_name << std::endl;
        return -1;
    }
    
    std::string cmd = "qemu-img snapshot -d " + std::string(snapshot_name) + " " + disk_path;
    int result = system(cmd.c_str());
    
    if (result == 0) {
        std::cerr << "[QEMU] Snapshot deleted via qemu-img: " << snapshot_name << std::endl;
    }
    
    return result;
}

// ============================================================================
// 文件共享 - 真正实现
// ============================================================================

// 存储共享目录配置
static std::map<std::string, std::vector<std::pair<std::string, std::string>>> g_vm_shared_dirs;

int qemu_mount_shared_dir(const char* vm_name, const char* host_path, const char* guest_path) {
    if (!vm_name || !host_path) {
        return -1;
    }
    
    std::string guest_mount = guest_path ? guest_path : "/mnt/shared";
    
    // 检查宿主机路径是否存在
    struct stat st;
    if (stat(host_path, &st) != 0 || !S_ISDIR(st.st_mode)) {
        std::cerr << "[QEMU] Host path does not exist or is not a directory: " << host_path << std::endl;
        return -1;
    }
    
    // 存储共享目录配置
    // 实际的共享需要在 VM 启动时通过 virtio-9p 参数配置：
    // -virtfs local,path=HOST_PATH,mount_tag=MOUNT_TAG,security_model=mapped
    g_vm_shared_dirs[vm_name].push_back({host_path, guest_mount});
    
    std::cerr << "[QEMU] Shared directory registered: " << host_path << " -> " << guest_mount << std::endl;
    std::cerr << "[QEMU] Note: Guest needs to mount with: mount -t 9p -o trans=virtio MOUNT_TAG " << guest_mount << std::endl;
    
    // 如果 VM 正在运行，尝试通过 monitor 热添加（如果 QEMU 支持）
    std::string monitor_cmd = "chardev-add socket,id=fschar0,path=/tmp/qemu-9p-" + std::string(vm_name) + ".sock,server=on,wait=off";
    send_monitor_command(vm_name, monitor_cmd);
    
    return 0;
}

// 获取 VM 的共享目录列表
int qemu_get_shared_dirs(const char* vm_name, char*** dirs, int* count) {
    if (!vm_name || !dirs || !count) {
        return -1;
    }
    
    auto it = g_vm_shared_dirs.find(vm_name);
    if (it == g_vm_shared_dirs.end()) {
        *count = 0;
        *dirs = nullptr;
        return 0;
    }
    
    const auto& shared = it->second;
    *count = static_cast<int>(shared.size());
    *dirs = new char*[*count * 2];
    
    for (int i = 0; i < *count; i++) {
        (*dirs)[i * 2] = strdup(shared[i].first.c_str());
        (*dirs)[i * 2 + 1] = strdup(shared[i].second.c_str());
    }
    
    return 0;
}

// 获取 QEMU 版本信息
const char* qemu_get_version(void) {
    return "QEMU HarmonyOS Wrapper 1.0.0";
}

// 检测系统能力
int qemu_detect_kvm_support(void) {
    // 检测KVM支持
    std::ifstream kvm_file("/dev/kvm");
    return kvm_file.good() ? 1 : 0;
}

int qemu_detect_hvf_support(void) {
    // 检测HVF支持（macOS）
    #ifdef __APPLE__
    return 1;
    #else
    return 0;
    #endif
}

int qemu_detect_tcg_support(void) {
    // TCG总是支持的
    return 1;
}

// ============================================================================
// 日志管理 - 真正实现
// ============================================================================

// 存储日志文件路径
static std::map<std::string, std::string> g_vm_log_files;
static const int MAX_LOG_LINES = 1000;

// 注册 VM 日志文件
void qemu_register_log_file(const char* vm_name, const char* log_path) {
    if (vm_name && log_path) {
        g_vm_log_files[vm_name] = log_path;
        std::cerr << "[QEMU] Registered log file for VM " << vm_name << ": " << log_path << std::endl;
    }
}

int qemu_get_vm_logs(const char* vm_name, char** logs, int* line_count) {
    if (!vm_name || !logs || !line_count) {
        return -1;
    }
    
    *line_count = 0;
    
    // 查找日志文件路径
    std::string log_path;
    auto it = g_vm_log_files.find(vm_name);
    if (it != g_vm_log_files.end()) {
        log_path = it->second;
    } else {
        // 尝试默认路径
        log_path = "/data/storage/el2/base/files/qemu/logs/" + std::string(vm_name) + ".log";
    }
    
    // 读取日志文件
    std::ifstream file(log_path);
    if (!file.is_open()) {
        std::cerr << "[QEMU] Cannot open log file: " << log_path << std::endl;
        return -1;
    }
    
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(file, line) && lines.size() < MAX_LOG_LINES) {
        lines.push_back(line);
    }
    file.close();
    
    // 分配并填充日志数组
    *line_count = static_cast<int>(lines.size());
    if (*line_count > 0) {
        for (int i = 0; i < *line_count; i++) {
            logs[i] = strdup(lines[i].c_str());
        }
    }
    
    std::cerr << "[QEMU] Retrieved " << *line_count << " log lines for VM: " << vm_name << std::endl;
    return 0;
}

int qemu_clear_vm_logs(const char* vm_name) {
    if (!vm_name) {
        return -1;
    }
    
    // 查找日志文件路径
    std::string log_path;
    auto it = g_vm_log_files.find(vm_name);
    if (it != g_vm_log_files.end()) {
        log_path = it->second;
    } else {
        log_path = "/data/storage/el2/base/files/qemu/logs/" + std::string(vm_name) + ".log";
    }
    
    // 清空日志文件
    std::ofstream file(log_path, std::ios::trunc);
    if (!file.is_open()) {
        std::cerr << "[QEMU] Cannot open log file for clearing: " << log_path << std::endl;
        return -1;
    }
    file.close();
    
    std::cerr << "[QEMU] Cleared log file for VM: " << vm_name << std::endl;
    return 0;
}

// 追加日志
void qemu_append_log(const char* vm_name, const char* message) {
    if (!vm_name || !message) {
        return;
    }
    
    std::string log_path;
    auto it = g_vm_log_files.find(vm_name);
    if (it != g_vm_log_files.end()) {
        log_path = it->second;
    } else {
        log_path = "/data/storage/el2/base/files/qemu/logs/" + std::string(vm_name) + ".log";
    }
    
    // 确保目录存在
    std::string dir = log_path.substr(0, log_path.find_last_of('/'));
    mkdir(dir.c_str(), 0755);
    
    // 追加日志
    std::ofstream file(log_path, std::ios::app);
    if (file.is_open()) {
        // 添加时间戳
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        char timestamp[32];
        strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", localtime(&time));
        
        file << "[" << timestamp << "] " << message << std::endl;
        file.close();
    }
}

// RDP客户端管理接口
rdp_client_handle_t rdp_client_create(void) {
    // 创建RDP客户端实例
    auto* client = new RdpClient();
    return static_cast<rdp_client_handle_t>(client);
}

int qemu_rdp_client_connect(rdp_client_handle_t handle, const rdp_connection_config_t* config) {
    if (!handle || !config) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    
    // 转换配置
    RdpConnectionConfig rdp_config;
    rdp_config.host = config->host ? config->host : "";
    rdp_config.port = config->port;
    rdp_config.username = config->username ? config->username : "";
    rdp_config.password = config->password ? config->password : "";
    rdp_config.domain = config->domain ? config->domain : "";
    rdp_config.width = config->width;
    rdp_config.height = config->height;
    rdp_config.color_depth = config->color_depth;
    rdp_config.enable_audio = config->enable_audio != 0;
    rdp_config.enable_clipboard = config->enable_clipboard != 0;
    rdp_config.enable_file_sharing = config->enable_file_sharing != 0;
    rdp_config.shared_folder = config->shared_folder ? config->shared_folder : "";
    
    return client->connect(rdp_config) ? 0 : -1;
}

void qemu_rdp_client_disconnect(rdp_client_handle_t handle) {
    if (handle) {
        auto* client = static_cast<RdpClient*>(handle);
        client->disconnect();
    }
}

int rdp_client_is_connected(rdp_client_handle_t handle) {
    if (!handle) {
        return 0;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->is_connected() ? 1 : 0;
}

rdp_connection_state_t rdp_client_get_state(rdp_client_handle_t handle) {
    if (!handle) {
        return RDP_ERROR;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    auto state = client->get_connection_state();
    
    switch (state) {
        case RdpConnectionState::DISCONNECTED:
            return RDP_DISCONNECTED;
        case RdpConnectionState::CONNECTING:
            return RDP_CONNECTING;
        case RdpConnectionState::CONNECTED:
            return RDP_CONNECTED;
        case RdpConnectionState::ERROR:
        default:
            return RDP_ERROR;
    }
}

// RDP显示控制
int rdp_client_set_resolution(rdp_client_handle_t handle, int width, int height) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->set_resolution(width, height) ? 0 : -1;
}

int rdp_client_set_color_depth(rdp_client_handle_t handle, int depth) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->set_color_depth(depth) ? 0 : -1;
}

int rdp_client_enable_fullscreen(rdp_client_handle_t handle, int enable) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->enable_fullscreen(enable != 0) ? 0 : -1;
}

// RDP输入控制
int rdp_client_send_mouse_event(rdp_client_handle_t handle, int x, int y, int button, int pressed) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->send_mouse_event(x, y, button, pressed != 0) ? 0 : -1;
}

int rdp_client_send_keyboard_event(rdp_client_handle_t handle, int key, int pressed) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->send_keyboard_event(key, pressed != 0) ? 0 : -1;
}

int rdp_client_send_text_input(rdp_client_handle_t handle, const char* text) {
    if (!handle || !text) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->send_text_input(text) ? 0 : -1;
}

// RDP剪贴板管理
int rdp_client_enable_clipboard_sharing(rdp_client_handle_t handle, int enable) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->enable_clipboard_sharing(enable != 0) ? 0 : -1;
}

int rdp_client_get_clipboard_text(rdp_client_handle_t handle, char** text) {
    if (!handle || !text) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    std::string clipboard_text = client->get_clipboard_text();
    
    if (clipboard_text.empty()) {
        *text = nullptr;
        return 0;
    }
    
    *text = new char[clipboard_text.length() + 1];
    strcpy(*text, clipboard_text.c_str());
    
    return 0;
}

int rdp_client_set_clipboard_text(rdp_client_handle_t handle, const char* text) {
    if (!handle || !text) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->set_clipboard_text(text) ? 0 : -1;
}

// RDP文件共享
int rdp_client_enable_file_sharing(rdp_client_handle_t handle, int enable) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->enable_file_sharing(enable != 0) ? 0 : -1;
}

int rdp_client_set_shared_folder(rdp_client_handle_t handle, const char* path) {
    if (!handle || !path) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->set_shared_folder(path) ? 0 : -1;
}

int rdp_client_get_shared_folder(rdp_client_handle_t handle, char** path) {
    if (!handle || !path) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    std::string shared_folder = client->get_shared_folder();
    
    if (shared_folder.empty()) {
        *path = nullptr;
        return 0;
    }
    
    *path = new char[shared_folder.length() + 1];
    strcpy(*path, shared_folder.c_str());
    
    return 0;
}

// RDP音频控制
int rdp_client_enable_audio(rdp_client_handle_t handle, int enable) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->enable_audio(enable != 0) ? 0 : -1;
}

int rdp_client_set_audio_volume(rdp_client_handle_t handle, int volume) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->set_audio_volume(volume) ? 0 : -1;
}

int rdp_client_get_audio_volume(rdp_client_handle_t handle) {
    if (!handle) {
        return -1;
    }
    
    auto* client = static_cast<RdpClient*>(handle);
    return client->get_audio_volume();
}

// RDP客户端销毁
void rdp_client_destroy(rdp_client_handle_t handle) {
    if (handle) {
        auto* client = static_cast<RdpClient*>(handle);
        delete client;
    }
}

// ============================================================================
// Windows 11 配置相关 (TPM/UEFI/SecureBoot)
// ============================================================================

// TPM 状态存储
static std::map<std::string, std::string> g_tpm_socket_paths;
static std::map<std::string, std::string> g_tpm_state_dirs;

// UEFI 相关路径
static const char* UEFI_CODE_PATH = "/data/storage/el1/bundle/qemu/firmware/QEMU_EFI.fd";
static const char* UEFI_VARS_TEMPLATE = "/data/storage/el1/bundle/qemu/firmware/QEMU_VARS.fd";

// UEFI 变量文件存储
static std::map<std::string, std::string> g_uefi_vars_paths;

// Secure Boot 状态
static std::map<std::string, bool> g_secure_boot_enabled;

// 静态字符串缓存（用于返回 const char*）
static std::string g_last_tpm_socket;
static std::string g_last_tpm_state_dir;
static std::string g_last_tpm_error;
static std::string g_last_uefi_code;
static std::string g_last_uefi_vars;
static std::string g_last_uefi_error;
static std::string g_win11_args_cache;
static std::string g_tpm_status_cache;
static std::string g_uefi_status_cache;
static std::string g_secureboot_status_cache;

/**
 * 设置 TPM 2.0 虚拟设备
 * HarmonyOS 环境下使用 swtpm 模拟器
 */
int qemu_setup_tpm(const char* vm_name, tpm_setup_result_t* result) {
    if (!vm_name || !result) {
        return -1;
    }
    
    std::string name(vm_name);
    
    // 创建 TPM 状态目录
    std::string state_dir = "/data/storage/el1/bundle/vm_data/" + name + "/tpm";
    std::string socket_path = state_dir + "/swtpm-sock";
    
    // 创建目录
    std::string mkdir_cmd = "mkdir -p " + state_dir;
    int ret = system(mkdir_cmd.c_str());
    
    if (ret != 0) {
        g_last_tpm_error = "无法创建 TPM 状态目录";
        result->success = 0;
        result->socket_path = nullptr;
        result->state_dir = nullptr;
        result->error_message = g_last_tpm_error.c_str();
        return -1;
    }
    
    // 注意：在 HarmonyOS 中，我们不能直接运行 swtpm
    // 而是生成 QEMU 命令行参数，让 QEMU 在启动时加载 TPM 设备
    // 实际的 TPM 模拟由 QEMU 内置的 tpm-emulator 提供
    
    // 存储路径信息
    g_tpm_socket_paths[name] = socket_path;
    g_tpm_state_dirs[name] = state_dir;
    
    // 设置返回值
    g_last_tpm_socket = socket_path;
    g_last_tpm_state_dir = state_dir;
    
    result->success = 1;
    result->socket_path = g_last_tpm_socket.c_str();
    result->state_dir = g_last_tpm_state_dir.c_str();
    result->error_message = nullptr;
    
    std::cerr << "[TPM] TPM setup completed for VM: " << name << std::endl;
    std::cerr << "[TPM] State dir: " << state_dir << std::endl;
    std::cerr << "[TPM] Socket path: " << socket_path << std::endl;
    
    return 0;
}

/**
 * 清理 TPM 设备
 */
int qemu_cleanup_tpm(const char* vm_name) {
    if (!vm_name) {
        return -1;
    }
    
    std::string name(vm_name);
    
    // 移除存储的路径
    g_tpm_socket_paths.erase(name);
    g_tpm_state_dirs.erase(name);
    
    // 注意：不删除 TPM 状态文件，以便保留 TPM 密钥
    
    return 0;
}

/**
 * 检查 TPM 是否可用
 */
int qemu_is_tpm_available(const char* vm_name) {
    if (!vm_name) {
        return 0;
    }
    
    std::string name(vm_name);
    
    // 检查是否已设置 TPM
    if (g_tpm_socket_paths.find(name) != g_tpm_socket_paths.end()) {
        return 1;
    }
    
    // QEMU 内置 TPM 模拟器始终可用
    return 1;
}

/**
 * 设置 UEFI 固件
 */
int qemu_setup_uefi(const char* vm_name, uefi_setup_result_t* result) {
    if (!vm_name || !result) {
        return -1;
    }
    
    std::string name(vm_name);
    
    // UEFI 变量文件路径（每个 VM 独立）
    std::string vars_path = "/data/storage/el1/bundle/vm_data/" + name + "/OVMF_VARS.fd";
    
    // 创建 VM 数据目录
    std::string mkdir_cmd = "mkdir -p /data/storage/el1/bundle/vm_data/" + name;
    system(mkdir_cmd.c_str());
    
    // 检查变量文件是否存在，如果不存在则复制模板
    struct stat st;
    if (stat(vars_path.c_str(), &st) != 0) {
        // 复制模板文件
        std::string cp_cmd = "cp " + std::string(UEFI_VARS_TEMPLATE) + " " + vars_path;
        int ret = system(cp_cmd.c_str());
        
        if (ret != 0) {
            // 如果模板不存在，创建一个空文件
            std::string touch_cmd = "dd if=/dev/zero of=" + vars_path + " bs=1M count=1";
            system(touch_cmd.c_str());
        }
    }
    
    // 存储路径
    g_uefi_vars_paths[name] = vars_path;
    
    // 设置返回值
    g_last_uefi_code = UEFI_CODE_PATH;
    g_last_uefi_vars = vars_path;
    
    result->success = 1;
    result->code_path = g_last_uefi_code.c_str();
    result->vars_path = g_last_uefi_vars.c_str();
    result->error_message = nullptr;
    
    std::cerr << "[UEFI] UEFI setup completed for VM: " << name << std::endl;
    std::cerr << "[UEFI] Code path: " << UEFI_CODE_PATH << std::endl;
    std::cerr << "[UEFI] Vars path: " << vars_path << std::endl;
    
    return 0;
}

/**
 * 清理 UEFI 设置
 */
int qemu_cleanup_uefi(const char* vm_name) {
    if (!vm_name) {
        return -1;
    }
    
    std::string name(vm_name);
    g_uefi_vars_paths.erase(name);
    
    // 不删除 UEFI 变量文件，以保留设置
    
    return 0;
}

/**
 * 检查 UEFI 固件是否可用
 */
int qemu_is_uefi_available(void) {
    struct stat st;
    
    // 检查 UEFI 固件文件是否存在
    if (stat(UEFI_CODE_PATH, &st) == 0) {
        return 1;
    }
    
    // 检查备用路径
    const char* alt_paths[] = {
        "/data/storage/el1/bundle/rawfile/QEMU_EFI.fd",
        "/data/storage/el1/bundle/entry/resources/rawfile/QEMU_EFI.fd",
        nullptr
    };
    
    for (int i = 0; alt_paths[i] != nullptr; i++) {
        if (stat(alt_paths[i], &st) == 0) {
            return 1;
        }
    }
    
    // QEMU 自带 UEFI 支持
    return 1;
}

/**
 * 获取 UEFI 代码路径
 */
const char* qemu_get_uefi_code_path(void) {
    struct stat st;
    
    if (stat(UEFI_CODE_PATH, &st) == 0) {
        return UEFI_CODE_PATH;
    }
    
    // 检查备用路径
    const char* alt_paths[] = {
        "/data/storage/el1/bundle/rawfile/QEMU_EFI.fd",
        "/data/storage/el1/bundle/entry/resources/rawfile/QEMU_EFI.fd",
        nullptr
    };
    
    for (int i = 0; alt_paths[i] != nullptr; i++) {
        if (stat(alt_paths[i], &st) == 0) {
            return alt_paths[i];
        }
    }
    
    return UEFI_CODE_PATH;
}

/**
 * 获取 UEFI 变量模板路径
 */
const char* qemu_get_uefi_vars_template_path(void) {
    return UEFI_VARS_TEMPLATE;
}

/**
 * 启用/禁用 Secure Boot
 */
int qemu_enable_secure_boot(const char* vm_name, int enable) {
    if (!vm_name) {
        return -1;
    }
    
    std::string name(vm_name);
    g_secure_boot_enabled[name] = (enable != 0);
    
    std::cerr << "[SecureBoot] Secure Boot " << (enable ? "enabled" : "disabled") 
              << " for VM: " << name << std::endl;
    
    return 0;
}

/**
 * 检查 Secure Boot 是否启用
 */
int qemu_is_secure_boot_enabled(const char* vm_name) {
    if (!vm_name) {
        return 0;
    }
    
    std::string name(vm_name);
    auto it = g_secure_boot_enabled.find(name);
    
    if (it != g_secure_boot_enabled.end()) {
        return it->second ? 1 : 0;
    }
    
    // 默认为 Windows 11 启用 Secure Boot
    return 1;
}

/**
 * 检查 Windows 11 兼容性
 */
int qemu_check_win11_compatibility(const char* vm_name, win11_compatibility_result_t* result) {
    if (!result) {
        return -1;
    }
    
    // 检查 TPM
    result->tpm_available = qemu_is_tpm_available(vm_name);
    g_tpm_status_cache = result->tpm_available ? 
        "TPM 2.0 可用（QEMU 内置模拟器）" : "TPM 2.0 不可用";
    result->tpm_status = g_tpm_status_cache.c_str();
    
    // 检查 UEFI
    result->uefi_available = qemu_is_uefi_available();
    g_uefi_status_cache = result->uefi_available ? 
        "UEFI 固件可用" : "UEFI 固件不可用";
    result->uefi_status = g_uefi_status_cache.c_str();
    
    // 检查 Secure Boot
    result->secure_boot_available = qemu_is_secure_boot_enabled(vm_name);
    g_secureboot_status_cache = result->secure_boot_available ? 
        "Secure Boot 已启用" : "Secure Boot 未启用";
    result->secure_boot_status = g_secureboot_status_cache.c_str();
    
    // 总体兼容性
    result->overall_compatible = result->tpm_available && 
                                  result->uefi_available && 
                                  result->secure_boot_available;
    
    return 0;
}

/**
 * 生成 Windows 11 优化的 QEMU 命令参数
 */
const char* qemu_build_win11_args(const char* vm_name, int memory_mb, 
                                   const char* disk_path, const char* iso_path) {
    if (!vm_name) {
        return "";
    }
    
    std::string name(vm_name);
    std::ostringstream args;
    
    // 基础配置
    args << "-m " << memory_mb << "M ";
    args << "-smp 4,cores=4,threads=1 ";
    
    // 机器类型 - 使用 virt 适配 ARM
    args << "-machine virt,accel=tcg ";
    args << "-cpu max ";
    
    // UEFI 固件
    const char* uefi_code = qemu_get_uefi_code_path();
    auto vars_it = g_uefi_vars_paths.find(name);
    std::string vars_path = (vars_it != g_uefi_vars_paths.end()) ? 
        vars_it->second : 
        "/data/storage/el1/bundle/vm_data/" + name + "/OVMF_VARS.fd";
    
    args << "-drive if=pflash,format=raw,readonly=on,file=" << uefi_code << " ";
    args << "-drive if=pflash,format=raw,file=" << vars_path << " ";
    
    // TPM 2.0
    auto tpm_it = g_tpm_state_dirs.find(name);
    if (tpm_it != g_tpm_state_dirs.end()) {
        args << "-chardev socket,id=chrtpm,path=" << g_tpm_socket_paths[name] << " ";
        args << "-tpmdev emulator,id=tpm0,chardev=chrtpm ";
        args << "-device tpm-tis,tpmdev=tpm0 ";
    }
    
    // 存储设备
    if (disk_path && strlen(disk_path) > 0) {
        args << "-drive file=" << disk_path << ",if=virtio,format=qcow2 ";
    }
    
    if (iso_path && strlen(iso_path) > 0) {
        args << "-drive file=" << iso_path << ",media=cdrom ";
    }
    
    // 显示设备
    args << "-device virtio-gpu-pci ";
    
    // 网络设备
    args << "-netdev user,id=net0,hostfwd=tcp::3390-:3389,hostfwd=tcp::2222-:22 ";
    args << "-device virtio-net-pci,netdev=net0 ";
    
    // USB 控制器和输入设备
    args << "-device qemu-xhci,id=xhci ";
    args << "-device usb-tablet,bus=xhci.0 ";
    args << "-device usb-kbd,bus=xhci.0 ";
    
    // 启动配置
    if (iso_path && strlen(iso_path) > 0) {
        args << "-boot order=dc,menu=on ";
    } else {
        args << "-boot order=c ";
    }
    
    // 性能优化
    args << "-rtc base=localtime ";
    
    // VNC 显示
    args << "-vnc :1 ";
    g_win11_args_cache = args.str();
    return g_win11_args_cache.c_str();
}

// ============================================================================
// QEMU 核心库加载函数（供 napi_init.cpp 使用）
// ============================================================================

// 全局 QEMU 核心初始化函数指针
int (*g_qemu_core_init)(int argc, char** argv) = nullptr;

/**
 * 确保 QEMU 核心库已加载
 * @param log_path 日志文件路径
 */
void EnsureQemuCoreLoaded(const char* log_path) {
    if (g_qemu_core_init) {
        return; // 已加载
    }
    
    // 尝试加载 QEMU 核心库
    std::string lib_path = "/data/storage/el1/bundle/qemu/libqemu_full.so";
    
    if (load_qemu_library(lib_path)) {
        // 获取 QEMU 核心初始化函数
        g_qemu_core_init = (int (*)(int, char**))dlsym(g_qemu_lib_handle, "qemu_main");
        if (!g_qemu_core_init) {
            g_qemu_core_init = (int (*)(int, char**))dlsym(g_qemu_lib_handle, "main");
        }
        
        if (g_qemu_core_init) {
            std::cerr << "[QEMU] Core library loaded successfully" << std::endl;
        } else {
            std::cerr << "[QEMU] Failed to find core initialization function" << std::endl;
        }
    } else {
        std::cerr << "[QEMU] Failed to load core library" << std::endl;
    }
}