/**
 * VNC 独立窗口页面
 * 在新窗口中显示 VNC 远程桌面
 */
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'
import { VNCDisplay } from '../components/VNCDisplay'

@Entry
@Component
struct VNCWindow {
  @StorageLink('vnc_vmName') vmName: string = 'VM'
  @StorageLink('vnc_port') vncPort: number = 5701  // WebSocket 端口
  @StorageLink('vnc_host') vncHost: string = '127.0.0.1'
  
  @State isConnected: boolean = false
  @State statusText: string = '正在连接...'
  
  aboutToAppear(): void {
    hilog.info(0x0000, 'VNCWindow', '页面加载: vm=%{public}s host=%{public}s:%{public}d',
      this.vmName, this.vncHost, this.vncPort)
  }
  
  build() {
    Column() {
      // 顶部状态栏
      Row() {
        // VM 名称
        Text(`🖥️ ${this.vmName}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
        
        Blank()
        
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
      
      // VNC 显示区域
      VNCDisplay({
        config: { host: this.vncHost, port: this.vncPort },
        callbacks: {
          onConnected: () => {
            this.isConnected = true
            this.statusText = '已连接'
          },
          onDisconnected: () => {
            this.isConnected = false
            this.statusText = '已断开'
          },
          onError: (error: string) => {
            this.statusText = `错误: ${error}`
          }
        }
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A1A')
  }
  
  private closeWindow(): void {
    const ctx = getContext(this) as common.UIAbilityContext
    ctx.terminateSelf()
  }
}

