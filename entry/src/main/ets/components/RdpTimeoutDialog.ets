/**
 * RDP 连接超时处理对话框
 * 
 * 当 RDP 连接超时或卡死时，显示此对话框
 * 引导用户选择：继续等待、取消连接、强制关闭
 */

import { rdpManager, RdpConnectionInfo, SuggestedAction } from '../utils/RdpConnectionManager'

@CustomDialog
export struct RdpTimeoutDialog {
  controller: CustomDialogController
  @State connectionInfo: RdpConnectionInfo = {
    status: 'timeout',
    timeoutSeconds: 0,
    isStuck: true,
    message: '连接超时'
  }
  onAction?: (action: 'wait' | 'cancel' | 'force' | 'disconnect') => void

  aboutToAppear() {
    // 获取最新状态
    this.connectionInfo = rdpManager.getStatus()
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text('⚠️')
          .fontSize(24)
          .margin({ right: 8 })
        Text('连接问题')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 16 })

      // 状态信息
      Column() {
        Text(this.connectionInfo.message)
          .fontSize(16)
          .fontColor('#666666')
          .textAlign(TextAlign.Center)
        
        if (this.connectionInfo.timeoutSeconds > 0) {
          Text(`已等待 ${this.connectionInfo.timeoutSeconds} 秒`)
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 8 })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFF9E6')
      .borderRadius(8)
      .margin({ bottom: 20 })

      // 说明文字
      Text('请选择操作：')
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .margin({ bottom: 12 })

      // 操作按钮
      Column({ space: 10 }) {
        // 继续等待
        Button('继续等待')
          .width('100%')
          .height(44)
          .backgroundColor('#E8F5E9')
          .fontColor('#2E7D32')
          .onClick(() => {
            if (this.onAction) {
              this.onAction('wait')
            }
            this.controller.close()
          })

        // 取消连接
        Button('取消连接')
          .width('100%')
          .height(44)
          .backgroundColor('#E3F2FD')
          .fontColor('#1976D2')
          .onClick(() => {
            rdpManager.requestCancel()
            if (this.onAction) {
              this.onAction('cancel')
            }
            this.controller.close()
          })

        // 强制关闭（危险操作）
        Button('强制关闭')
          .width('100%')
          .height(44)
          .backgroundColor('#FFEBEE')
          .fontColor('#C62828')
          .onClick(() => {
            rdpManager.forceCleanup()
            if (this.onAction) {
              this.onAction('force')
            }
            this.controller.close()
          })
      }
      .width('100%')

      // 提示信息
      Text('💡 如果连接一直卡住，请选择"强制关闭"')
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 16 })
    }
    .width('90%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}

/**
 * 显示 RDP 超时对话框的工具函数
 */
export function showRdpTimeoutDialog(
  context: UIContext, 
  onAction?: (action: 'wait' | 'cancel' | 'force' | 'disconnect') => void
): CustomDialogController {
  let dialogController: CustomDialogController = new CustomDialogController({
    builder: RdpTimeoutDialog({
      onAction: onAction
    }),
    autoCancel: false,  // 不允许点击外部关闭
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  
  dialogController.open()
  return dialogController
}
