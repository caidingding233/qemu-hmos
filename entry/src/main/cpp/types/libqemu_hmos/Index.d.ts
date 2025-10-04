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

export interface DeviceCapabilities {
  kvmSupported: boolean;
  jitSupported: boolean;
  totalMemory: number;
  cpuCores: number;
}

export const version: () => string;
export const enableJit: () => boolean;
export const kvmSupported: () => boolean;
export const startVm: (config: VMConfig) => boolean;
export const stopVm: (name: string) => boolean;
export const getVmLogs: (name: string, startLine?: number) => string[];
export const getVmStatus: (name: string) => string;
export const getDeviceCapabilities: () => DeviceCapabilities;
export const pauseVm: (name: string) => boolean;
export const resumeVm: (name: string) => boolean;
export const createSnapshot: (name: string, snapshotName: string) => boolean;
export const restoreSnapshot: (name: string, snapshotName: string) => boolean;
export const listSnapshots: (name: string) => string[];
export const deleteSnapshot: (name: string, snapshotName: string) => boolean;

declare const _default: {
  version: typeof version;
  enableJit: typeof enableJit;
  kvmSupported: typeof kvmSupported;
  startVm: typeof startVm;
  stopVm: typeof stopVm;
  getVmLogs: typeof getVmLogs;
  getVmStatus: typeof getVmStatus;
  getDeviceCapabilities: typeof getDeviceCapabilities;
  pauseVm: typeof pauseVm;
  resumeVm: typeof resumeVm;
  createSnapshot: typeof createSnapshot;
  restoreSnapshot: typeof restoreSnapshot;
  listSnapshots: typeof listSnapshots;
  deleteSnapshot: typeof deleteSnapshot;
};
export default _default;
