import fs from '@ohos.file.fs'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'

// 需要复制的 keymap 文件列表（仅复制常用的）
const KEYMAP_FILES: string[] = [
  'en-us',    // 美式英语（必需，QEMU VNC 默认使用）
  'en-gb',    // 英式英语
  'de',       // 德语
  'fr',       // 法语
  'es',       // 西班牙语
  'it',       // 意大利语
  'ja',       // 日语
  'ru',       // 俄语
  'pt-br',    // 巴西葡萄牙语
]

/**
 * QEMU Keymaps 管理器
 * 
 * VNC 初始化时需要 keymaps 目录中的键盘映射文件。
 * 此管理器负责将 rawfile 中的 keymaps 复制到沙盒目录。
 */
export class KeymapsManager {
  /**
   * 确保 keymaps 目录存在并包含必要的映射文件
   * @param ctx UIAbility 上下文
   * @returns QEMU 数据目录路径（包含 keymaps 子目录）或 null（失败）
   */
  static async ensureKeymaps(ctx: common.UIAbilityContext): Promise<string | null> {
    try {
      // 目标目录：filesDir/qemu_data/keymaps/
      const filesDir = ctx.filesDir
      const qemuDataDir = `${filesDir}/qemu_data`
      const keymapsDir = `${qemuDataDir}/keymaps`
      
      // 详细路径日志，便于调试
      hilog.info(0x0000, 'KEYMAPS', '========== KeymapsManager ==========')
      hilog.info(0x0000, 'KEYMAPS', 'ctx.filesDir = %{public}s', filesDir)
      hilog.info(0x0000, 'KEYMAPS', 'qemuDataDir = %{public}s', qemuDataDir)
      hilog.info(0x0000, 'KEYMAPS', 'keymapsDir = %{public}s', keymapsDir)
      
      // 创建目录结构
      await KeymapsManager.ensureDir(qemuDataDir)
      await KeymapsManager.ensureDir(keymapsDir)
      
      // 检查 en-us（必需文件）是否已存在
      const enUsPath = `${keymapsDir}/en-us`
      if (await KeymapsManager.exists(enUsPath)) {
        hilog.info(0x0000, 'KEYMAPS', 'keymaps 已存在，跳过复制')
        return qemuDataDir
      }

      hilog.info(0x0000, 'KEYMAPS', 'keymaps 不存在，从 rawfile 复制...')
      
      const rm = ctx.resourceManager
      if (!rm || typeof (rm as object) !== 'object') {
        hilog.error(0x0000, 'KEYMAPS', '无法获取 resourceManager')
        return null
      }

      // 复制每个 keymap 文件
      let successCount = 0
      for (const keymapName of KEYMAP_FILES) {
        const rawfilePath = `keymaps/${keymapName}`
        const targetPath = `${keymapsDir}/${keymapName}`
        
        try {
          const content = await rm.getRawFileContent(rawfilePath)
          await KeymapsManager.writeFile(targetPath, content)
          successCount++
          hilog.info(0x0000, 'KEYMAPS', '复制成功: %{public}s (%{public}d bytes)', 
            keymapName, content.length)
        } catch (e) {
          // 某些 keymap 文件可能不存在，记录但不报错
          hilog.warn(0x0000, 'KEYMAPS', '复制失败（可能不存在）: %{public}s - %{public}s', 
            keymapName, (e as Error).message)
        }
      }

      if (successCount === 0) {
        hilog.error(0x0000, 'KEYMAPS', '没有成功复制任何 keymap 文件！')
        return null
      }

      hilog.info(0x0000, 'KEYMAPS', 'keymaps 复制完成，成功 %{public}d/%{public}d 个文件', 
        successCount, KEYMAP_FILES.length)
      hilog.info(0x0000, 'KEYMAPS', 'QEMU 数据目录: %{public}s', qemuDataDir)
      
      return qemuDataDir
    } catch (e) {
      hilog.error(0x0000, 'KEYMAPS', 'ensureKeymaps 异常: %{public}s', (e as Error).message)
      return null
    }
  }

  /**
   * 获取 QEMU 数据目录路径（不执行复制，仅返回路径）
   */
  static getQemuDataDir(ctx: common.UIAbilityContext): string {
    return `${ctx.filesDir}/qemu_data`
  }

  private static async exists(path: string): Promise<boolean> {
    try {
      await fs.access(path)
      return true
    } catch (_) {
      return false
    }
  }

  private static async ensureDir(path: string): Promise<void> {
    try {
      await fs.access(path)
    } catch (_) {
      await fs.mkdir(path)
    }
  }

  private static async writeFile(path: string, content: Uint8Array): Promise<void> {
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    await fs.write(file.fd, content.buffer as ArrayBuffer)
    await fs.close(file)
  }
}

