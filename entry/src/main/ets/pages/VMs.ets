// 动态导入QEMU模块
let qemu: any = null;
import fs from '@ohos.file.fs'
import router from '@ohos.router'
import { VMCreateDialog } from '../components/VMCreateDialog';
// 动态导入CustomDialogController
let CustomDialogController: any = null;

// 导出VMCreateConfig接口供其他组件使用
export interface VMCreateConfig {
  name: string;
  osType: string;
  isoPath: string;
  diskSize: number;
  memory: number;
  cpuCount: number;
}

interface VmMeta {
  id: string;
  name: string;
  osType: string;
  isoPath: string;
  diskSizeGB: number;
  memoryMB: number;
  cpuCount: number;
  status: 'creating' | 'preparing' | 'running' | 'stopping' | 'stopped' | 'failed';
  createdAt: number;
}

@Entry
@Component
struct VMsPage {
  @State vms: VmMeta[] = [];
  @State showCreateDialog: boolean = false;
  @State loading: boolean = false;
  @State error: string = '';
  
  private createDialogController: CustomDialogController = new CustomDialogController({
    builder: VMCreateDialog({
      onConfirm: (config: VMCreateConfig) => this.handleCreateVM(config),
      onCancel: () => this.showCreateDialog = false
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  aboutToAppear() {
    this.initModules();
    this.loadVms();
  }

  private async initModules() {
    try {
      // 动态导入QEMU模块
      const qemuModule = await eval('import("qemu_hmos")');
      qemu = qemuModule.default;
      
      // 动态导入CustomDialogController
      const dialogModule = await eval('import("@ohos.arkui.advanced")');
      CustomDialogController = dialogModule.CustomDialogController;
    } catch (error) {
      console.error('模块动态导入失败:', error);
    }
  }

  private async loadVms() {
    try {
      const savedVms = await AppStorage.Get<string>('vms');
      if (savedVms) {
        this.vms = JSON.parse(savedVms);
        // 冷启动同步真实状态，避免误显示为“运行中”
        try {
          for (const vm of this.vms) {
            let live = 'stopped' as VmMeta['status']
            try { live = qemu.getVmStatus(vm.name) as VmMeta['status'] } catch (_) { live = 'stopped' }
            if (live !== 'running' && vm.status !== 'stopped') vm.status = 'stopped'
          }
          await this.saveVms()
        } catch (_) {}
      }
    } catch (e) {
      console.error('Failed to load VMs:', e);
    }
  }

  private async saveVms() {
    try {
      await AppStorage.Set<string>('vms', JSON.stringify(this.vms));
    } catch (e) {
      console.error('Failed to save VMs:', e);
    }
  }

  private async handleCreateVM(config: VMCreateConfig) {
    try {
      this.loading = true;
      this.error = '';
      
      const vmConfig = {
        name: config.name,
        isoPath: config.isoPath,
        diskSizeGB: config.diskSize,
        memoryMB: config.memory,
        cpuCount: config.cpuCount,
        accel: qemu.kvmSupported() ? 'kvm' : 'tcg',
        display: 'vnc=:1,websocket=5701',
        nographic: false
      } as const;
      
      const success = qemu.startVm(vmConfig);
      if (success) {
        const newVm: VmMeta = {
          id: Date.now().toString(),
          name: config.name,
          osType: config.osType,
          isoPath: config.isoPath,
          diskSizeGB: config.diskSize,
          memoryMB: config.memory,
          cpuCount: config.cpuCount,
          status: 'creating',
          createdAt: Date.now()
        };
        this.vms.push(newVm);
        await this.saveVms();
        this.showCreateDialog = false;
        // 成功启动后进入 VNC 页面
        router.pushUrl({ url: 'pages/VNCViewer', params: { vmInfo: { name: newVm.name, vncPort: 5701 } } })
          .catch((e: Error) => console.error('打开VNC失败:', e));
        this.startVMStatusMonitoring(newVm.name);
      } else {
        this.error = 'Failed to start VM';
      }
    } catch (e) {
      console.error('Create VM failed:', e);
      this.error = `Failed to create VM: ${e}`;
    } finally {
      this.loading = false;
    }
  }

  private startVMStatusMonitoring(vmName: string) {
    // 启动状态监控
    const monitorInterval = setInterval(() => {
      try {
        const status = qemu.getVmStatus(vmName);
        const vmIndex = this.vms.findIndex((vm: VmMeta) => vm.name === vmName);
        if (vmIndex !== -1) {
          this.vms[vmIndex].status = status as VmMeta['status'];
          this.saveVms();
        }
        
        // 如果VM已停止，停止监控
        if (status === 'stopped' || status === 'failed') {
          clearInterval(monitorInterval);
        }
      } catch (e) {
        console.error('Status monitoring failed:', e);
        clearInterval(monitorInterval);
      }
    }, 2000);
  }

  private startVM(vm: VmMeta) {
    try {
      const success = qemu.startVm({
        name: vm.name,
        accel: qemu.kvmSupported() ? 'kvm' : 'tcg',
        display: 'vnc=:1,websocket=5701',
        nographic: false
      });
      if (success) {
        vm.status = 'running';
        this.saveVms();
        // 进入 VNC 页面
        router.pushUrl({ url: 'pages/VNCViewer', params: { vmInfo: { name: vm.name, vncPort: 5701 } } })
          .catch((e: Error) => console.error('打开VNC失败:', e));
        this.startVMStatusMonitoring(vm.name);
      }
    } catch (e) {
      console.error('Start VM failed:', e);
      this.error = `Failed to start VM: ${e}`;
    }
  }

  private stopVM(vm: VmMeta) {
    try {
      const success = qemu.stopVm(vm.name);
      if (success) {
        vm.status = 'stopping';
        this.saveVms();
      }
    } catch (e) {
      console.error('Stop VM failed:', e);
      this.error = `Failed to stop VM: ${e}`;
    }
  }

  private async deleteVM(vm: VmMeta) {
    try {
      if (vm.status !== 'stopped' && vm.status !== 'failed') {
        this.error = '请先停止虚拟机再删除';
        return;
      }
      this.loading = true;
      this.error = '';
      // 尝试删除磁盘文件
      const vmDir = `/data/storage/el2/base/haps/entry/files/vms/${vm.name}`
      const files = ['disk.qcow2', 'qemu.log', 'vm_config.json', 'vm_status.txt']
      for (const f of files) {
        const p = `${vmDir}/${f}`
        try { await fs.unlink(p) } catch (_) { /* 忽略 */ }
      }
      try { await fs.rmdir(vmDir) } catch (_) {}
      // 从内存与存储移除
      this.vms = this.vms.filter((x: VmMeta) => x.name !== vm.name)
      await this.saveVms()
    } catch (e) {
      this.error = `删除失败: ${e}`
    } finally {
      this.loading = false;
    }
  }

  private showVMLogs(vm: VmMeta) {
    try {
      const logs = qemu.getVmLogs(vm.name);
      console.log(`VM ${vm.name} logs:`, logs);
      // 这里可以显示日志对话框
    } catch (e) {
      console.error('Get VM logs failed:', e);
    }
  }

  private getStatusColor(status: VmMeta['status']): string {
    switch (status) {
      case 'running': return '#4CAF50';
      case 'creating': case 'preparing': return '#FF9800';
      case 'stopping': return '#FF5722';
      case 'stopped': return '#9E9E9E';
      case 'failed': return '#F44336';
      default: return '#9E9E9E';
    }
  }

  private getStatusText(status: VmMeta['status']): string {
    switch (status) {
      case 'running': return '运行中';
      case 'creating': return '创建中';
      case 'preparing': return '准备中';
      case 'stopping': return '停止中';
      case 'stopped': return '已停止';
      case 'failed': return '失败';
      default: return '未知';
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('虚拟机管理')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('创建VM')
          .onClick(() => {
            this.createDialogController.open();
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .margin({ bottom: 16 })

      // 错误提示
      if (this.error) {
        Text(this.error)
          .fontSize(14)
          .fontColor(Color.Red)
          .padding(8)
          .backgroundColor(Color.Red + '20')
          .borderRadius(4)
          .margin({ bottom: 16 })
      }

      // VM列表
      List() {
        ForEach(this.vms, (vm: VmMeta) => {
          ListItem() {
            Column() {
              Row() {
                Text(vm.name)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                Blank()
                Text(this.getStatusText(vm.status))
                  .fontSize(14)
                  .fontColor(this.getStatusColor(vm.status))
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                Text(`OS: ${vm.osType}`)
                  .fontSize(14)
                  .fontColor(Color.Grey)
                Blank()
                Text(`${vm.cpuCount}核 ${vm.memoryMB}MB ${vm.diskSizeGB}GB`)
                  .fontSize(14)
                  .fontColor(Color.Grey)
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                Button('启动')
                  .onClick(() => this.startVM(vm))
                  .enabled(vm.status === 'stopped' || vm.status === 'failed')
                  .margin({ right: 8 })
                Button('停止')
                  .onClick(() => this.stopVM(vm))
                  .enabled(vm.status === 'running')
                  .margin({ right: 8 })
                Button('日志')
                  .onClick(() => this.showVMLogs(vm))
                  .margin({ right: 8 })
                Button('删除')
                  .onClick(() => this.deleteVM(vm))
                  .enabled(vm.status === 'stopped' || vm.status === 'failed')
              }
              .width('100%')
            }
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .margin({ bottom: 8 })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')
  }
}
