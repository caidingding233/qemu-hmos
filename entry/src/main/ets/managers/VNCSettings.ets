/**
 * VNC 设置管理器
 * 管理VNC客户端模式和端口配置
 */
import data_preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'

// VNC 客户端模式
export type VNCMode = 'native' | 'novnc'

// VNC 设置接口
export interface VNCSettingsData {
  mode: VNCMode           // VNC客户端模式
  nativePort: number      // 原生客户端端口 (RFB协议)
  novncPort: number       // noVNC端口 (WebSocket)
  autoConnect: boolean    // 自动连接
  quality: number         // 图像质量 (0-9)
}

const PREF_NAME = 'vnc_settings'
const KEY_MODE = 'vnc_mode'
const KEY_NATIVE_PORT = 'vnc_native_port'
const KEY_NOVNC_PORT = 'vnc_novnc_port'
const KEY_AUTO_CONNECT = 'vnc_auto_connect'
const KEY_QUALITY = 'vnc_quality'

// 默认设置
const DEFAULT_SETTINGS: VNCSettingsData = {
  mode: 'novnc',        // 默认使用noVNC（兼容性更好）
  nativePort: 5901,     // RFB端口 (display :1)
  novncPort: 5700,      // WebSocket端口
  autoConnect: true,
  quality: 6
}

class VNCSettings {
  private preferences: data_preferences.Preferences | null = null
  private settings: VNCSettingsData = { ...DEFAULT_SETTINGS }
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
      this.settings.mode = await this.preferences.get(KEY_MODE, DEFAULT_SETTINGS.mode) as VNCMode
      this.settings.nativePort = await this.preferences.get(KEY_NATIVE_PORT, DEFAULT_SETTINGS.nativePort) as number
      this.settings.novncPort = await this.preferences.get(KEY_NOVNC_PORT, DEFAULT_SETTINGS.novncPort) as number
      this.settings.autoConnect = await this.preferences.get(KEY_AUTO_CONNECT, DEFAULT_SETTINGS.autoConnect) as boolean
      this.settings.quality = await this.preferences.get(KEY_QUALITY, DEFAULT_SETTINGS.quality) as number
      
      hilog.info(0x0000, 'VNCSettings', '加载设置: mode=%{public}s, nativePort=%{public}d, novncPort=%{public}d',
        this.settings.mode, this.settings.nativePort, this.settings.novncPort)
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
      await this.preferences.put(KEY_MODE, this.settings.mode)
      await this.preferences.put(KEY_NATIVE_PORT, this.settings.nativePort)
      await this.preferences.put(KEY_NOVNC_PORT, this.settings.novncPort)
      await this.preferences.put(KEY_AUTO_CONNECT, this.settings.autoConnect)
      await this.preferences.put(KEY_QUALITY, this.settings.quality)
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
    return { ...this.settings }
  }

  /**
   * 获取VNC模式
   */
  getMode(): VNCMode {
    return this.settings.mode
  }

  /**
   * 设置VNC模式
   */
  async setMode(mode: VNCMode): Promise<void> {
    this.settings.mode = mode
    await this.save()
  }

  /**
   * 获取当前模式对应的端口
   */
  getCurrentPort(): number {
    return this.settings.mode === 'native' ? this.settings.nativePort : this.settings.novncPort
  }

  /**
   * 设置原生客户端端口
   */
  async setNativePort(port: number): Promise<void> {
    this.settings.nativePort = port
    await this.save()
  }

  /**
   * 设置noVNC端口
   */
  async setNoVNCPort(port: number): Promise<void> {
    this.settings.novncPort = port
    await this.save()
  }

  /**
   * 获取原生客户端端口
   */
  getNativePort(): number {
    return this.settings.nativePort
  }

  /**
   * 获取noVNC端口
   */
  getNoVNCPort(): number {
    return this.settings.novncPort
  }

  /**
   * 设置图像质量
   */
  async setQuality(quality: number): Promise<void> {
    this.settings.quality = Math.max(0, Math.min(9, quality))
    await this.save()
  }

  /**
   * 获取图像质量
   */
  getQuality(): number {
    return this.settings.quality
  }
}

export const vncSettings = new VNCSettings()

