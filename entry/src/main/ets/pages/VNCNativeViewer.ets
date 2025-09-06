import router from '@ohos.router'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'
import qemu from 'libqemu_hmos.so'
import vnc from '../managers/VNCNativeClient'

interface VNCNativeRouteParams { vmName?: string }

interface VMConfig {
  name: string
  accel: string
  display: string
  nographic: boolean
  diskSizeGB?: number
  memoryMB?: number
  cpuCount?: number
}

@Entry
@Component
struct VNCNativeViewer {
  @State vmName: string = ''
  @State status: string = '准备中'
  @State connected: boolean = false

  aboutToAppear() {
    const params = router.getParams() as VNCNativeRouteParams
    if (params && typeof params.vmName === 'string') this.vmName = params.vmName

    hilog.info(0x0000, 'VNC_NATIVE', `初始化原生VNC页面, VM名称: ${this.vmName}`)

    const vncAvailable = vnc.isAvailable()
    if (vncAvailable) {
      this.status = '✅ 原生VNC可用 (实验性)'
      hilog.info(0x0000, 'VNC_NATIVE', 'LibVNCClient库可用')

      // NAPI模块已加载
      hilog.info(0x0000, 'VNC_NATIVE', 'NAPI模块已加载')
    } else {
      this.status = '❌ 原生VNC不可用: 缺少 LibVNCClient 预编译库'
      hilog.error(0x0000, 'VNC_NATIVE', 'LibVNCClient库不可用，请检查库文件')
    }
  }

  async startAndConnect() {
    try {
      hilog.info(0x0000, 'VNC_NATIVE', '开始启动原生VNC流程')

      // 步骤1: 检查VNC可用性
      const vncAvailable = vnc.isAvailable()
      hilog.info(0x0000, 'VNC_NATIVE', `VNC可用性检查: ${vncAvailable}`)
      if (!vncAvailable) {
        this.status = '❌ 原生VNC不可用: LibVNCClient库未找到'
        hilog.error(0x0000, 'VNC_NATIVE', 'LibVNCClient库不可用')
        return
      }

      // 步骤2: 检查KVM支持
      const kvmSupported = qemu.kvmSupported()
      hilog.info(0x0000, 'VNC_NATIVE', `KVM支持检查: ${kvmSupported}`)

      // 步骤3: 准备VM配置
      const vmConfig: VMConfig = {
        name: 'test_vm',
        accel: kvmSupported ? 'kvm' : 'tcg',
        display: 'vnc=:1',
        nographic: false,
        diskSizeGB: 64,     // 默认64GB磁盘
        memoryMB: 4096,     // 默认4GB内存
        cpuCount: 4         // 默认4核CPU
      }
      hilog.info(0x0000, 'VNC_NATIVE', `VM配置: ${JSON.stringify(vmConfig)}`)

      this.status = '🚀 启动VM (无WebSocket)…'
      hilog.info(0x0000, 'VNC_NATIVE', '开始调用qemu.startVm')
      
      // 检查qemu对象是否存在
      if (!qemu) {
        hilog.error(0x0000, 'VNC_NATIVE', 'qemu对象为null或undefined')
        this.status = '❌ qemu对象未加载'
        return
      }
      
      if (!qemu.startVm) {
        hilog.error(0x0000, 'VNC_NATIVE', 'qemu.startVm方法不存在')
        this.status = '❌ startVm方法不存在'
        return
      }
      
      hilog.info(0x0000, 'VNC_NATIVE', 'qemu对象和startVm方法存在，开始调用')
      
      let ok: boolean = false
      try {
        ok = qemu.startVm(vmConfig)
        hilog.info(0x0000, 'VNC_NATIVE', `qemu.startVm返回: ${ok}`)
      } catch (error) {
        hilog.error(0x0000, 'VNC_NATIVE', `qemu.startVm异常: ${error}`)
        this.status = '❌ VM启动异常'
        return
      }

      if (!ok) {
        this.status = '❌ VM启动失败'
        hilog.error(0x0000, 'VNC_NATIVE', 'VM启动失败，检查核心库和配置')
        return
      }

      hilog.info(0x0000, 'VNC_NATIVE', 'VM启动成功，开始连接VNC')
      this.status = '🔗 连接原生VNC 127.0.0.1:5901…'

      // 步骤4: 等待VM启动完成
      await new Promise<void>(resolve => setTimeout(resolve, 2000))

      // 步骤5: 连接VNC
      const connected = await vnc.connect('127.0.0.1', 5901)
      this.connected = connected

      if (connected) {
        this.status = '✅ 已连接原生VNC (渲染开发中)'
        hilog.info(0x0000, 'VNC_NATIVE', 'VNC连接成功')
      } else {
        this.status = '❌ VNC连接失败 (检查VM状态和网络)'
        hilog.error(0x0000, 'VNC_NATIVE', 'VNC连接失败，可能VM未启动或端口不可用')
      }

    } catch (e) {
      const errorMsg = (e as Error).message
      this.status = `❌ 异常: ${errorMsg}`
      hilog.error(0x0000, 'VNC_NATIVE', `异常发生: ${errorMsg}`)
    }
  }

  testGetFrame() {
    try {
      hilog.info(0x0000, 'VNC_NATIVE', '测试获取VNC帧')
      const frame = vnc.getFrame()
      if (frame) {
        this.status = `✅ 获取帧成功: ${frame.width}x${frame.height}, ${frame.pixels?.byteLength || 0} bytes`
        hilog.info(0x0000, 'VNC_NATIVE', `帧信息: ${frame.width}x${frame.height}`)
      } else {
        this.status = '❌ 获取帧失败: 无帧数据'
        hilog.warn(0x0000, 'VNC_NATIVE', '获取帧失败')
      }
    } catch (e) {
      const errorMsg = (e as Error).message
      this.status = `❌ 获取帧异常: ${errorMsg}`
      hilog.error(0x0000, 'VNC_NATIVE', `获取帧异常: ${errorMsg}`)
    }
  }

  private goBack() { router.back() }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => this.goBack())
        Text(this.vmName).fontSize(16).fontWeight(FontWeight.Medium).margin({ left: 8 })
      }.width('100%').padding(12)

      Text(this.status)
        .fontSize(14)
        .fontColor(this.status.includes('❌') ? Color.Red : this.status.includes('✅') ? Color.Green : Color.Grey)
        .padding(12)
        .textAlign(TextAlign.Center)

      Button('启动并连接原生VNC')
        .onClick(() => this.startAndConnect())
        .margin({ top: 12 })

      Button('测试获取帧')
        .onClick(() => this.testGetFrame())
        .margin({ top: 8 })
        .enabled(this.connected)
    }
    .width('100%').height('100%')
  }
}
