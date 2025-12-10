/**
 * RDP 连接管理器
 * 
 * 功能：
 * - 监控连接状态
 * - 检测超时
 * - 提供强制关闭选项
 * - 引导用户处理卡死情况
 */

import qemuModule from 'libqemu_hmos.so'

export type RdpStatus = 'disconnected' | 'connecting' | 'connected' | 'timeout' | 'cancelling'

export interface RdpConnectionInfo {
  status: RdpStatus
  timeoutSeconds: number
  isStuck: boolean
  message: string
}

export class RdpConnectionManager {
  private checkInterval: number = -1
  private onStatusChange?: (info: RdpConnectionInfo) => void
  private timeoutThreshold: number = 30  // 默认30秒超时

  /**
   * 设置超时阈值
   */
  setTimeoutThreshold(seconds: number) {
    this.timeoutThreshold = seconds
    if (qemuModule.rdpSetTimeout) {
      qemuModule.rdpSetTimeout(seconds)
    }
  }

  /**
   * 获取当前连接状态
   */
  getStatus(): RdpConnectionInfo {
    let status: RdpStatus = 'disconnected'
    let timeoutSeconds = 0
    let isStuck = false
    let message = ''

    try {
      // 获取状态字符串
      if (qemuModule.rdpGetStatusString) {
        const statusStr = qemuModule.rdpGetStatusString()
        status = statusStr as RdpStatus
      }

      // 检查超时
      if (qemuModule.rdpCheckTimeout) {
        timeoutSeconds = qemuModule.rdpCheckTimeout()
        if (timeoutSeconds > 0) {
          status = 'timeout'
          isStuck = true
        }
      }

      // 生成用户友好的消息
      switch (status) {
        case 'disconnected':
          message = '未连接'
          break
        case 'connecting':
          message = '正在连接...'
          break
        case 'connected':
          message = '已连接'
          break
        case 'timeout':
          message = `连接超时（已等待 ${timeoutSeconds} 秒）`
          break
        case 'cancelling':
          message = '正在取消...'
          break
      }
    } catch (e) {
      console.error('[RdpConnectionManager] getStatus error:', e)
      message = '状态获取失败'
    }

    return { status, timeoutSeconds, isStuck, message }
  }

  /**
   * 开始监控连接状态
   */
  startMonitoring(callback: (info: RdpConnectionInfo) => void) {
    this.onStatusChange = callback
    
    // 每2秒检查一次
    this.checkInterval = setInterval(() => {
      const info = this.getStatus()
      if (this.onStatusChange) {
        this.onStatusChange(info)
      }
    }, 2000)
  }

  /**
   * 停止监控
   */
  stopMonitoring() {
    if (this.checkInterval !== -1) {
      clearInterval(this.checkInterval)
      this.checkInterval = -1
    }
  }

  /**
   * 请求取消连接（温和方式）
   */
  requestCancel(): boolean {
    try {
      if (qemuModule.rdpRequestCancel) {
        qemuModule.rdpRequestCancel()
        return true
      }
    } catch (e) {
      console.error('[RdpConnectionManager] requestCancel error:', e)
    }
    return false
  }

  /**
   * 强制清理连接（用于卡死情况）
   * 
   * 注意：这会强制重置状态，即使后台线程还在运行
   * 可能会有少量资源泄漏，但能让用户继续使用应用
   */
  forceCleanup(): boolean {
    try {
      if (qemuModule.rdpForceCleanup) {
        qemuModule.rdpForceCleanup()
        return true
      }
    } catch (e) {
      console.error('[RdpConnectionManager] forceCleanup error:', e)
    }
    return false
  }

  /**
   * 获取用于显示给用户的建议操作
   */
  getSuggestedActions(info: RdpConnectionInfo): SuggestedAction[] {
    const actions: SuggestedAction[] = []

    if (info.status === 'timeout' || info.isStuck) {
      actions.push({
        label: '继续等待',
        description: '等待连接完成（可能需要更长时间）',
        action: 'wait',
        danger: false
      })
      actions.push({
        label: '取消连接',
        description: '尝试正常取消连接',
        action: 'cancel',
        danger: false
      })
      actions.push({
        label: '强制关闭',
        description: '强制清理连接（推荐在卡死时使用）',
        action: 'force',
        danger: true
      })
    } else if (info.status === 'connecting') {
      actions.push({
        label: '取消',
        description: '取消正在进行的连接',
        action: 'cancel',
        danger: false
      })
    } else if (info.status === 'connected') {
      actions.push({
        label: '断开连接',
        description: '正常断开 RDP 连接',
        action: 'disconnect',
        danger: false
      })
    }

    return actions
  }
}

export interface SuggestedAction {
  label: string
  description: string
  action: 'wait' | 'cancel' | 'force' | 'disconnect'
  danger: boolean
}

// 单例实例
export const rdpManager = new RdpConnectionManager()
