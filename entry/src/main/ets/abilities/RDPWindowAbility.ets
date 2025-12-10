/**
 * RDP 独立窗口 Ability
 * 用于在新窗口中显示 FreeRDP 远程桌面
 */
import UIAbility from '@ohos.app.ability.UIAbility'
import Want from '@ohos.app.ability.Want'
import window from '@ohos.window'
import hilog from '@ohos.hilog'

const TAG = 'RDPWindowAbility'

export default class RDPWindowAbility extends UIAbility {
  private mainWindow: window.Window | null = null
  
  // 从 want 中获取的参数
  private vmName: string = ''
  private vmId: string = ''
  private rdpPort: number = 3390
  private rdpHost: string = '127.0.0.1'
  
  onCreate(want: Want, launchParam: object): void {
    hilog.info(0x0000, TAG, 'onCreate')
    
    // 解析启动参数
    if (want.parameters) {
      this.vmName = String(want.parameters['vmName'] ?? 'VM')
      this.vmId = String(want.parameters['vmId'] ?? '')
      this.rdpPort = Number(want.parameters['rdpPort'] ?? 3390)
      this.rdpHost = String(want.parameters['rdpHost'] ?? '127.0.0.1')
    }
    
    hilog.info(0x0000, TAG, 'RDP参数: vm=%{public}s host=%{public}s port=%{public}d',
      this.vmName, this.rdpHost, this.rdpPort)
    
    // 存储参数供页面使用
    AppStorage.setOrCreate<string>('rdp_vmName', this.vmName)
    AppStorage.setOrCreate<string>('rdp_vmId', this.vmId)
    AppStorage.setOrCreate<number>('rdp_port', this.rdpPort)
    AppStorage.setOrCreate<string>('rdp_host', this.rdpHost)
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate')
    
    windowStage.getMainWindow().then((win: window.Window): void => {
      this.mainWindow = win
      
      try {
        win.setWindowDecorVisible(true)
      } catch (e) {
        hilog.warn(0x0000, TAG, '设置窗口装饰失败: %{public}s', (e as Error).message)
      }
      
    }).catch((err: Error): void => {
      hilog.error(0x0000, TAG, '获取主窗口失败: %{public}s', err.message)
    })
    
    // 加载 RDP 查看器页面
    windowStage.loadContent('pages/RDPWindow', (err, data) => {
      if (err.code) {
        hilog.error(0x0000, TAG, '加载内容失败: %{public}d, %{public}s', err.code, err.message)
        return
      }
      hilog.info(0x0000, TAG, 'RDP 窗口内容加载成功')
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

