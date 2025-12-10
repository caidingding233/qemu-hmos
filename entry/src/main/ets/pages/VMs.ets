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
  // 可选：用于显示的系统/架构标签
  systemCamp?: string;
  cpuCamp?: string;
}

@Entry
@Component
struct VMsPage {
  @State vms: VmMeta[] = [];
  @State showCreateDialog: boolean = false;
  @State loading: boolean = false;
  @State error: string = '';
  @State searchText: string = '';
  
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
      // 读取存储的配置，缺省时给安全默认值
      const cpu = vm.cpuCount && vm.cpuCount > 0 ? vm.cpuCount : 2;
      const mem = vm.memoryMB && vm.memoryMB > 0 ? vm.memoryMB : 2048;
      const disk = vm.diskSizeGB && vm.diskSizeGB > 0 ? vm.diskSizeGB : 32;
      const success = qemu.startVm({
        name: vm.name,
        isoPath: vm.isoPath,
        diskSizeGB: disk,
        memoryMB: mem,
        cpuCount: cpu,
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

  private getFilteredVms(): VmMeta[] {
    const keyword = this.searchText.trim().toLowerCase();
    if (!keyword) return this.vms;
    return this.vms.filter(vm => vm.name.toLowerCase().includes(keyword) || vm.osType.toLowerCase().includes(keyword));
  }

  /**
   * 获取系统阵营显示名称
   * 优先使用真实值，没有时从 osType 推导
   */
  private getSystemCamp(vm: VmMeta): string {
    // 真实值映射表
    const campDisplayMap: Record<string, string> = {
      'windows': 'Windows',
      'linux': 'Linux',
      'bsd': 'BSD',
      'harmonyos': 'HarmonyOS',
      'macos': 'macOS',
      'other': 'Other'
    };
    
    // 优先使用真实值
    if (vm.systemCamp) {
      return campDisplayMap[vm.systemCamp] || vm.systemCamp;
    }
    
    // 推导逻辑
    const os = vm.osType.toLowerCase();
    if (os.includes('win')) return 'Windows';
    if (os.includes('mac') || os.includes('darwin')) return 'macOS';
    if (os.includes('harmony') || os.includes('hmos') || os.includes('ohos')) return 'HarmonyOS';
    if (os.includes('bsd') || os.includes('freebsd')) return 'BSD';
    if (os.includes('linux') || os.includes('ubuntu') || os.includes('debian') || 
        os.includes('fedora') || os.includes('centos') || os.includes('arch') ||
        os.includes('manjaro') || os.includes('mint')) return 'Linux';
    return 'Other';
  }

  /**
   * 获取 CPU 架构显示名称
   * 优先使用真实值，没有时从配置推导
   */
  private getCpuCamp(vm: VmMeta): string {
    // 真实值映射表
    const cpuDisplayMap: Record<string, string> = {
      'aarch64': 'ARM64',
      'x86_64': 'x86_64',
      'i386': 'x86',
      'riscv64': 'RISC-V',
      'other': 'Other'
    };
    
    // 优先使用真实值
    if (vm.cpuCamp) {
      return cpuDisplayMap[vm.cpuCamp] || vm.cpuCamp;
    }
    
    // 推导逻辑：从 config.archType 获取，或默认 ARM64
    if (vm.config?.archType) {
      const arch = vm.config.archType.toLowerCase();
      if (arch.includes('aarch64') || arch.includes('arm64')) return 'ARM64';
      if (arch.includes('x86_64') || arch.includes('amd64')) return 'x86_64';
      if (arch.includes('i386') || arch.includes('x86') || arch.includes('i686')) return 'x86';
      if (arch.includes('riscv')) return 'RISC-V';
    }
    
    // 默认 ARM64（鸿蒙设备主流架构）
    return 'ARM64';
  }

  build() {
    Row() {
      // 左侧导航
      Column() {
        Row() {
          Text('≡')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .padding(12)
        }
        .margin({ bottom: 12 })
        Column() {
          Text('👤')
            .fontSize(20)
            .padding({ top: 8, bottom: 4 })
          Text('虚拟机')
            .fontSize(14)
            .fontColor('#1A73E8')
            .padding({ bottom: 12 })
          Text('⚙')
            .fontSize(18)
            .padding({ top: 8, bottom: 4 })
          Text('Apps')
            .fontSize(14)
            .fontColor('#888888')
            .padding({ bottom: 12 })
          Text('👥')
            .fontSize(18)
            .padding({ top: 8, bottom: 4 })
          Text('我的')
            .fontSize(14)
            .fontColor('#888888')
        }
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
        Text('添加..')
          .fontSize(14)
          .fontColor('#1A73E8')
          .padding({ bottom: 20 })
      }
      .width(92)
      .height('100%')
      .backgroundColor('#F7F9FA')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)

      // 中间列表区
      Column() {
        Row() {
          TextInput({ placeholder: '搜索虚拟机的名字', text: this.searchText })
            .border({ color: '#E0E0E0', width: 1 })
            .borderRadius(24)
            .height(40)
            .padding({ left: 12, right: 12 })
            .width('70%')
            .onChange((val: string) => this.searchText = val)
          Blank()
          Button('＋ 新建')
            .backgroundColor('#1A73E8')
            .fontColor(Color.White)
            .borderRadius(20)
            .height(36)
            .padding({ left: 14, right: 14 })
            .onClick(() => this.createDialogController.open())
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 12, right: 12 })

        if (this.error) {
          Text(this.error)
            .fontSize(14)
            .fontColor(Color.Red)
            .padding(10)
            .backgroundColor('#FFEBEE')
            .borderRadius(8)
            .margin({ left: 12, right: 12, bottom: 8 })
        }

        Scroll() {
          Column() {
            ForEach(this.getFilteredVms(), (vm: VmMeta) => {
              Column() {
                Row() {
                  Text('★')
                    .fontSize(18)
                    .fontColor('#1A73E8')
                    .margin({ right: 8 })
                  Column() {
                    Text(vm.name)
                      .fontSize(18)
                      .fontWeight(FontWeight.Medium)
                    Text(`${vm.osType} · ${vm.cpuCount}核 · ${vm.memoryMB}MB · ${vm.diskSizeGB}GB`)
                      .fontSize(14)
                      .fontColor('#7A7A7A')
                    Row() {
                      Text(this.getSystemCamp(vm))
                        .fontSize(12)
                        .fontColor('#1A73E8')
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .backgroundColor('#E8F1FF')
                        .borderRadius(10)
                        .margin({ right: 6 })
                      Text(this.getCpuCamp(vm))
                        .fontSize(12)
                        .fontColor('#00897B')
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .backgroundColor('#E0F2F1')
                        .borderRadius(10)
                    }
                  }
                  Blank()
                  Text(this.getStatusText(vm.status))
                    .fontSize(14)
                    .fontColor(this.getStatusColor(vm.status))
                }
                .width('100%')
                .padding({ top: 10, bottom: 10, left: 14, right: 14 })
                .onClick(() => this.startVM(vm))
              }
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .margin({ bottom: 8, left: 8, right: 8 })
              .shadow({ radius: 6, color: '#00000010' })
            })

            if (this.getFilteredVms().length === 0) {
              Column() {
                Text('暂无虚拟机')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .margin({ bottom: 6 })
                Text('点击右上角 “＋ 新建” 来创建虚拟机')
                  .fontSize(14)
                  .fontColor('#7A7A7A')
              }
              .width('100%')
              .height(180)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .margin({ top: 12, left: 12, right: 12 })
              .shadow({ radius: 6, color: '#00000010' })
            }
          }
          .width('100%')
          .padding({ bottom: 12 })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('30%')
      .height('100%')
      .backgroundColor('#F0F2F5')

      // 右侧内容占位
      Column() {
        if (this.error === '') {
          Text('请选择左侧虚拟机开始')
            .fontSize(16)
            .fontColor('#7A7A7A')
        } else {
          Text(this.error)
            .fontSize(14)
            .fontColor(Color.Red)
            .padding(12)
            .backgroundColor('#FFEBEE')
            .borderRadius(8)
            .margin({ bottom: 12 })
        }
        Blank()
      }
      .layoutWeight(1)
      .height('100%')
      .padding(24)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ECEFF1')
  }
}
