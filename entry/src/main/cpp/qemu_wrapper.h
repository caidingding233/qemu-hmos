#ifndef QEMU_WRAPPER_H
#define QEMU_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

// QEMU 虚拟机状态
typedef enum {
    QEMU_VM_STOPPED = 0,
    QEMU_VM_RUNNING = 1,
    QEMU_VM_PAUSED = 2,
    QEMU_VM_ERROR = -1
} qemu_vm_state_t;

// RDP连接状态
typedef enum {
    RDP_DISCONNECTED = 0,
    RDP_CONNECTING = 1,
    RDP_CONNECTED = 2,
    RDP_ERROR = -1
} rdp_connection_state_t;

// RDP连接配置
typedef struct {
    const char* host;                    // 主机地址
    int port;                           // 端口号
    const char* username;               // 用户名
    const char* password;               // 密码
    const char* domain;                 // 域名
    int width;                          // 显示宽度
    int height;                         // 显示高度
    int color_depth;                    // 颜色深度
    int enable_audio;                   // 是否启用音频
    int enable_clipboard;               // 是否启用剪贴板共享
    int enable_file_sharing;            // 是否启用文件共享
    const char* shared_folder;          // 共享文件夹路径
} rdp_connection_config_t;

// QEMU 虚拟机配置
typedef struct {
    const char* name;                    // 虚拟机名称
    const char* arch_type;               // 架构类型：aarch64, x86_64, i386
    const char* machine_type;            // 机器类型，如 "virt"
    const char* cpu_type;                // CPU 类型，如 "cortex-a57"
    int memory_mb;                       // 内存大小（MB）
    int cpu_count;                       // CPU核心数
    const char* disk_path;               // 硬盘文件路径
    int disk_size_gb;                    // 硬盘大小（GB）
    const char* iso_path;                // ISO镜像路径
    const char* efi_firmware;            // EFI固件路径
    const char* shared_dir;              // 宿主共享目录
    int vnc_port;                        // VNC端口
    int rdp_port;                        // RDP端口
    const char* network_mode;            // 网络模式：user, bridge, none
    const char* accel_mode;              // 加速模式：kvm, tcg, hvf
    const char* display_mode;            // 显示模式：vnc, sdl, gtk, none
} qemu_vm_config_t;

// QEMU 虚拟机实例句柄
typedef void* qemu_vm_handle_t;

// RDP客户端句柄
typedef void* rdp_client_handle_t;

// QEMU 核心接口
int qemu_init(void);
void qemu_cleanup(void);

// 虚拟机管理接口
qemu_vm_handle_t qemu_vm_create(const qemu_vm_config_t* config);
int qemu_vm_start(qemu_vm_handle_t handle);
int qemu_vm_stop(qemu_vm_handle_t handle);
int qemu_vm_pause(qemu_vm_handle_t handle);
int qemu_vm_resume(qemu_vm_handle_t handle);
qemu_vm_state_t qemu_vm_get_state(qemu_vm_handle_t handle);
void qemu_vm_destroy(qemu_vm_handle_t handle);

// 硬盘管理
int qemu_create_disk(const char* path, int size_gb, const char* format);
int qemu_resize_disk(const char* path, int new_size_gb);

// 网络管理
int qemu_setup_network(const char* vm_name, const char* mode, int host_port, int guest_port);
int qemu_forward_port(const char* vm_name, int host_port, int guest_port);

// 显示管理
int qemu_start_vnc_server(const char* vm_name, int port);
int qemu_start_rdp_server(const char* vm_name, int port);

// RDP客户端管理接口
rdp_client_handle_t rdp_client_create(void);
// 注意：函数名添加 qemu_ 前缀以避免与 FreeRDP 库的同名函数冲突
int qemu_rdp_client_connect(rdp_client_handle_t handle, const rdp_connection_config_t* config);
void qemu_rdp_client_disconnect(rdp_client_handle_t handle);
int rdp_client_is_connected(rdp_client_handle_t handle);
rdp_connection_state_t rdp_client_get_state(rdp_client_handle_t handle);

// RDP 超时检测和强制清理接口
int rdp_check_timeout(void);           // 检查是否超时，返回超时秒数，0表示未超时
void rdp_set_timeout(int seconds);     // 设置超时时间（秒）
void rdp_request_cancel(void);         // 请求取消连接
int rdp_is_cancel_requested(void);     // 检查是否已请求取消
void rdp_force_cleanup(void);          // 强制清理（即使线程没退出）
const char* rdp_get_status_string(void); // 获取状态字符串

// RDP显示控制
int rdp_client_set_resolution(rdp_client_handle_t handle, int width, int height);
int rdp_client_set_color_depth(rdp_client_handle_t handle, int depth);
int rdp_client_enable_fullscreen(rdp_client_handle_t handle, int enable);

// RDP输入控制
int rdp_client_send_mouse_event(rdp_client_handle_t handle, int x, int y, int button, int pressed);
int rdp_client_send_keyboard_event(rdp_client_handle_t handle, int key, int pressed);
int rdp_client_send_text_input(rdp_client_handle_t handle, const char* text);

// RDP剪贴板管理
int rdp_client_enable_clipboard_sharing(rdp_client_handle_t handle, int enable);
int rdp_client_get_clipboard_text(rdp_client_handle_t handle, char** text);
int rdp_client_set_clipboard_text(rdp_client_handle_t handle, const char* text);

// RDP文件共享
int rdp_client_enable_file_sharing(rdp_client_handle_t handle, int enable);
int rdp_client_set_shared_folder(rdp_client_handle_t handle, const char* path);
int rdp_client_get_shared_folder(rdp_client_handle_t handle, char** path);

// RDP音频控制
int rdp_client_enable_audio(rdp_client_handle_t handle, int enable);
int rdp_client_set_audio_volume(rdp_client_handle_t handle, int volume);
int rdp_client_get_audio_volume(rdp_client_handle_t handle);

// RDP客户端销毁
void rdp_client_destroy(rdp_client_handle_t handle);

// 快照管理
int qemu_create_snapshot(const char* vm_name, const char* snapshot_name);
int qemu_restore_snapshot(const char* vm_name, const char* snapshot_name);
int qemu_list_snapshots(const char* vm_name, char** snapshot_list, int* count);

// 文件共享
int qemu_mount_shared_dir(const char* vm_name, const char* host_path, const char* guest_path);

// 获取 QEMU 版本信息
const char* qemu_get_version(void);

// 检测系统能力
int qemu_detect_kvm_support(void);
int qemu_detect_hvf_support(void);
int qemu_detect_tcg_support(void);

// KVM 权限检测（HarmonyOS 专用）
const char* qemu_get_kvm_unavailable_reason(int is_release_build);
int qemu_is_pc_device(void);

// 设备信息设置（从 ArkTS 层调用）
// device_type: 0=unknown, 1=phone, 2=tablet, 3=2in1, 4=pc
void qemu_set_device_info(int device_type, const char* model);

// JIT 权限（ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY）
void qemu_set_jit_permission(int has_permission);
int qemu_has_jit_permission(void);
const char* qemu_get_jit_permission_info(int is_release_build);

// 日志管理
int qemu_get_vm_logs(const char* vm_name, char** logs, int* line_count);
int qemu_clear_vm_logs(const char* vm_name);
void qemu_append_log(const char* vm_name, const char* message);
void qemu_register_log_file(const char* vm_name, const char* log_path);

// Monitor 管理
void qemu_register_monitor(const char* vm_name, const char* socket_path);

// 共享目录管理
int qemu_get_shared_dirs(const char* vm_name, char*** dirs, int* count);

// 删除快照
int qemu_delete_snapshot(const char* vm_name, const char* snapshot_name);

// Windows 11 配置相关 (TPM/UEFI/SecureBoot)
// TPM 设置结果
typedef struct {
    int success;
    const char* socket_path;
    const char* state_dir;
    const char* error_message;
} tpm_setup_result_t;

// UEFI 设置结果
typedef struct {
    int success;
    const char* code_path;
    const char* vars_path;
    const char* error_message;
} uefi_setup_result_t;

// Windows 11 兼容性检查结果
typedef struct {
    int tpm_available;
    int uefi_available;
    int secure_boot_available;
    int overall_compatible;
    const char* tpm_status;
    const char* uefi_status;
    const char* secure_boot_status;
} win11_compatibility_result_t;

// TPM 管理
int qemu_setup_tpm(const char* vm_name, tpm_setup_result_t* result);
int qemu_cleanup_tpm(const char* vm_name);
int qemu_is_tpm_available(const char* vm_name);

// UEFI 管理
int qemu_setup_uefi(const char* vm_name, uefi_setup_result_t* result);
int qemu_cleanup_uefi(const char* vm_name);
int qemu_is_uefi_available(void);
const char* qemu_get_uefi_code_path(void);
const char* qemu_get_uefi_vars_template_path(void);

// Secure Boot 管理
int qemu_enable_secure_boot(const char* vm_name, int enable);
int qemu_is_secure_boot_enabled(const char* vm_name);

// Windows 11 兼容性检查
int qemu_check_win11_compatibility(const char* vm_name, win11_compatibility_result_t* result);

// 生成 Windows 11 优化的 QEMU 命令参数
const char* qemu_build_win11_args(const char* vm_name, int memory_mb, const char* disk_path, const char* iso_path);
// QEMU 核心库加载函数
extern "C" {
    void EnsureQemuCoreLoaded(const char* log_path);
    extern int (*g_qemu_core_init)(int argc, char** argv);
}

#ifdef __cplusplus
}
#endif

#endif // QEMU_WRAPPER_H