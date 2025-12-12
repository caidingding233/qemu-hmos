import fs from '@ohos.file.fs'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'

/**
 * QEMU Keymaps 管理器 - 简化版
 */
export class KeymapsManager {
  
  static async ensureKeymaps(ctx: common.UIAbilityContext): Promise<string | null> {
    const TAG = 'KEYMAPS'
    
    try {
      hilog.info(0x0000, TAG, '>>> ensureKeymaps 开始 <<<')
      
      if (!ctx) {
        hilog.error(0x0000, TAG, 'ctx 为空！')
        return null
      }
      
      const filesDir = ctx.filesDir
      if (!filesDir) {
        hilog.error(0x0000, TAG, 'filesDir 为空！')
        return null
      }
      
      const qemuDataDir = `${filesDir}/qemu_data`
      const keymapsDir = `${qemuDataDir}/keymaps`
      const enUsPath = `${keymapsDir}/en-us`
      
      hilog.info(0x0000, TAG, 'filesDir=%{public}s', filesDir)
      hilog.info(0x0000, TAG, 'keymapsDir=%{public}s', keymapsDir)
      hilog.info(0x0000, TAG, 'enUsPath=%{public}s', enUsPath)
      
      // 1. 创建目录
      try {
        await fs.mkdir(qemuDataDir)
        hilog.info(0x0000, TAG, 'qemu_data 目录已创建')
      } catch (_) {
        hilog.info(0x0000, TAG, 'qemu_data 目录已存在')
      }
      
      try {
        await fs.mkdir(keymapsDir)
        hilog.info(0x0000, TAG, 'keymaps 目录已创建')
      } catch (_) {
        hilog.info(0x0000, TAG, 'keymaps 目录已存在')
      }
      
      // 2. 检查 en-us 文件
      hilog.info(0x0000, TAG, '>>> 检查 en-us 文件 <<<')
      let needCopy = true
      try {
        hilog.info(0x0000, TAG, '正在 stat: %{public}s', enUsPath)
        const stat = await fs.stat(enUsPath)
        hilog.info(0x0000, TAG, 'stat 成功: size=%{public}d', stat.size)
        if (stat.size > 10000) {  // en-us 约 28KB
          hilog.info(0x0000, TAG, 'en-us 已存在且有效 (%{public}d bytes)', stat.size)
          needCopy = false
        } else {
          hilog.warn(0x0000, TAG, 'en-us 文件太小 (%{public}d bytes)，需重新复制', stat.size)
        }
      } catch (e) {
        hilog.info(0x0000, TAG, 'en-us stat 失败: %{public}s', (e as Error).message)
        hilog.info(0x0000, TAG, 'en-us 不存在，需要复制')
      }
      hilog.info(0x0000, TAG, 'needCopy=%{public}s', String(needCopy))
      
      if (!needCopy) {
        hilog.info(0x0000, TAG, '>>> ensureKeymaps 成功（文件已存在）<<<')
        return qemuDataDir
      }
      
      // 3. 从 rawfile 复制
      hilog.info(0x0000, TAG, '开始从 rawfile 复制...')
      
      const rm = ctx.resourceManager
      if (!rm) {
        hilog.error(0x0000, TAG, 'resourceManager 为空！')
        return null
      }
      
      // 只复制必需的 en-us
      const keymapFiles = ['en-us', 'en-gb', 'de', 'fr', 'es', 'ja', 'ru']
      let successCount = 0
      
      for (const name of keymapFiles) {
        try {
          hilog.info(0x0000, TAG, '读取: keymaps/%{public}s', name)
          const content = await rm.getRawFileContent(`keymaps/${name}`)
          hilog.info(0x0000, TAG, '读取成功: %{public}d bytes', content.length)
          
          const targetPath = `${keymapsDir}/${name}`
          const file = await fs.open(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
          await fs.write(file.fd, content.buffer as ArrayBuffer)
          await fs.close(file)
          
          hilog.info(0x0000, TAG, '写入成功: %{public}s', name)
          successCount++
        } catch (e) {
          hilog.error(0x0000, TAG, '复制 %{public}s 失败: %{public}s', name, (e as Error).message)
        }
      }
      
      hilog.info(0x0000, TAG, '复制完成: %{public}d/%{public}d 个文件', successCount, keymapFiles.length)
      
      if (successCount === 0) {
        hilog.error(0x0000, TAG, '>>> ensureKeymaps 失败（无文件复制成功）<<<')
        return null
      }
      
      hilog.info(0x0000, TAG, '>>> ensureKeymaps 成功 <<<')
      return qemuDataDir
      
    } catch (e) {
      hilog.error(0x0000, TAG, '>>> ensureKeymaps 异常: %{public}s <<<', (e as Error).message)
      return null
    }
  }
  
  static getQemuDataDir(ctx: common.UIAbilityContext): string {
    return `${ctx.filesDir}/qemu_data`
  }
}
