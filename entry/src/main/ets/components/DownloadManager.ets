import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';

// 下载任务状态
export enum DownloadStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

// 下载任务信息
export interface DownloadTask {
  id: string;
  url: string;
  filename: string;
  localPath: string;
  totalSize: number;
  downloadedSize: number;
  status: DownloadStatus;
  progress: number;
  speed: number; // bytes per second
  eta: number; // estimated time in seconds
  retryCount: number;
  maxRetries: number;
  createdAt: string;
  updatedAt: string;
  error?: string;
}

// 下载管理器
export class DownloadManager {
  private static instance: DownloadManager;
  private tasks: Map<string, DownloadTask> = new Map();
  private activeDownloads: Set<string> = new Set();
  private maxConcurrentDownloads: number = 3;
  private downloadQueue: string[] = [];
  private isRunning: boolean = false;

  private constructor() {}

  public static getInstance(): DownloadManager {
    if (!DownloadManager.instance) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  // 添加下载任务
  public async addTask(url: string, filename: string, localPath: string): Promise<string> {
    const taskId = this.generateTaskId();
    const task: DownloadTask = {
      id: taskId,
      url,
      filename,
      localPath,
      totalSize: 0,
      downloadedSize: 0,
      status: DownloadStatus.PENDING,
      progress: 0,
      speed: 0,
      eta: 0,
      retryCount: 0,
      maxRetries: 3,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    this.tasks.set(taskId, task);
    this.downloadQueue.push(taskId);
    
    // 开始处理队列
    this.processQueue();
    
    return taskId;
  }

  // 暂停下载
  public pauseTask(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;

    if (task.status === DownloadStatus.DOWNLOADING) {
      task.status = DownloadStatus.PAUSED;
      task.updatedAt = new Date().toISOString();
      this.activeDownloads.delete(taskId);
      this.processQueue();
      return true;
    }
    return false;
  }

  // 恢复下载
  public resumeTask(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;

    if (task.status === DownloadStatus.PAUSED) {
      task.status = DownloadStatus.PENDING;
      task.updatedAt = new Date().toISOString();
      this.downloadQueue.unshift(taskId); // 添加到队列前面
      this.processQueue();
      return true;
    }
    return false;
  }

  // 取消下载
  public cancelTask(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;

    task.status = DownloadStatus.CANCELLED;
    task.updatedAt = new Date().toISOString();
    this.activeDownloads.delete(taskId);
    
    // 从队列中移除
    const index = this.downloadQueue.indexOf(taskId);
    if (index > -1) {
      this.downloadQueue.splice(index, 1);
    }

    // 删除本地文件
    this.deleteLocalFile(task.localPath);
    
    return true;
  }

  // 获取任务信息
  public getTask(taskId: string): DownloadTask | undefined {
    return this.tasks.get(taskId);
  }

  // 获取所有任务
  public getAllTasks(): DownloadTask[] {
    return Array.from(this.tasks.values());
  }

  // 处理下载队列
  private async processQueue() {
    if (this.isRunning) return;
    this.isRunning = true;

    while (this.downloadQueue.length > 0 && this.activeDownloads.size < this.maxConcurrentDownloads) {
      const taskId = this.downloadQueue.shift();
      if (taskId) {
        const task = this.tasks.get(taskId);
        if (task && task.status === DownloadStatus.PENDING) {
          this.activeDownloads.add(taskId);
          this.downloadTask(task);
        }
      }
    }

    this.isRunning = false;
  }

  // 执行下载任务
  private async downloadTask(taskId: string) {
    const task = this.tasks.get(taskId);
    if (!task) return;

    try {
      task.status = DownloadStatus.DOWNLOADING;
      task.updatedAt = new Date().toISOString();

      // 检查是否支持断点续传
      const resumeSupported = await this.checkResumeSupport(task.url);
      const startPosition = resumeSupported ? task.downloadedSize : 0;

      // 创建HTTP请求
      const request = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Range': `bytes=${startPosition}-`
        },
        connectTimeout: 30000,
        readTimeout: 60000
      };

      // 打开文件用于写入
      const file = await fileIo.open(task.localPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      
      let lastUpdateTime = Date.now();
      let lastDownloadedSize = task.downloadedSize;

      // 发送请求
      request.request(task.url, options).then((response) => {
        if (response.responseCode === 200 || response.responseCode === 206) {
          // 获取文件总大小
          const contentLength = response.header['content-length'];
          if (contentLength) {
            task.totalSize = parseInt(contentLength) + startPosition;
          }

          // 处理响应数据
          const reader = response.body?.getReader();
          if (reader) {
            this.processResponseData(reader, file, task, lastUpdateTime, lastDownloadedSize);
          }
        } else {
          throw new Error(`HTTP ${response.responseCode}: ${response.responseMessage}`);
        }
      }).catch((error) => {
        this.handleDownloadError(task, error);
      });

    } catch (error) {
      this.handleDownloadError(task, error);
    }
  }

  // 处理响应数据
  private async processResponseData(
    reader: ReadableStreamDefaultReader<Uint8Array>,
    file: fileIo.File,
    task: DownloadTask,
    lastUpdateTime: number,
    lastDownloadedSize: number
  ) {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        // 写入文件
        await fileIo.write(file.fd, value.buffer);

        // 更新任务信息
        task.downloadedSize += value.length;
        task.progress = task.totalSize > 0 ? (task.downloadedSize / task.totalSize) * 100 : 0;

        // 计算下载速度
        const now = Date.now();
        const timeDiff = (now - lastUpdateTime) / 1000;
        if (timeDiff >= 1) {
          const sizeDiff = task.downloadedSize - lastDownloadedSize;
          task.speed = sizeDiff / timeDiff;
          task.eta = task.speed > 0 ? (task.totalSize - task.downloadedSize) / task.speed : 0;
          lastUpdateTime = now;
          lastDownloadedSize = task.downloadedSize;
        }

        task.updatedAt = new Date().toISOString();

        // 检查是否完成
        if (task.totalSize > 0 && task.downloadedSize >= task.totalSize) {
          task.status = DownloadStatus.COMPLETED;
          task.progress = 100;
          task.speed = 0;
          task.eta = 0;
          task.updatedAt = new Date().toISOString();
          this.activeDownloads.delete(task.id);
          this.processQueue();
          break;
        }

        // 检查是否被暂停
        if (task.status === DownloadStatus.PAUSED) {
          break;
        }
      }
    } catch (error) {
      this.handleDownloadError(task, error);
    } finally {
      await fileIo.close(file.fd);
    }
  }

  // 处理下载错误
  private handleDownloadError(task: DownloadTask, error: any) {
    task.retryCount++;
    task.error = error.message || error.toString();
    task.updatedAt = new Date().toISOString();

    if (task.retryCount < task.maxRetries) {
      // 重试
      task.status = DownloadStatus.PENDING;
      this.downloadQueue.unshift(task.id);
    } else {
      // 失败
      task.status = DownloadStatus.FAILED;
    }

    this.activeDownloads.delete(task.id);
    this.processQueue();
  }

  // 检查是否支持断点续传
  private async checkResumeSupport(url: string): Promise<boolean> {
    try {
      const request = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.HEAD,
        connectTimeout: 10000,
        readTimeout: 10000
      };

      const response = await request.request(url, options);
      const acceptRanges = response.header['accept-ranges'];
      return acceptRanges === 'bytes';
    } catch (error) {
      return false;
    }
  }

  // 删除本地文件
  private async deleteLocalFile(filePath: string) {
    try {
      await fileIo.unlink(filePath);
    } catch (error) {
      console.error(`Failed to delete file ${filePath}:`, error);
    }
  }

  // 生成任务ID
  private generateTaskId(): string {
    return `task_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  // 格式化文件大小
  public static formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  // 格式化时间
  public static formatTime(seconds: number): string {
    if (seconds < 60) return `${Math.round(seconds)}秒`;
    if (seconds < 3600) return `${Math.round(seconds / 60)}分钟`;
    return `${Math.round(seconds / 3600)}小时`;
  }
}
