/**
 * RDP 驱动器映射管理器
 * 管理 App 沙箱与 VM 之间的双向文件共享
 * 
 * 沙箱结构:
 * /data/storage/el2/base/files/
 * ├── vm_disks/
 * │   └── {VM名称}/
 * │       └── shared/          <- 通过 virtio-9p 挂载到 VM
 * └── onedrive/
 *     └── ...                  <- 从 VM OneDrive 复制来的文件
 */

import fs from '@ohos.file.fs';
import fileIo from '@ohos.fileio';

// 共享目录配置
export interface SharedDirectory {
  id: string;
  vmName: string;
  hostPath: string;           // 鸿蒙沙箱路径
  guestMountPoint: string;    // VM 内挂载点 (如 \\VIOSRV\shared)
  guestDriveLetter?: string;  // RDP 重定向盘符 (如 Z:)
  enabled: boolean;
  readOnly: boolean;
  description: string;
}

// 文件传输任务
export interface FileTransferTask {
  id: string;
  sourcePath: string;
  targetPath: string;
  direction: 'host_to_guest' | 'guest_to_host';
  status: 'pending' | 'transferring' | 'completed' | 'failed';
  progress: number;
  totalSize: number;
  transferredSize: number;
  error?: string;
}

// 驱动器管理配置
export interface DriveManagerConfig {
  baseDirectory: string;      // 基础目录
  vmDisksPath: string;        // VM 磁盘文件目录
  oneDrivePath: string;       // OneDrive 缓存目录
  enableVirtio9p: boolean;    // 启用 virtio-9p
  enableRDPRedirect: boolean; // 启用 RDP 驱动器重定向
}

export class RDPDriveManager {
  private static instance: RDPDriveManager;
  private config: DriveManagerConfig;
  private sharedDirectories: Map<string, SharedDirectory> = new Map();
  private transferTasks: Map<string, FileTransferTask> = new Map();

  private constructor() {
    this.config = {
      baseDirectory: '/data/storage/el2/base/files',
      vmDisksPath: '/data/storage/el2/base/files/vm_disks',
      oneDrivePath: '/data/storage/el2/base/files/onedrive',
      enableVirtio9p: true,
      enableRDPRedirect: true
    };
  }

  public static getInstance(): RDPDriveManager {
    if (!RDPDriveManager.instance) {
      RDPDriveManager.instance = new RDPDriveManager();
    }
    return RDPDriveManager.instance;
  }

  /**
   * 初始化 VM 的共享目录
   */
  public async initializeVMSharedDirectory(vmName: string): Promise<boolean> {
    try {
      const sharedPath = `${this.config.vmDisksPath}/${vmName}/shared`;
      
      // 创建目录结构
      await this.ensureDirectoryExists(sharedPath);
      
      // 注册共享目录
      const sharedDir: SharedDirectory = {
        id: `shared-${vmName}`,
        vmName: vmName,
        hostPath: sharedPath,
        guestMountPoint: '\\\\VIOSRV\\shared',
        guestDriveLetter: 'Z:',
        enabled: true,
        readOnly: false,
        description: `${vmName} 的共享目录`
      };
      
      this.sharedDirectories.set(sharedDir.id, sharedDir);
      
      console.info(`[RDPDriveManager] Initialized shared directory for ${vmName}: ${sharedPath}`);
      return true;
    } catch (e) {
      console.error(`[RDPDriveManager] Failed to initialize shared directory for ${vmName}:`, e);
      return false;
    }
  }

  /**
   * 初始化 OneDrive 缓存目录
   */
  public async initializeOneDriveCache(): Promise<boolean> {
    try {
      await this.ensureDirectoryExists(this.config.oneDrivePath);
      console.info(`[RDPDriveManager] OneDrive cache directory initialized: ${this.config.oneDrivePath}`);
      return true;
    } catch (e) {
      console.error('[RDPDriveManager] Failed to initialize OneDrive cache:', e);
      return false;
    }
  }

  /**
   * 确保目录存在
   */
  private async ensureDirectoryExists(path: string): Promise<void> {
    try {
      const stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        throw new Error(`${path} exists but is not a directory`);
      }
    } catch (e) {
      // 目录不存在，创建它
      fs.mkdirSync(path, true);
      console.info(`[RDPDriveManager] Created directory: ${path}`);
    }
  }

  /**
   * 获取 VM 的共享目录路径
   */
  public getVMSharedPath(vmName: string): string {
    return `${this.config.vmDisksPath}/${vmName}/shared`;
  }

  /**
   * 获取 OneDrive 缓存路径
   */
  public getOneDriveCachePath(): string {
    return this.config.oneDrivePath;
  }

  /**
   * 生成 QEMU virtio-9p 参数
   */
  public generateVirtio9pArgs(vmName: string): string[] {
    if (!this.config.enableVirtio9p) {
      return [];
    }

    const sharedPath = this.getVMSharedPath(vmName);
    
    return [
      '-virtfs',
      `local,path=${sharedPath},mount_tag=shared,security_model=mapped-xattr,id=shared0`
    ];
  }

  /**
   * 生成 RDP 驱动器重定向参数 (用于 FreeRDP)
   */
  public generateRDPDriveArgs(vmName: string): string[] {
    if (!this.config.enableRDPRedirect) {
      return [];
    }

    const args: string[] = [];
    
    // 添加 VM 共享目录
    const sharedDir = this.sharedDirectories.get(`shared-${vmName}`);
    if (sharedDir && sharedDir.enabled) {
      args.push(`/drive:shared,${sharedDir.hostPath}`);
    }
    
    // 添加 OneDrive 缓存目录
    args.push(`/drive:onedrive,${this.config.oneDrivePath}`);
    
    return args;
  }

  /**
   * 复制文件从宿主到 VM 共享目录
   */
  public async copyToVMShared(vmName: string, sourcePath: string, targetFileName?: string): Promise<boolean> {
    try {
      const sharedPath = this.getVMSharedPath(vmName);
      const fileName = targetFileName || this.getFileName(sourcePath);
      const targetPath = `${sharedPath}/${fileName}`;
      
      // 创建传输任务
      const task = this.createTransferTask(sourcePath, targetPath, 'host_to_guest');
      
      // 执行复制
      await this.copyFile(sourcePath, targetPath, task);
      
      console.info(`[RDPDriveManager] Copied ${sourcePath} to ${targetPath}`);
      return true;
    } catch (e) {
      console.error('[RDPDriveManager] Copy to VM shared failed:', e);
      return false;
    }
  }

  /**
   * 从 VM 共享目录复制文件到 OneDrive 缓存
   */
  public async copyFromVMSharedToOneDrive(vmName: string, fileName: string): Promise<boolean> {
    try {
      const sourcePath = `${this.getVMSharedPath(vmName)}/${fileName}`;
      const targetPath = `${this.config.oneDrivePath}/${fileName}`;
      
      // 创建传输任务
      const task = this.createTransferTask(sourcePath, targetPath, 'guest_to_host');
      
      // 执行复制
      await this.copyFile(sourcePath, targetPath, task);
      
      console.info(`[RDPDriveManager] Copied ${sourcePath} to OneDrive cache`);
      return true;
    } catch (e) {
      console.error('[RDPDriveManager] Copy from VM shared failed:', e);
      return false;
    }
  }

  /**
   * 列出 VM 共享目录内容
   */
  public async listVMSharedFiles(vmName: string): Promise<string[]> {
    try {
      const sharedPath = this.getVMSharedPath(vmName);
      const files: string[] = [];
      
      const dir = fs.opendirSync(sharedPath);
      let dirent = dir.readSync();
      while (dirent) {
        files.push(dirent.name);
        dirent = dir.readSync();
      }
      dir.closeSync();
      
      return files;
    } catch (e) {
      console.error('[RDPDriveManager] List shared files failed:', e);
      return [];
    }
  }

  /**
   * 列出 OneDrive 缓存内容
   */
  public async listOneDriveCacheFiles(): Promise<string[]> {
    try {
      const files: string[] = [];
      
      const dir = fs.opendirSync(this.config.oneDrivePath);
      let dirent = dir.readSync();
      while (dirent) {
        files.push(dirent.name);
        dirent = dir.readSync();
      }
      dir.closeSync();
      
      return files;
    } catch (e) {
      console.error('[RDPDriveManager] List OneDrive cache failed:', e);
      return [];
    }
  }

  /**
   * 删除 VM 共享目录中的文件
   */
  public async deleteFromVMShared(vmName: string, fileName: string): Promise<boolean> {
    try {
      const filePath = `${this.getVMSharedPath(vmName)}/${fileName}`;
      fs.unlinkSync(filePath);
      console.info(`[RDPDriveManager] Deleted ${filePath}`);
      return true;
    } catch (e) {
      console.error('[RDPDriveManager] Delete failed:', e);
      return false;
    }
  }

  /**
   * 获取共享目录状态
   */
  public getSharedDirectoryStatus(vmName: string): 'active' | 'inactive' | 'error' {
    const sharedDir = this.sharedDirectories.get(`shared-${vmName}`);
    if (!sharedDir) {
      return 'error';
    }
    
    try {
      const stat = fs.statSync(sharedDir.hostPath);
      return stat.isDirectory() ? 'active' : 'error';
    } catch (e) {
      return 'inactive';
    }
  }

  /**
   * 获取传输任务列表
   */
  public getTransferTasks(): FileTransferTask[] {
    return Array.from(this.transferTasks.values());
  }

  /**
   * 获取诊断信息
   */
  public getDiagnostics(): string[] {
    const diagnostics: string[] = [];
    
    diagnostics.push(`基础目录: ${this.config.baseDirectory}`);
    diagnostics.push(`VM 磁盘目录: ${this.config.vmDisksPath}`);
    diagnostics.push(`OneDrive 缓存: ${this.config.oneDrivePath}`);
    diagnostics.push(`Virtio-9p: ${this.config.enableVirtio9p ? '启用' : '禁用'}`);
    diagnostics.push(`RDP 重定向: ${this.config.enableRDPRedirect ? '启用' : '禁用'}`);
    diagnostics.push(`共享目录数量: ${this.sharedDirectories.size}`);
    
    for (const [id, dir] of this.sharedDirectories) {
      const status = this.getSharedDirectoryStatus(dir.vmName);
      diagnostics.push(`  ${dir.vmName}: ${dir.hostPath} (${status})`);
    }
    
    return diagnostics;
  }

  // === 私有辅助方法 ===

  private getFileName(path: string): string {
    const parts = path.split('/');
    return parts[parts.length - 1] || 'unknown';
  }

  private createTransferTask(source: string, target: string, direction: 'host_to_guest' | 'guest_to_host'): FileTransferTask {
    const task: FileTransferTask = {
      id: Date.now().toString(),
      sourcePath: source,
      targetPath: target,
      direction,
      status: 'pending',
      progress: 0,
      totalSize: 0,
      transferredSize: 0
    };
    
    this.transferTasks.set(task.id, task);
    return task;
  }

  private async copyFile(source: string, target: string, task: FileTransferTask): Promise<void> {
    task.status = 'transferring';
    
    try {
      // 获取源文件大小
      const stat = fs.statSync(source);
      task.totalSize = stat.size;
      
      // 复制文件
      fs.copyFileSync(source, target);
      
      task.transferredSize = task.totalSize;
      task.progress = 100;
      task.status = 'completed';
    } catch (e) {
      task.status = 'failed';
      task.error = e instanceof Error ? e.message : String(e);
      throw e;
    }
  }
}
