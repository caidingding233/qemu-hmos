/**
 * Compatibility layer for musl/HarmonyOS
 * 
 * musl libc 不支持 pthread_cancel，这里提供兼容实现
 * ICU 使用系统库 libicu.so，不需要 stub
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <pthread.h>
#include <unistd.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * pthread_cancel 兼容实现
 * 
 * musl 不支持 pthread_cancel，这是一个不完美的替代方案
 * 
 * 重要限制：
 * 1. 真正的 pthread_cancel 会在"取消点"自动终止线程
 * 2. 我们的实现只是发送信号，无法强制终止
 * 3. 如果目标线程不处理信号，可能导致问题
 * 
 * FreeRDP 影响：
 * - TerminateThread 功能可能不完全工作
 * - 大部分正常使用应该没问题
 * ============================================================ */

#if defined(__MUSL__) || defined(__OHOS__) || defined(__HARMONYOS__)

/* 全局取消标志 - 线程可以检查这个来决定是否退出 */
static volatile sig_atomic_t g_cancel_requested = 0;

/* SIGUSR1 信号处理器 - 设置取消标志 */
static void cancel_signal_handler(int sig) {
    (void)sig;
    g_cancel_requested = 1;
    /* 
     * 注意：这个处理器在收到信号的线程上下文中执行
     * 但它只设置一个全局标志，实际退出需要线程自己检查
     */
}

/* 初始化信号处理器
 * 
 * 注意：不再使用 __attribute__((constructor)) 自动安装，
 * 因为在 HarmonyOS 上可能与系统信号处理冲突导致崩溃。
 * 改为在首次使用 pthread_cancel 时惰性安装。
 */
static int g_signal_handler_installed = 0;

static void ensure_cancel_handler_installed(void) {
    if (g_signal_handler_installed) return;
    
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = cancel_signal_handler;
    sa.sa_flags = 0;
    sigemptyset(&sa.sa_mask);
    
    if (sigaction(SIGUSR1, &sa, NULL) == 0) {
        g_signal_handler_installed = 1;
    } else {
        fprintf(stderr, "[COMPAT] Warning: Failed to install SIGUSR1 handler\n");
    }
}

/* 
 * pthread_cancel 兼容实现
 * 
 * 工作流程：
 * 1. 设置全局取消标志
 * 2. 发送 SIGUSR1 信号给目标线程
 * 3. 目标线程的信号处理器会被调用
 * 4. 如果线程在阻塞的系统调用中，会被中断（返回 EINTR）
 * 
 * 局限：
 * - 不能强制终止线程
 * - 依赖线程自己检查取消状态或响应 EINTR
 */
int pthread_cancel(pthread_t thread) {
    /* 确保信号处理器已安装 */
    ensure_cancel_handler_installed();
    
    /* 设置取消标志 */
    g_cancel_requested = 1;
    
    /* 发送信号 */
    int ret = pthread_kill(thread, SIGUSR1);
    
    if (ret == ESRCH) {
        /* 线程已经不存在，视为成功 */
        return 0;
    }
    
    if (ret != 0) {
        fprintf(stderr, "[COMPAT] pthread_cancel: pthread_kill returned %d\n", ret);
    }
    
    return ret;
}

/* 检查是否有取消请求（线程可以调用这个来检查） */
int pthread_cancel_requested(void) {
    return g_cancel_requested;
}

/* 清除取消标志 */
void pthread_cancel_clear(void) {
    g_cancel_requested = 0;
}

/* 
 * pthread_setcancelstate - 空实现
 * 真正的实现会启用/禁用取消功能
 */
#ifndef PTHREAD_CANCEL_ENABLE
#define PTHREAD_CANCEL_ENABLE 0
#define PTHREAD_CANCEL_DISABLE 1
#define PTHREAD_CANCEL_DEFERRED 0
#define PTHREAD_CANCEL_ASYNCHRONOUS 1
#endif

int pthread_setcancelstate(int state, int *oldstate) {
    (void)state;
    if (oldstate) *oldstate = PTHREAD_CANCEL_ENABLE;
    return 0;
}

int pthread_setcanceltype(int type, int *oldtype) {
    (void)type;
    if (oldtype) *oldtype = PTHREAD_CANCEL_DEFERRED;
    return 0;
}

/* 
 * pthread_testcancel - 检查取消点
 * 真正的实现会在这里检查并退出线程
 * 我们的实现只能检查标志
 */
void pthread_testcancel(void) {
    if (g_cancel_requested) {
        /* 
         * 理想情况下应该调用 pthread_exit(PTHREAD_CANCELED)
         * 但这可能导致资源泄漏，因为不会执行清理处理器
         * 所以我们只打印警告，让调用者自己决定
         */
        fprintf(stderr, "[COMPAT] pthread_testcancel: cancel requested, thread should exit\n");
    }
}

#endif /* __MUSL__ || __OHOS__ || __HARMONYOS__ */

/* ============================================================
 * ICU Unicode 转换函数
 * 
 * 注意：ICU 函数（ucnv_convert, u_errorName）现在使用系统库 libicu.so
 * 这些函数不再需要 stub 实现，已通过 -licu 链接到系统库
 * ============================================================ */

#ifdef __cplusplus
}
#endif
