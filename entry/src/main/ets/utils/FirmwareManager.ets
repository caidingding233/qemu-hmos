import fs from '@ohos.file.fs'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'

// 固件文件名
const FIRMWARE_FILENAME: string = 'edk2-aarch64-code.fd'

export class FirmwareManager {
  /**
   * 确保 UEFI 固件存在：优先从 rawfile 复制到 files 目录
   * @param ctx UIAbility 上下文
   * @returns 固件路径（成功）或 null（失败）
   */
  static async ensureUefi(ctx: common.UIAbilityContext): Promise<string | null> {
    try {
      // 使用 context.filesDir 获取正确的应用文件目录
      const filesDir = ctx.filesDir
      const targetPath = `${filesDir}/${FIRMWARE_FILENAME}`
      
      hilog.info(0x0000, 'FIRMWARE', '检查固件路径: %{public}s', targetPath)
      
      if (await FirmwareManager.exists(targetPath)) {
        hilog.info(0x0000, 'FIRMWARE', '固件已存在')
        return targetPath
      }

      hilog.info(0x0000, 'FIRMWARE', '固件不存在，从 rawfile 复制...')
      
      // 若缺失，尝试从 rawfile 复制
      const rm = ctx.resourceManager
      if (!rm || typeof (rm as object) !== 'object') {
        hilog.error(0x0000, 'FIRMWARE', '无法获取 resourceManager')
        return null
      }

      let content: Uint8Array
      try {
        // rawfile 下直接以文件名访问
        content = await rm.getRawFileContent(FIRMWARE_FILENAME)
        hilog.info(0x0000, 'FIRMWARE', '成功读取 rawfile，大小: %{public}d bytes', content.length)
      } catch (e) {
        hilog.error(0x0000, 'FIRMWARE', '读取 rawfile 失败: %{public}s', (e as Error).message)
        return null
      }

      try {
        // 写入目标路径（覆盖写入以防半成品）
        // 使用 READ_WRITE 以便 fsync
        const file = await fs.open(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
        // Uint8Array 转 ArrayBuffer
        await fs.write(file.fd, content.buffer as ArrayBuffer)
        // 强制刷新到磁盘
        await fs.fsync(file.fd)
        await fs.close(file)
        
        // 再次检查文件是否真的存在且大小正确
        const stat = await fs.stat(targetPath)
        if (stat.size === content.length) {
          hilog.info(0x0000, 'FIRMWARE', '固件复制成功并验证: %{public}s', targetPath)
          return targetPath
        } else {
          hilog.error(0x0000, 'FIRMWARE', '固件复制后大小不匹配')
          return null
        }
      } catch (e) {
        hilog.error(0x0000, 'FIRMWARE', '写入固件失败: %{public}s', (e as Error).message)
        return null
      }
    } catch (e) {
      hilog.error(0x0000, 'FIRMWARE', 'ensureUefi 异常: %{public}s', (e as Error).message)
      return null
    }
  }

  private static async exists(path: string): Promise<boolean> {
    try {
      await fs.access(path)
      return true
    } catch (_) {
      return false
    }
  }
}
