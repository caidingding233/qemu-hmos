/**
 * 串口控制台 独立窗口 Ability
 * 用于在新窗口中显示虚拟机的串口 TTL 终端
 */
import UIAbility from '@ohos.app.ability.UIAbility'
import Want from '@ohos.app.ability.Want'
import window from '@ohos.window'
import hilog from '@ohos.hilog'

const TAG = 'ConsoleWindowAbility'

export default class ConsoleWindowAbility extends UIAbility {
  private mainWindow: window.Window | null = null
  
  // 从 want 中获取的参数
  private vmName: string = ''
  private vmId: string = ''
  
  onCreate(want: Want, launchParam: object): void {
    hilog.info(0x0000, TAG, 'onCreate')
    
    // 解析启动参数
    if (want.parameters) {
      this.vmName = String(want.parameters['vmName'] ?? 'VM')
      this.vmId = String(want.parameters['vmId'] ?? '')
    }
    
    hilog.info(0x0000, TAG, '控制台参数: vmName=%{public}s vmId=%{public}s', this.vmName, this.vmId)
    
    // 存储参数供页面使用
    AppStorage.setOrCreate<string>('console_vmName', this.vmName)
    AppStorage.setOrCreate<string>('console_vmId', this.vmId)
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
    
    // 加载控制台页面
    windowStage.loadContent('pages/ConsoleWindow', (err, data) => {
      if (err.code) {
        hilog.error(0x0000, TAG, '加载内容失败: %{public}d, %{public}s', err.code, err.message)
        return
      }
      hilog.info(0x0000, TAG, '控制台窗口内容加载成功')
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

