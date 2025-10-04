import { router } from '@kit.ArkUI';
import { DownloadManager, DownloadTask, DownloadStatus } from '../components/DownloadManager';

@Entry
@Component
struct DownloadPage {
  @State downloadManager: DownloadManager = DownloadManager.getInstance();
  @State tasks: DownloadTask[] = [];
  @State showAddDialog: boolean = false;
  @State newDownloadUrl: string = '';
  @State newDownloadFilename: string = '';

  aboutToAppear() {
    this.loadTasks();
  }

  private loadTasks() {
    this.tasks = this.downloadManager.getAllTasks();
  }

  private async addDownload() {
    if (!this.newDownloadUrl.trim()) {
      promptAction.showToast({ message: '请输入下载链接' });
      return;
    }

    const filename = this.newDownloadFilename.trim() || this.extractFilenameFromUrl(this.newDownloadUrl);
    const localPath = `/data/storage/el2/base/haps/entry/files/downloads/${filename}`;

    try {
      await this.downloadManager.addTask(this.newDownloadUrl, filename, localPath);
      this.newDownloadUrl = '';
      this.newDownloadFilename = '';
      this.showAddDialog = false;
      this.loadTasks();
      promptAction.showToast({ message: '下载任务已添加' });
    } catch (error) {
      promptAction.showToast({ message: `添加下载失败: ${error}` });
    }
  }

  private extractFilenameFromUrl(url: string): string {
    const urlObj = new URL(url);
    const pathname = urlObj.pathname;
    const filename = pathname.split('/').pop() || 'download';
    return filename;
  }

  private pauseTask(taskId: string) {
    this.downloadManager.pauseTask(taskId);
    this.loadTasks();
  }

  private resumeTask(taskId: string) {
    this.downloadManager.resumeTask(taskId);
    this.loadTasks();
  }

  private cancelTask(taskId: string) {
    this.downloadManager.cancelTask(taskId);
    this.loadTasks();
  }

  private getStatusText(status: DownloadStatus): string {
    switch (status) {
      case DownloadStatus.PENDING: return '等待中';
      case DownloadStatus.DOWNLOADING: return '下载中';
      case DownloadStatus.PAUSED: return '已暂停';
      case DownloadStatus.COMPLETED: return '已完成';
      case DownloadStatus.FAILED: return '失败';
      case DownloadStatus.CANCELLED: return '已取消';
      default: return '未知';
    }
  }

  private getStatusColor(status: DownloadStatus): string {
    switch (status) {
      case DownloadStatus.PENDING: return '#FFA500';
      case DownloadStatus.DOWNLOADING: return '#4CAF50';
      case DownloadStatus.PAUSED: return '#FF9800';
      case DownloadStatus.COMPLETED: return '#2196F3';
      case DownloadStatus.FAILED: return '#F44336';
      case DownloadStatus.CANCELLED: return '#9E9E9E';
      default: return '#9E9E9E';
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Button('返回')
          .onClick(() => router.back())
          .margin({ right: 16 })
        
        Text('下载管理')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .flexGrow(1)
        
        Button('添加')
          .onClick(() => this.showAddDialog = true)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#F8F9FA')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      // 下载列表
      if (this.tasks.length === 0) {
        Column() {
          Image($r('app.media.ic_download'))
            .width(64)
            .height(64)
            .opacity(0.5)
            .margin({ bottom: 16 })
          
          Text('暂无下载任务')
            .fontSize(16)
            .fontColor('#666666')
            .margin({ bottom: 8 })
          
          Text('点击右上角"添加"按钮开始下载')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.tasks, (task: DownloadTask) => {
            ListItem() {
              Column() {
                // 文件名和状态
                Row() {
                  Text(task.filename)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1A1A1A')
                    .flexGrow(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  
                  Text(this.getStatusText(task.status))
                    .fontSize(12)
                    .fontColor(this.getStatusColor(task.status))
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(this.getStatusColor(task.status) + '20')
                    .borderRadius(4)
                }
                .width('100%')
                .margin({ bottom: 8 })

                // 进度条
                if (task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.PAUSED) {
                  Progress({ value: task.progress, total: 100 })
                    .width('100%')
                    .height(4)
                    .color('#4CAF50')
                    .backgroundColor('#E0E0E0')
                    .margin({ bottom: 8 })
                }

                // 下载信息
                Row() {
                  Text(`${DownloadManager.formatFileSize(task.downloadedSize)} / ${DownloadManager.formatFileSize(task.totalSize)}`)
                    .fontSize(12)
                    .fontColor('#666666')
                  
                  if (task.status === DownloadStatus.DOWNLOADING) {
                    Text(` ${DownloadManager.formatFileSize(task.speed)}/s`)
                      .fontSize(12)
                      .fontColor('#666666')
                      .margin({ left: 8 })
                    
                    if (task.eta > 0) {
                      Text(` 剩余 ${DownloadManager.formatTime(task.eta)}`)
                        .fontSize(12)
                        .fontColor('#666666')
                        .margin({ left: 8 })
                    }
                  }
                }
                .width('100%')
                .margin({ bottom: 8 })

                // 操作按钮
                Row() {
                  if (task.status === DownloadStatus.DOWNLOADING) {
                    Button('暂停')
                      .onClick(() => this.pauseTask(task.id))
                      .fontSize(12)
                      .height(32)
                      .margin({ right: 8 })
                  } else if (task.status === DownloadStatus.PAUSED) {
                    Button('继续')
                      .onClick(() => this.resumeTask(task.id))
                      .fontSize(12)
                      .height(32)
                      .margin({ right: 8 })
                  } else if (task.status === DownloadStatus.FAILED) {
                    Button('重试')
                      .onClick(() => this.resumeTask(task.id))
                      .fontSize(12)
                      .height(32)
                      .margin({ right: 8 })
                  }
                  
                  if (task.status !== DownloadStatus.COMPLETED) {
                    Button('取消')
                      .onClick(() => this.cancelTask(task.id))
                      .fontSize(12)
                      .height(32)
                      .backgroundColor('#F44336')
                      .fontColor(Color.White)
                  }
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
              }
              .width('100%')
              .padding(16)
              .backgroundColor(Color.White)
              .borderRadius(8)
              .margin({ bottom: 8 })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')

    // 添加下载对话框
    if (this.showAddDialog) {
      Column() {
        Column() {
          Text('添加下载')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 20 })

          TextInput({ placeholder: '请输入下载链接' })
            .value(this.newDownloadUrl)
            .onChange((value: string) => this.newDownloadUrl = value)
            .margin({ bottom: 16 })

          TextInput({ placeholder: '文件名（可选）' })
            .value(this.newDownloadFilename)
            .onChange((value: string) => this.newDownloadFilename = value)
            .margin({ bottom: 20 })

          Row() {
            Button('取消')
              .onClick(() => this.showAddDialog = false)
              .flexGrow(1)
              .margin({ right: 8 })

            Button('确定')
              .onClick(() => this.addDownload())
              .flexGrow(1)
              .backgroundColor('#4CAF50')
              .fontColor(Color.White)
          }
          .width('100%')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(Color.White)
        .borderRadius(8)
        .margin(16)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
