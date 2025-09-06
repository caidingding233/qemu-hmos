import hilog from '@ohos.hilog'
import qemu from 'libqemu_hmos.so'
import { VncFrame, QemuAPI } from '../types/qemu'

interface QemuWithVnc extends QemuAPI {
  vncAvailable(): boolean
  vncCreate(): number
  vncConnect(id: number, host: string, port: number): boolean
  vncDisconnect(id: number): boolean
  vncGetFrame(id: number): VncFrame | null
}

class VNCNativeClient {
  private sessionId: number | null = null
  private host: string = '127.0.0.1'
  private port: number = 5901

  isAvailable(): boolean {
    const qi = qemu as QemuWithVnc
    const available = typeof (qi as QemuWithVnc).vncAvailable === 'function' ? qi.vncAvailable() : false
    hilog.info(0x0000, 'VNC_CLIENT', `VNC可用性检查: ${available}`)
    return available
  }

  create(): boolean {
    const qi = qemu as QemuWithVnc
    if (typeof qi.vncCreate !== 'function') {
      hilog.error(0x0000, 'VNC_CLIENT', 'vncCreate函数不可用')
      return false
    }
    this.sessionId = qi.vncCreate()
    const success = typeof this.sessionId === 'number' && this.sessionId > 0
    hilog.info(0x0000, 'VNC_CLIENT', `VNC会话创建: ${success ? '成功' : '失败'}, ID: ${this.sessionId}`)
    return success
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

    const qi = qemu as QemuWithVnc
    if (typeof qi.vncConnect !== 'function') {
      hilog.error(0x0000, 'VNC_CLIENT', 'vncConnect函数不可用')
      return false
    }

    const result = qi.vncConnect(this.sessionId as number, host, port)
    hilog.info(0x0000, 'VNC_CLIENT', `VNC连接结果: ${result ? '成功' : '失败'}`)
    return result
  }

  disconnect(): void {
    if (this.sessionId == null) {
      hilog.info(0x0000, 'VNC_CLIENT', '没有活跃会话，无需断开')
      return
    }
    const qi = qemu as QemuWithVnc
    if (typeof qi.vncDisconnect === 'function') {
      qi.vncDisconnect(this.sessionId as number)
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
    const qi = qemu as QemuWithVnc
    if (typeof qi.vncGetFrame !== 'function') {
      hilog.error(0x0000, 'VNC_CLIENT', 'vncGetFrame函数不可用')
      return null
    }
    const frame = qi.vncGetFrame(this.sessionId as number) as VncFrame | null
    if (frame) {
      hilog.debug(0x0000, 'VNC_CLIENT', `获取帧成功: ${frame.width}x${frame.height}`)
    } else {
      hilog.warn(0x0000, 'VNC_CLIENT', '获取帧失败或无新帧')
    }
    return frame
  }
}

export default new VNCNativeClient()
