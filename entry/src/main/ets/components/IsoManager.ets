/**
 * ISO 镜像管理组件
 * 用于浏览、上传和删除 ISO 文件
 */
import fs from '@ohos.file.fs'
import picker from '@ohos.file.picker'
import common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'

// ISO 文件信息
interface IsoFileInfo {
  name: string
  path: string
  size: number  // 字节
  modifiedTime: number
}

@Component
export struct IsoManager {
  @State isoFiles: IsoFileInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State totalSize: number = 0
  @State copyProgress: number = 0
  @State isCopying: boolean = false

  // ISO 存储目录
  private readonly isoDir: string = '/data/storage/el2/base/haps/entry/files/isos'

  aboutToAppear() {
    this.refreshIsoList()
  }

  // 刷新 ISO 列表
  async refreshIsoList() {
    this.isLoading = true
    this.errorMessage = ''
    this.isoFiles = []
    this.totalSize = 0

    try {
      // 确保目录存在
      try {
        await fs.mkdir(this.isoDir)
      } catch (_) { /* 目录可能已存在 */ }

      // 列出目录内容
      const files = await fs.listFile(this.isoDir)
      const isoList: IsoFileInfo[] = []

      for (const fileName of files) {
        if (fileName.toLowerCase().endsWith('.iso')) {
          const filePath = this.isoDir + '/' + fileName
          try {
            const stat = await fs.stat(filePath)
            isoList.push({
              name: fileName,
              path: filePath,
              size: stat.size,
              modifiedTime: stat.mtime
            })
            this.totalSize += stat.size
          } catch (e) {
            hilog.warn(0x0000, 'ISO_MANAGER', '无法获取文件信息: %{public}s', fileName)
          }
        }
      }

      // 按修改时间排序（最新的在前）
      isoList.sort((a, b) => b.modifiedTime - a.modifiedTime)
      this.isoFiles = isoList

    } catch (e) {
      this.errorMessage = '读取 ISO 列表失败: ' + (e as Error).message
      hilog.error(0x0000, 'ISO_MANAGER', '读取 ISO 列表失败: %{public}s', (e as Error).message)
    } finally {
      this.isLoading = false
    }
  }

  // 添加 ISO（从外部存储复制）
  async addIso() {
    try {
      const dp = new picker.DocumentViewPicker()
      const result = await dp.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['iso', 'ISO', 'img', 'IMG']
      })

      if (!result || result.length === 0) return

      let srcPath = result[0]
      if (srcPath.startsWith('file://')) {
        srcPath = srcPath.substring(7)
      }

      // 检查是否已在沙箱中
      if (srcPath.startsWith(this.isoDir)) {
        this.errorMessage = '该文件已在 ISO 目录中'
        return
      }

      // 开始复制
      this.isCopying = true
      this.copyProgress = 0
      this.errorMessage = ''

      const fileName = srcPath.split('/').pop() || 'image.iso'
      const dstPath = this.isoDir + '/' + fileName

      // 确保目录存在
      try {
        await fs.mkdir(this.isoDir)
      } catch (_) { }

      // 获取源文件大小
      const srcStat = await fs.stat(srcPath)
      const totalBytes = srcStat.size

      // 逐块复制并更新进度
      const src = await fs.open(srcPath, fs.OpenMode.READ_ONLY)
      const dst = await fs.open(dstPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
      const chunkSize = 4 * 1024 * 1024  // 4MB
      const buf = new ArrayBuffer(chunkSize)
      let copiedBytes = 0

      while (true) {
        const n: number = await fs.read(src.fd, buf)
        if (!n || n <= 0) break
        await fs.write(dst.fd, buf.slice(0, n))
        copiedBytes += n
        this.copyProgress = Math.round((copiedBytes / totalBytes) * 100)
        if (n < chunkSize) break
      }

      await fs.close(src)
      await fs.close(dst)

      hilog.info(0x0000, 'ISO_MANAGER', 'ISO 复制成功: %{public}s', fileName)

      // 刷新列表
      await this.refreshIsoList()

    } catch (e) {
      this.errorMessage = '复制 ISO 失败: ' + (e as Error).message
      hilog.error(0x0000, 'ISO_MANAGER', '复制 ISO 失败: %{public}s', (e as Error).message)
    } finally {
      this.isCopying = false
      this.copyProgress = 0
    }
  }

  // 删除 ISO
  async deleteIso(iso: IsoFileInfo) {
    AlertDialog.show({
      title: '确认删除',
      message: `确定要删除 "${iso.name}" 吗？\n大小: ${this.formatSize(iso.size)}`,
      primaryButton: {
        value: '取消',
        action: () => { }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: async () => {
          try {
            await fs.unlink(iso.path)
            hilog.info(0x0000, 'ISO_MANAGER', 'ISO 已删除: %{public}s', iso.name)
            await this.refreshIsoList()
          } catch (e) {
            this.errorMessage = '删除失败: ' + (e as Error).message
          }
        }
      }
    })
  }

  // 格式化文件大小
  private formatSize(bytes: number): string {
    if (bytes < 1024) return bytes + ' B'
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB'
    return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB'
  }

  // 格式化时间
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('ISO 镜像管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('刷新')
          .onClick(() => this.refreshIsoList())
          .margin({ right: 8 })
        Button('添加 ISO')
          .onClick(() => this.addIso())
          .enabled(!this.isCopying)
      }
      .width('100%')
      .padding(16)

      // 存储统计
      Row() {
        Text(`共 ${this.isoFiles.length} 个镜像，占用 ${this.formatSize(this.totalSize)}`)
          .fontSize(14)
          .fontColor(Color.Gray)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 复制进度
      if (this.isCopying) {
        Column() {
          Text(`正在复制... ${this.copyProgress}%`)
            .fontSize(14)
          Progress({ value: this.copyProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F5F5F5')
      }

      // 错误提示
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor(Color.Red)
          .padding(16)
      }

      // 加载中
      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .margin(20)
      }

      // ISO 列表
      if (!this.isLoading && this.isoFiles.length === 0) {
        Column() {
          Text('暂无 ISO 镜像')
            .fontSize(16)
            .fontColor(Color.Gray)
          Text('点击"添加 ISO"从设备存储导入')
            .fontSize(14)
            .fontColor(Color.Gray)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(40)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.isoFiles, (iso: IsoFileInfo) => {
            ListItem() {
              Row() {
                // ISO 图标
                Image($r('app.media.startIcon'))
                  .width(40)
                  .height(40)
                  .margin({ right: 12 })

                // 文件信息
                Column() {
                  Text(iso.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(this.formatSize(iso.size))
                      .fontSize(12)
                      .fontColor(Color.Gray)
                    Text(' | ')
                      .fontSize(12)
                      .fontColor(Color.Gray)
                    Text(this.formatTime(iso.modifiedTime))
                      .fontSize(12)
                      .fontColor(Color.Gray)
                  }
                  .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                // 删除按钮
                Button('删除')
                  .fontColor(Color.Red)
                  .backgroundColor(Color.Transparent)
                  .onClick(() => this.deleteIso(iso))
              }
              .width('100%')
              .padding(12)
              .backgroundColor(Color.White)
              .borderRadius(8)
            }
            .margin({ left: 16, right: 16, bottom: 8 })
          })
        }
        .width('100%')
        .layoutWeight(1)
      }

      // 底部提示
      Text('提示：ISO 文件存储在应用沙箱中，卸载应用会清除所有镜像')
        .fontSize(12)
        .fontColor(Color.Gray)
        .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}

