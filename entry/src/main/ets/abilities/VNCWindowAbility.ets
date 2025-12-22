/**
 * VNC 独立窗口 Ability
 * 用于在新窗口中显示 VNC 远程桌面
 * 原生 VNC 独立窗口（LibVNCClient）
 */
import UIAbility from '@ohos.app.ability.UIAbility'
import Want from '@ohos.app.ability.Want'
import window from '@ohos.window'
import hilog from '@ohos.hilog'

const TAG = 'VNCWindowAbility'

export default class VNCWindowAbility extends UIAbility {
  private mainWindow: window.Window | null = null
  
  // 从 want 中获取的参数
  private vmName: string = ''
  private vncPort: number = 5901  // RFB 端口（原生）
  private vncHost: string = '127.0.0.1'
  
  onCreate(want: Want, launchParam: object): void {
    hilog.info(0x0000, TAG, 'onCreate')
    
    // 解析启动参数
    if (want.parameters) {
      this.vmName = String(want.parameters['vmName'] ?? 'VM')
      this.vncPort = Number(want.parameters['vncPort'] ?? 5901)
      this.vncHost = String(want.parameters['vncHost'] ?? '127.0.0.1')
    }
    
    hilog.info(0x0000, TAG, 'VNC参数: vm=%{public}s host=%{public}s port=%{public}d',
      this.vmName, this.vncHost, this.vncPort)
    
    // 存储参数供页面使用
    AppStorage.setOrCreate<string>('vnc_vmName', this.vmName)
    AppStorage.setOrCreate<number>('vnc_port', this.vncPort)
    AppStorage.setOrCreate<string>('vnc_host', this.vncHost)
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate')
    
    windowStage.getMainWindow().then((win: window.Window): void => {
      this.mainWindow = win
      
      // 设置窗口标题为 VM 名称
      try {
        win.setWindowDecorVisible(true)
      } catch (e) {
        hilog.warn(0x0000, TAG, '设置窗口装饰失败: %{public}s', (e as Error).message)
      }
      
    }).catch((err: Error): void => {
      hilog.error(0x0000, TAG, '获取主窗口失败: %{public}s', err.message)
    })
    
    const pageName = 'pages/VNCNativeViewer'
    hilog.info(0x0000, TAG, '加载页面: %{public}s', pageName)
    
    windowStage.loadContent(pageName, (err, data) => {
      if (err.code) {
        hilog.error(0x0000, TAG, '加载内容失败: %{public}d, %{public}s', err.code, err.message)
        return
      }
      hilog.info(0x0000, TAG, 'VNC 窗口内容加载成功')
    })
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy')
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'onForeground')
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'onBackground')
  }
}
