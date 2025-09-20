export interface VMConfig {
  name: string;
  isoPath?: string;
  diskSizeGB?: number;
  memoryMB?: number;
  cpuCount?: number;
  accel?: string;
  display?: string;
  nographic?: boolean;
}

export interface VMStatus {
  name: string;
  status: 'creating' | 'preparing' | 'running' | 'stopping' | 'stopped' | 'failed';
  createdAt: string;
  diskPath: string;
  logPath: string;
}

export interface QemuAPI {
  version(): string;
  enableJit(): boolean;
  kvmSupported(): boolean;
  startVm(config: VMConfig): boolean;
  stopVm(name: string): boolean;
  getVmLogs(name: string, startLine?: number): string[];
  getVmStatus(name: string): string;
  // Diagnostics and testing (optional)
  testFunction?: () => boolean;
  checkCoreLib?: () => CoreDiag;
  // Native VNC (LibVNCClient)
  vncAvailable(): boolean;
  vncCreate(): number;
  vncConnect(id: number, host: string, port: number): boolean;
  vncDisconnect(id: number): boolean;
  vncGetFrame(id: number): VncFrame | null;
}

// VNC frame shape for native client
export interface VncFrame {
  width: number;
  height: number;
  pixels: ArrayBuffer;
}

// Module declaration for N-API native addon
declare module 'libqemu_hmos.so' {
  const qemu: QemuAPI;
  export default qemu;
}

// Diagnostics result for core library probing
export interface CoreDiag {
  loaded: boolean;
  foundLd: boolean;
  symFound?: boolean;
  selfDir: string;
  foundSelfDir: boolean;
  existsFilesPath: boolean;
  filesPath: string;
  foundFiles: boolean;
  errLd?: string;
  symErr?: string;
  errSelfDir?: string;
  errFiles?: string;
}
