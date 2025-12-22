import fs from '@ohos.file.fs'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'

// 固件文件名（aarch64 UEFI 建议同时提供 CODE + VARS 两块 pflash）
const FIRMWARE_CODE_FILENAME: string = 'edk2-aarch64-code.fd'
const FIRMWARE_VARS_FILENAME: string = 'edk2-arm-vars.fd'

export class FirmwareManager {
  /**
   * 确保 UEFI 固件存在：优先从 rawfile 复制到 files 目录
   * @param ctx UIAbility 上下文
   * @returns 固件路径（成功）或 null（失败）
   */
  static async ensureUefi(ctx: common.UIAbilityContext): Promise<string | null> {
    hilog.info(0x0000, 'FIRMWARE', '>>> ensureUefi 开始 <<<')
    try {
      // 使用 context.filesDir 获取正确的应用文件目录
      const filesDir = ctx.filesDir
      const targetPath = `${filesDir}/${FIRMWARE_CODE_FILENAME}`
      const varsTargetPath = `${filesDir}/${FIRMWARE_VARS_FILENAME}`
      
      hilog.info(0x0000, 'FIRMWARE', 'filesDir=%{public}s', filesDir)
      hilog.info(0x0000, 'FIRMWARE', '目标路径=%{public}s', targetPath)
      hilog.info(0x0000, 'FIRMWARE', 'VARS 目标路径=%{public}s', varsTargetPath)
      
      // 检查 CODE 是否存在
      let fileExists = false
      try {
        await fs.access(targetPath)
        fileExists = true
        hilog.info(0x0000, 'FIRMWARE', '文件存在检查: 存在')
      } catch (e) {
        hilog.info(0x0000, 'FIRMWARE', '文件存在检查: 不存在 (%{public}s)', (e as Error).message)
      }
      
      if (fileExists) {
        try {
          const stat = await fs.stat(targetPath)
          hilog.info(0x0000, 'FIRMWARE', '固件已存在，大小=%{public}d bytes', stat.size)
          // 额外确保 VARS 也存在（不影响返回值，但能显著提升 aarch64 UEFI 兼容性）
          await FirmwareManager.ensureUefiVars(ctx, varsTargetPath)
          hilog.info(0x0000, 'FIRMWARE', '>>> ensureUefi 成功，返回路径=%{public}s <<<', targetPath)
          return targetPath
        } catch (e) {
          hilog.error(0x0000, 'FIRMWARE', 'stat 失败: %{public}s', (e as Error).message)
        }
      }

      hilog.info(0x0000, 'FIRMWARE', '固件不存在或无法读取，从 rawfile 复制...')
      
      // 若缺失，尝试从 rawfile 复制
      const rm = ctx.resourceManager
      if (!rm || typeof (rm as object) !== 'object') {
        hilog.error(0x0000, 'FIRMWARE', '无法获取 resourceManager')
        return null
      }

      let content: Uint8Array
      try {
        // rawfile 下直接以文件名访问
        hilog.info(0x0000, 'FIRMWARE', '正在读取 rawfile(CODE): %{public}s', FIRMWARE_CODE_FILENAME)
        content = await rm.getRawFileContent(FIRMWARE_CODE_FILENAME)
        hilog.info(0x0000, 'FIRMWARE', '成功读取 rawfile，大小: %{public}d bytes', content.length)
      } catch (e) {
        hilog.error(0x0000, 'FIRMWARE', '读取 rawfile 失败: %{public}s', (e as Error).message)
        hilog.error(0x0000, 'FIRMWARE', '请确保 rawfile/%{public}s 存在', FIRMWARE_CODE_FILENAME)
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
          // 同时确保 VARS 盘存在
          await FirmwareManager.ensureUefiVars(ctx, varsTargetPath)
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

  /**
   * 确保 UEFI VARS 固件存在（aarch64 推荐）
   * 仅用于补齐变量盘，不改变 ensureUefi() 的返回值语义
   */
  private static async ensureUefiVars(ctx: common.UIAbilityContext, varsTargetPath: string): Promise<void> {
    try {
      // 已存在则跳过
      try {
        await fs.access(varsTargetPath)
        const st = await fs.stat(varsTargetPath)
        if (st.size > 1024) {
          hilog.info(0x0000, 'FIRMWARE', 'VARS 已存在且有效，大小=%{public}d bytes', st.size)
          return
        }
        hilog.warn(0x0000, 'FIRMWARE', 'VARS 文件过小，准备重写，大小=%{public}d bytes', st.size)
      } catch (_) {
        // not exist, continue
      }

      const rm = ctx.resourceManager
      if (!rm) {
        hilog.warn(0x0000, 'FIRMWARE', 'resourceManager 不可用，跳过 VARS 复制')
        return
      }

      hilog.info(0x0000, 'FIRMWARE', '正在读取 rawfile(VARS): %{public}s', FIRMWARE_VARS_FILENAME)
      const vars = await rm.getRawFileContent(FIRMWARE_VARS_FILENAME)
      hilog.info(0x0000, 'FIRMWARE', '读取 VARS 成功，大小=%{public}d bytes', vars.length)

      const f = await fs.open(varsTargetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
      await fs.write(f.fd, vars.buffer as ArrayBuffer)
      await fs.fsync(f.fd)
      await fs.close(f)
      const st2 = await fs.stat(varsTargetPath)
      hilog.info(0x0000, 'FIRMWARE', 'VARS 复制完成: %{public}s size=%{public}d', varsTargetPath, st2.size)
    } catch (e) {
      hilog.warn(0x0000, 'FIRMWARE', 'ensureUefiVars 失败(不致命): %{public}s', (e as Error).message)
    }
  }

}
