// 全局类型声明文件
declare module 'qemu_hmos' {
  interface QemuModule {
    // 基础功能
    version(): string;
    enableJit(): boolean;
    kvmSupported(): boolean;
    
    // VM管理
    startVm(config: {
      name: string;
      isoPath?: string;
      diskSizeGB?: number;
      memoryMB?: number;
      cpuCount?: number;
      accel?: string;
      display?: string;
      nographic?: boolean;
    }): boolean;
    
    stopVm(vmName: string): boolean;
    getVmStatus(vmName: string): string;
    getVmLogs(vmName: string, startLine?: number): string[];
    
    // 核心库诊断
    checkCoreLib(): {
      loaded: boolean;
      foundLd: boolean;
      foundSelfDir: boolean;
      selfDir: string;
      existsFilesPath: boolean;
      filesPath: string;
      foundFiles: boolean;
      errLd?: string;
      errSelfDir?: string;
      errFiles?: string;
      symFound?: boolean;
      symErr?: string;
    };
    
    // RDP客户端
    createRdpClient(): { id: string };
    connectRdp(clientId: string, config: {
      host: string;
      port: number;
      username: string;
      password: string;
      width?: number;
      height?: number;
    }): number;
    disconnectRdp(clientId: string): number;
    getRdpStatus(clientId: string): number;
    destroyRdpClient(clientId: string): number;
    
    // VNC客户端
    vncAvailable(): boolean;
    vncCreate(): number;
    vncConnect(id: number, host: string, port: number): boolean;
    vncDisconnect(id: number): boolean;
    vncGetFrame(id: number): {
      width: number;
      height: number;
      pixels: ArrayBuffer;
    } | null;
    
    // 测试和诊断
    testFunction(): boolean;
    getModuleInfo(): {
      name: string;
      version: string;
      status: string;
    };
  }
  
  const qemu: QemuModule;
  export default qemu;
}

declare module '@ohos.arkui.advanced' {
  export class CustomDialogController {
    constructor();
    open(): void;
    close(): void;
  }
}

