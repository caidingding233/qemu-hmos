import hilog from '@ohos.hilog'
import qemu from 'qemu_hmos'
import { VncFrame, QemuAPI } from '../types/qemu'

// 检查 qemu 是否包含 VNC 方法
function hasVncMethods(obj: QemuAPI): boolean {
  const api = obj as QemuAPI
  return api.vncAvailable !== undefined &&
    api.vncCreate !== undefined &&
    api.vncConnect !== undefined &&
    api.vncDisconnect !== undefined &&
    api.vncGetFrame !== undefined;
}

function hasVncInputMethods(obj: QemuAPI): boolean {
  const api = obj as QemuAPI
  return api.vncSendPointer !== undefined && api.vncSendKey !== undefined
}

// 辅助函数：安全调用 VNC 方法（无参数）
function callVncMethod0<T>(methodName: string): T | null {
  try {
    const api = qemu as QemuAPI
    if (methodName === 'vncAvailable' && api.vncAvailable !== undefined) {
      return api.vncAvailable() as T
    }
    if (methodName === 'vncCreate' && api.vncCreate !== undefined) {
      return api.vncCreate() as T
    }
    return null
  } catch (e) {
    hilog.error(0x0000, 'VNC_CLIENT', `调用 ${methodName} 失败`)
    return null
  }
}

// 辅助函数：安全调用 VNC 方法（1个参数）
function callVncMethod1<T>(methodName: string, arg1: number): T | null {
  try {
    const api = qemu as QemuAPI
    if (methodName === 'vncDisconnect' && api.vncDisconnect !== undefined) {
      api.vncDisconnect(arg1)
      return null as T
    }
    if (methodName === 'vncGetFrame' && api.vncGetFrame !== undefined) {
      return api.vncGetFrame(arg1) as T
    }
    return null
  } catch (e) {
    hilog.error(0x0000, 'VNC_CLIENT', `调用 ${methodName} 失败`)
    return null
  }
}

// 辅助函数：安全调用 VNC 方法（3个参数）
function callVncMethod3<T>(methodName: string, arg1: number, arg2: string, arg3: number): T | null {
  try {
    const api = qemu as QemuAPI
    if (methodName === 'vncConnect' && api.vncConnect !== undefined) {
      return api.vncConnect(arg1, arg2, arg3) as T
    }
    return null
  } catch (e) {
    hilog.error(0x0000, 'VNC_CLIENT', `调用 ${methodName} 失败`)
    return null
  }
}

export interface VNCNativeClientApi {
  isAvailable(): boolean
  create(): boolean
  connect(host: string, port: number): Promise<boolean>
  disconnect(): void
  getFrame(): VncFrame | null
  sendPointer(x: number, y: number, buttonMask: number): boolean
  sendKey(keysym: number, down: boolean): boolean
}

class VNCNativeClient implements VNCNativeClientApi {
  private sessionId: number | null = null
  private host: string = '127.0.0.1'
  private port: number = 5901
  private lastFrameLogMs: number = 0

  isAvailable(): boolean {
    if (hasVncMethods(qemu)) {
      const result = callVncMethod0<boolean>('vncAvailable')
      if (result !== null) {
        hilog.info(0x0000, 'VNC_CLIENT', `VNC可用性检查: ${result}`)
        return result
      }
    }
    hilog.warn(0x0000, 'VNC_CLIENT', 'VNC功能不可用（vncAvailable方法不存在）')
    return false
  }

  create(): boolean {
    if (hasVncMethods(qemu)) {
      const sessionId = callVncMethod0<number>('vncCreate')
      if (sessionId !== null && typeof sessionId === 'number') {
        this.sessionId = sessionId
        const success = sessionId > 0
        hilog.info(0x0000, 'VNC_CLIENT', `VNC会话创建: ${success ? '成功' : '失败'}, ID: ${this.sessionId}`)
        return success
      }
    }
      hilog.error(0x0000, 'VNC_CLIENT', 'vncCreate函数不可用')
      return false
  }

  async connect(host: string, port: number): Promise<boolean> {
    this.host = host; this.port = port
    hilog.info(0x0000, 'VNC_CLIENT', `尝试连接VNC: ${host}:${port}`)

    if (this.sessionId == null) {
      hilog.info(0x0000, 'VNC_CLIENT', '没有现有会话，创建新会话')
      if (!this.create()) {
        hilog.error(0x0000, 'VNC_CLIENT', '无法创建VNC会话')
        return false
      }
    }

    if (hasVncMethods(qemu) && this.sessionId !== null) {
      const result = callVncMethod3<boolean>('vncConnect', this.sessionId, host, port)
      if (result !== null) {
        hilog.info(0x0000, 'VNC_CLIENT', `VNC连接结果: ${result ? '成功' : '失败'}`)
        return result
      }
    }
      hilog.error(0x0000, 'VNC_CLIENT', 'vncConnect函数不可用')
      return false
  }

  disconnect(): void {
    if (this.sessionId == null) {
      hilog.info(0x0000, 'VNC_CLIENT', '没有活跃会话，无需断开')
      return
    }
    if (hasVncMethods(qemu)) {
      callVncMethod1<void>('vncDisconnect', this.sessionId)
      hilog.info(0x0000, 'VNC_CLIENT', `VNC会话断开: ID ${this.sessionId}`)
    } else {
      hilog.error(0x0000, 'VNC_CLIENT', 'vncDisconnect函数不可用')
    }
    this.sessionId = null
  }

  getFrame(): VncFrame | null {
    if (this.sessionId == null) {
      hilog.warn(0x0000, 'VNC_CLIENT', '没有活跃会话，无法获取帧')
      return null
    }
    if (hasVncMethods(qemu)) {
      const frame = callVncMethod1<VncFrame | null>('vncGetFrame', this.sessionId)
      // 高频日志会严重拖慢 UI；这里做节流：最多 2 秒打一次
      const now = Date.now()
      if (now - this.lastFrameLogMs > 2000) {
        this.lastFrameLogMs = now
        if (frame) {
          hilog.info(0x0000, 'VNC_CLIENT', `帧更新: ${frame.width}x${frame.height}`)
        } else {
          hilog.info(0x0000, 'VNC_CLIENT', '无新帧')
        }
      }
      return frame
    }
    hilog.error(0x0000, 'VNC_CLIENT', 'vncGetFrame函数不可用')
    return null
  }

  sendPointer(x: number, y: number, buttonMask: number): boolean {
    if (this.sessionId == null) return false
    const api = qemu as QemuAPI
    if (hasVncMethods(qemu) && hasVncInputMethods(qemu) && api.vncSendPointer) {
      try {
        return api.vncSendPointer(this.sessionId, x, y, buttonMask) as boolean
      } catch (_) {
        return false
      }
    }
    return false
  }

  sendKey(keysym: number, down: boolean): boolean {
    if (this.sessionId == null) return false
    const api = qemu as QemuAPI
    if (hasVncMethods(qemu) && hasVncInputMethods(qemu) && api.vncSendKey) {
      try {
        return api.vncSendKey(this.sessionId, keysym, down) as boolean
      } catch (_) {
        return false
      }
    }
    return false
  }
}

const vncNativeClient: VNCNativeClientApi = new VNCNativeClient()
export default vncNativeClient

// 额外导出：避免部分 ArkTS 工具链对 default export 的类型推断不完整
export function vncSendPointer(x: number, y: number, buttonMask: number): boolean {
  return vncNativeClient.sendPointer(x, y, buttonMask)
}

export function vncSendKey(keysym: number, down: boolean): boolean {
  return vncNativeClient.sendKey(keysym, down)
}
