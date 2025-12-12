/**
 * VNC 设置管理器
 * 管理原生 VNC 端口配置（已移除 noVNC）
 */
import data_preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'

// VNC 设置接口
export interface VNCSettingsData {
  nativePort: number      // 原生客户端端口 (RFB协议)
  autoConnect: boolean    // 自动连接
}

const PREF_NAME = 'vnc_settings'
const KEY_NATIVE_PORT = 'vnc_native_port'
const KEY_AUTO_CONNECT = 'vnc_auto_connect'

// 默认设置
const DEFAULT_SETTINGS: VNCSettingsData = {
  nativePort: 5901,     // RFB端口 (display :1)
  autoConnect: true
}

class VNCSettings {
  private preferences: data_preferences.Preferences | null = null
  private settings: VNCSettingsData = {
    nativePort: DEFAULT_SETTINGS.nativePort,
    autoConnect: DEFAULT_SETTINGS.autoConnect
  }
  private initialized: boolean = false

  /**
   * 初始化设置
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return
    
    try {
      this.preferences = await data_preferences.getPreferences(context, PREF_NAME)
      await this.load()
      this.initialized = true
      hilog.info(0x0000, 'VNCSettings', '设置初始化完成')
    } catch (e) {
      hilog.error(0x0000, 'VNCSettings', '设置初始化失败: %{public}s', (e as Error).message)
    }
  }

  /**
   * 加载设置
   */
  private async load(): Promise<void> {
    if (!this.preferences) return
    
    try {
      this.settings.nativePort = await this.preferences.get(KEY_NATIVE_PORT, DEFAULT_SETTINGS.nativePort) as number
      this.settings.autoConnect = await this.preferences.get(KEY_AUTO_CONNECT, DEFAULT_SETTINGS.autoConnect) as boolean
      
      hilog.info(0x0000, 'VNCSettings', '加载设置: nativePort=%{public}d', this.settings.nativePort)
    } catch (e) {
      hilog.error(0x0000, 'VNCSettings', '加载设置失败: %{public}s', (e as Error).message)
    }
  }

  /**
   * 保存设置
   */
  private async save(): Promise<void> {
    if (!this.preferences) return
    
    try {
      await this.preferences.put(KEY_NATIVE_PORT, this.settings.nativePort)
      await this.preferences.put(KEY_AUTO_CONNECT, this.settings.autoConnect)
      await this.preferences.flush()
      
      hilog.info(0x0000, 'VNCSettings', '设置已保存')
    } catch (e) {
      hilog.error(0x0000, 'VNCSettings', '保存设置失败: %{public}s', (e as Error).message)
    }
  }

  /**
   * 获取当前设置
   */
  getSettings(): VNCSettingsData {
    return {
      nativePort: this.settings.nativePort,
      autoConnect: this.settings.autoConnect
    }
  }

  /**
   * 设置原生客户端端口
   */
  async setNativePort(port: number): Promise<void> {
    this.settings.nativePort = port
    await this.save()
  }

  /**
   * 获取原生客户端端口
   */
  getNativePort(): number {
    return this.settings.nativePort
  }
}

export const vncSettings = new VNCSettings()

