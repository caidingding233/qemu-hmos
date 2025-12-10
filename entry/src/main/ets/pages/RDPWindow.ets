/**
 * RDP 独立窗口页面
 * 在新窗口中显示 FreeRDP 远程桌面
 */
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'
import qemu from 'qemu_hmos'

interface RdpClientInfo {
  id: string
}

interface RdpConnectConfig {
  host: string
  port: number
  username?: string
  password?: string
  width?: number
  height?: number
}

interface RdpNativeApi {
  createRdpClient?: () => RdpClientInfo
  connectRdp?: (clientId: string, config: RdpConnectConfig) => number
  getRdpStatus?: (clientId: string) => number
  disconnectRdp?: (clientId: string) => number
  destroyRdpClient?: (clientId: string) => number
}

@Entry
@Component
struct RDPWindow {
  @StorageLink('rdp_vmName') vmName: string = 'VM'
  @StorageLink('rdp_vmId') vmId: string = ''
  @StorageLink('rdp_port') rdpPort: number = 3390
  @StorageLink('rdp_host') rdpHost: string = '127.0.0.1'
  
  @State isConnected: boolean = false
  @State statusText: string = '正在连接...'
  @State connectionInfo: string = ''
  private rdpClientId: string = ''
  
  aboutToAppear(): void {
    hilog.info(0x0000, 'RDPWindow', '页面加载: vm=%{public}s host=%{public}s:%{public}d',
      this.vmName, this.rdpHost, this.rdpPort)
    
    this.connectionInfo = `${this.rdpHost}:${this.rdpPort}`
    
    this.connectRDP()
  }
  
  private connectRDP(): void {
    try {
      this.statusText = '正在发起 FreeRDP 连接...'
      
      if (!qemu || typeof qemu.createRdpClient !== 'function' || typeof qemu.connectRdp !== 'function') {
        this.isConnected = false
        this.statusText = 'FreeRDP 模块不可用'
        hilog.error(0x0000, 'RDPWindow', 'qemu_hmos RDP 接口不可用')
        return
      }
      
      const client = qemu.createRdpClient()
      this.rdpClientId = client?.id ?? ''
      if (!this.rdpClientId) {
        this.isConnected = false
        this.statusText = '创建 RDP 客户端失败'
        return
      }
      
      const result = qemu.connectRdp(this.rdpClientId, {
        host: this.rdpHost,
        port: this.rdpPort,
        username: '',
        password: '',
        width: 1280,
        height: 720
      })
      
      if (result === 0) {
        this.isConnected = true
        this.statusText = '已连接 FreeRDP'
        hilog.info(0x0000, 'RDPWindow', 'FreeRDP 连接成功: %{public}s', this.connectionInfo)
      } else {
        this.isConnected = false
        this.statusText = 'FreeRDP 连接失败'
        hilog.error(0x0000, 'RDPWindow', 'FreeRDP 连接失败，状态码 %{public}d', result)
      }
    } catch (e) {
      const message = (e as Error).message ?? String(e)
      this.isConnected = false
      this.statusText = `错误: ${message}`
      hilog.error(0x0000, 'RDPWindow', 'FreeRDP 启动失败: %{public}s', message)
    }
  }
  
  build() {
    Column() {
      // 顶部状态栏
      Row() {
        // VM 名称
        Text(`🚀 ${this.vmName}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
        
        Blank()
        
        // 连接信息
        Text(this.connectionInfo)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ right: 12 })
        
        // 连接状态
        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(this.isConnected ? '#34C759' : '#FF9500')
          Text(this.statusText)
            .fontSize(12)
            .fontColor('#AAAAAA')
            .margin({ left: 6 })
        }
        
        // 关闭按钮
        Button() {
          Text('✕').fontSize(16).fontColor('#888888')
        }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor('rgba(255, 255, 255, 0.1)')
        .margin({ left: 16 })
        .onClick(() => {
          this.closeWindow()
        })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .backgroundColor('rgba(30, 30, 30, 0.95)')
      
      // RDP 显示区域（占位）
      Column() {
        // 加载动画
        if (!this.isConnected) {
          Column() {
            LoadingProgress()
              .width(64)
              .height(64)
              .color('#007AFF')
            
            Text('正在连接 RDP 服务...')
              .fontSize(16)
              .fontColor('#888888')
              .margin({ top: 16 })
            
            Text(`目标: ${this.rdpHost}:${this.rdpPort}`)
              .fontSize(13)
              .fontColor('#555555')
              .margin({ top: 8 })
            
            // 提示信息
            Column() {
              Text('💡 提示')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FF9500')
                .margin({ bottom: 8 })
              
              Text('• 确保虚拟机内已启用远程桌面')
                .fontSize(12)
                .fontColor('#666666')
              Text('• Windows: 设置 → 系统 → 远程桌面')
                .fontSize(12)
                .fontColor('#666666')
              Text('• Linux: 安装 xrdp 服务')
                .fontSize(12)
                .fontColor('#666666')
            }
            .margin({ top: 32 })
            .padding(16)
            .backgroundColor('rgba(255, 149, 0, 0.1)')
            .borderRadius(12)
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#0D0D0D')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A1A')
  }
  
  private closeWindow(): void {
    if (this.rdpClientId && qemu && typeof qemu.disconnectRdp === 'function') {
      try {
        qemu.disconnectRdp(this.rdpClientId)
      } catch (e) {
        hilog.warn(0x0000, 'RDPWindow', '断开 FreeRDP 时出错: %{public}s', (e as Error).message)
      }
    }
    const ctx = getContext(this) as common.UIAbilityContext
    ctx.terminateSelf()
  }
}

