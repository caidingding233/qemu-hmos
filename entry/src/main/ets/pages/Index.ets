import hilog from '@ohos.hilog';
import common from '@ohos.app.ability.common'
import { FirmwareManager } from '../utils/FirmwareManager'
import router from '@ohos.router'
// 动态导入QEMU模块
let qemu: any = null;
import type { CoreDiag } from '../types/qemu'
import picker from '@ohos.file.picker'
import fs from '@ohos.file.fs'
import os from '@ohos.os'
import { VmStore, type VMMetaPersist } from '../managers/VmStore'


// 辅助类型：ISO 复制结果
interface CopyResult { ok: boolean; path: string }

// QEMU配置接口
interface VMConfig {
  name: string;
  archType?: 'aarch64' | 'x86_64' | 'i386';  // 架构类型
  isoPath?: string;
  diskSizeGB?: number;
  memoryMB?: number;
  cpuCount?: number;
  accel?: string;
  display?: string;
  nographic?: boolean;
}

// QEMU API接口
// 使用真实 NAPI 模块

// 模块信息接口
interface ModuleInfo {
  name: string;
  version: string;
  status: string;
}

// 本地扩展接口：仅用于类型守卫访问可选诊断方法
interface QemuDiagAPI {
  testFunction?: () => boolean
  checkCoreLib?: () => CoreDiag
  getModuleInfo?: () => ModuleInfo
}

// QEMU配置类
class QemuConfig {
  name: string = '';
  archType: 'aarch64' | 'x86_64' | 'i386' = 'aarch64';  // 默认 ARM64
  osType: string = 'Windows';
  diskSizeGB: number = 64;
  memoryMB: number = 6144;
  cpuCount: number = 4;
  isoPath?: string;
}

// CoreDiag 类型由 ../types/qemu 提供

// VM元数据类
class VMMeta {
  id: string = '';
  name: string = '';
  osType: string = 'Windows';
  status: 'creating' | 'preparing' | 'running' | 'stopping' | 'stopped' | 'failed' | 'starting' = 'stopped';
  createdAt: number = Date.now();
  config: QemuConfig = new QemuConfig();
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State testResult: string = '正在检测系统能力...';
  @State vms: VMMeta[] = [];
  @State showCreateDialog: boolean = false;
  @State newVMName: string = '';
  @State newVMOS: string = 'Windows';
  @State newVMArchType: 'aarch64' | 'x86_64' | 'i386' = 'aarch64';
  @State newVMDiskSize: number = 64;
  @State newVMMemory: number = 6144;
  @State newVMCPU: number = 4;
  @State newVMISOPath: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State showStartModeDialog: boolean = false;
  @State startTargetVM: VMMeta | null = null;

  private store?: VmStore;

  aboutToAppear() {
    // 动态导入QEMU模块
    this.initQemuModule();
    // 初始化持久化并加载
    this.initStoreAndLoad();
    // 触发一次系统能力检测
    this.testQemuFunctions();
  }

  private async initQemuModule() {
    try {
      // 动态导入QEMU模块
      const qemuModule = await eval('import("qemu_hmos")');
      qemu = qemuModule.default;
      hilog.info(0x0000, 'QEMU_TEST', 'QEMU模块动态导入成功');
    } catch (error) {
      hilog.error(0x0000, 'QEMU_TEST', 'QEMU模块动态导入失败: %{public}s', (error as Error).message);
    }
  }

  private async initStoreAndLoad() {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      this.store = new VmStore(ctx)
      const list = await this.store.loadAll()
      this.vms = list.map((p: VMMetaPersist) => {
        const m = new VMMeta()
        m.id = p.id
        m.name = p.name
        m.osType = p.osType
        m.createdAt = p.createdAt
        m.status = p.status ?? 'stopped'
        const cfg = new QemuConfig()
        cfg.name = p.config.name
        cfg.osType = p.config.osType
        cfg.diskSizeGB = p.config.diskSizeGB
        cfg.memoryMB = p.config.memoryMB
        cfg.cpuCount = p.config.cpuCount
        cfg.isoPath = p.config.isoPath || ''
        m.config = cfg
        return m
      })
      // 冷启动状态重同步：避免上次异常退出/重装后仍显示为“运行中”
      // 通过 NAPI 查询真实状态并校正到 stopped（若当前进程并未持有运行线程）
      try {
        for (const vm of this.vms) {
          let live: string = 'stopped'
          try { live = qemu.getVmStatus(vm.name) as string } catch (_e) { live = 'stopped' }
          const normalized = live === 'running' ? 'running' : 'stopped'
          if (vm.status !== normalized) vm.status = normalized
        }
        await this.saveAllVMs()
      } catch (_e) { /* ignore */ }
    } catch (e) {
      console.error('加载VM列表失败: ' + (e as Error).message)
    }
  }

  // 测试QEMU NAPI功能
  async testQemuFunctions() {
    try {
      this.isLoading = true;
      this.errorMessage = '';
      
      // 测试版本信息
      const version: string = qemu.version();
      hilog.info(0x0000, 'QEMU_TEST', 'QEMU版本: %{public}s', version);
      
      // 测试JIT权限
      const jitEnabled: boolean = qemu.enableJit();
      hilog.info(0x0000, 'QEMU_TEST', 'JIT权限: %{public}s', jitEnabled ? '已启用' : '未启用');
      
      // 测试KVM支持
      const kvmSupported: boolean = qemu.kvmSupported();
      hilog.info(0x0000, 'QEMU_TEST', 'KVM支持: %{public}s', kvmSupported ? '支持' : '不支持');

      // 触发一次原生侧最小调用，便于观察 C++ HILOG（QEMU_CORE）
      try {
        const qd = qemu as QemuDiagAPI
        const ok: boolean = typeof qd.testFunction === 'function' ? qd.testFunction!() : false
        hilog.info(0x0000, 'QEMU_TEST', 'NAPI TestFunction 调用结果: %{public}s', ok ? 'true' : 'false')
        
        // 测试新的模块信息函数
        const qd2 = qemu as QemuDiagAPI
        if (typeof qd2.getModuleInfo === 'function') {
          const moduleInfo = qd2.getModuleInfo!()
          hilog.info(0x0000, 'QEMU_TEST', 'NAPI ModuleInfo: %{public}s', JSON.stringify(moduleInfo))
        }
      } catch (e) {
        hilog.error(0x0000, 'QEMU_TEST', 'NAPI TestFunction 调用失败: %{public}s', (e as Error).message)
      }

      // 输出核心库诊断，确认 dlopen/dlsym 可用性
      try {
        const qd = qemu as QemuDiagAPI
        const diag: CoreDiag | undefined = typeof qd.checkCoreLib === 'function' ? qd.checkCoreLib!() : undefined
        if (diag) {
          hilog.info(0x0000, 'QEMU_TEST', 'Core.loaded=%{public}s, foundSelfDir=%{public}s, symFound=%{public}s', String(diag.loaded), String(diag.foundSelfDir), String(diag.symFound))
          hilog.info(0x0000, 'QEMU_TEST', 'Core.selfDir=%{public}s, filesPath=%{public}s', diag.selfDir, diag.filesPath)
          if (diag.errLd || diag.errSelfDir || diag.errFiles) {
            hilog.error(0x0000, 'QEMU_TEST', 'Core.errLd=%{public}s, errSelfDir=%{public}s, errFiles=%{public}s', String(diag.errLd || ''), String(diag.errSelfDir || ''), String(diag.errFiles || ''))
          }
        } else {
          hilog.info(0x0000, 'QEMU_TEST', 'Core诊断接口返回空')
        }
      } catch (e) {
        hilog.error(0x0000, 'QEMU_TEST', 'Core诊断接口调用失败: %{public}s', (e as Error).message)
      }
      
      this.testResult = `QEMU ${version}\nJIT: ${jitEnabled ? '✓' : '✗'}\nKVM: ${kvmSupported ? '✓' : '✗'}`;
    } catch (error) {
      const errorMsg: string = error instanceof Error ? error.message : String(error);
      hilog.error(0x0000, 'QEMU_TEST', 'NAPI测试失败: %{public}s', errorMsg);
      this.testResult = 'NAPI测试失败，请检查模块加载';
      this.errorMessage = `NAPI错误: ${errorMsg}`;
    } finally {
      this.isLoading = false;
    }
  }

  // 占位数据移除：保持空列表，用户通过“创建”按钮添加

  // 创建新VM
  async createVM() {
    if (!this.newVMName.trim()) {
      this.errorMessage = '请输入虚拟机名称';
      return;
    }

    try {
      this.isLoading = true;
      this.errorMessage = '';
      
      const newVM = new VMMeta();
      newVM.id = Date.now().toString();
      newVM.name = this.newVMName.trim();
      newVM.osType = this.newVMOS;
      // 仅创建元数据记录，置为 stopped，避免卡在 "创建中"
      newVM.status = 'stopped';
      newVM.config = {
        name: this.newVMName.trim(),
        archType: this.newVMArchType,
        osType: this.newVMOS,
        diskSizeGB: this.newVMDiskSize,
        memoryMB: this.newVMMemory,
        cpuCount: this.newVMCPU,
        isoPath: this.newVMISOPath
      };

      this.vms.push(newVM);
      // 若指定了 ISO，尝试复制到沙箱
      if (newVM.config.isoPath && newVM.config.isoPath.length > 0) {
        const copied = await this.ensureIsoInSandbox(newVM.config.isoPath)
        if (copied.ok) {
          newVM.config.isoPath = copied.path
        } else {
          this.errorMessage = '无法复制 ISO，请手动使用 hdc 推送到 files/isos/ 后重试'
        }
      }
      // 持久化保存
      await this.saveAllVMs();
      // 关闭弹窗并复位表单
      this.showCreateDialog = false;
      this.resetCreateForm();

      // 创建后立即以安装模式启动（VNC）
      await this.doStartVM(newVM, 'install')

      hilog.info(0x0000, 'VM_CREATE', '创建VM: %{public}s', newVM.name);
    } catch (error) {
      const errorMsg: string = error instanceof Error ? error.message : String(error);
      hilog.error(0x0000, 'VM_CREATE', '创建VM失败: %{public}s', errorMsg);
      this.errorMessage = `创建失败: ${errorMsg}`;
    } finally {
      this.isLoading = false;
    }
  }

  // 启动VM
  async startVM(vm: VMMeta) {
    // 弹出模式选择（安装期VNC / 已安装RDP）
    this.startTargetVM = vm
    this.showStartModeDialog = true
  }

  private async doStartVM(vm: VMMeta, mode: 'install' | 'normal') {
    try {
      this.isLoading = true;
      this.errorMessage = '';
      vm.status = 'starting';
      hilog.info(0x0000, 'VM_START', '启动VM: %{public}s', vm.name);

      // 确保 UEFI 固件就绪
      const ok = await FirmwareManager.ensureUefi(getContext(this) as common.UIAbilityContext)
      if (!ok) {
        this.errorMessage = '缺少 UEFI 固件：请将 edk2-aarch64-code.fd 放到 rawfile 或使用 hdc 推送到 files 目录'
        vm.status = 'failed'
        this.isLoading = false
        await this.saveAllVMs();
        return
      }

      // 启动 VM
      const success: boolean = qemu.startVm({
        name: vm.name,
        archType: vm.config.archType || 'aarch64',
        isoPath: vm.config.isoPath || '',
        diskSizeGB: vm.config.diskSizeGB,
        memoryMB: vm.config.memoryMB,
        cpuCount: vm.config.cpuCount,
        accel: qemu.kvmSupported() ? 'kvm' : 'tcg,thread=multi,tb-size=128',
        display: mode === 'install' ? 'vnc=127.0.0.1:1,websocket=5701' : 'vnc=127.0.0.1:1',
        nographic: false
      })

      if (success) {
        if (mode === 'install') {
          hilog.info(0x0000, 'VM_START', '启动VNC模式，端口: 5701')
          router.pushUrl({ url: 'pages/VNCViewer', params: { vmInfo: { name: vm.name, vncPort: 5701 } } })
        } else {
          router.pushUrl({ url: 'pages/RDPViewer', params: { vmId: vm.name, vmName: vm.name, rdpHost: '127.0.0.1', rdpPort: 3390 } })
        }
        vm.status = 'running'
        hilog.info(0x0000, 'VM_START', 'VM启动成功: %{public}s', vm.name)
      } else {
        vm.status = 'failed'
        this.errorMessage = 'VM启动失败 - 请先点击"诊断依赖"检查核心库状态'
        hilog.error(0x0000, 'VM_START', 'VM启动失败，请检查诊断信息')
      }
    } catch (error) {
      vm.status = 'failed'
      const errorMsg: string = error instanceof Error ? error.message : String(error)
      this.errorMessage = `启动失败: ${errorMsg}`
    } finally {
      this.isLoading = false
      this.showStartModeDialog = false
      this.startTargetVM = null
      await this.saveAllVMs()
    }
  }

  // 停止VM
  async stopVM(vm: VMMeta) {
    try {
      this.isLoading = true;
      this.errorMessage = '';
      
      vm.status = 'stopping';
      hilog.info(0x0000, 'VM_STOP', '停止VM: %{public}s', vm.name);

      // 调用真正的NAPI停止VM
      const success: boolean = qemu.stopVm(vm.name);

      if (success) {
        // 模拟停止过程
        setTimeout(() => {
          vm.status = 'stopped';
          hilog.info(0x0000, 'VM_STOP', 'VM停止成功: %{public}s', vm.name);
          this.saveAllVMs();
        }, 1000);
      } else {
        this.errorMessage = 'VM停止失败';
        hilog.error(0x0000, 'VM_STOP', 'VM停止失败: %{public}s', vm.name);
      }
    } catch (error) {
      const errorMsg: string = error instanceof Error ? error.message : String(error);
      this.errorMessage = `停止失败: ${errorMsg}`;
      hilog.error(0x0000, 'VM_STOP', 'VM停止异常: %{public}s', errorMsg);
    } finally {
      this.isLoading = false;
      await this.saveAllVMs();
    }
  }

  // 删除VM（清理持久化与磁盘文件）
  async deleteVM(vm: VMMeta) {
    try {
      if (vm.status === 'running' || vm.status === 'starting' || vm.status === 'stopping') {
        this.errorMessage = '请先停止虚拟机再删除';
        return;
      }
      this.isLoading = true;
      this.errorMessage = '';
      // 1) 删除磁盘文件（最佳努力）
      const vmDir = `/data/storage/el2/base/haps/entry/files/vms/${vm.name}`
      const files = ['disk.qcow2', 'qemu.log', 'vm_config.json', 'vm_status.txt']
      for (const f of files) {
        const p = `${vmDir}/${f}`
        try { await fs.unlink(p) } catch (_) { /* ignore */ }
      }
      try { await fs.rmdir(vmDir) } catch (_) { /* may contain extra files; ignore */ }
      // 2) 从列表移除并持久化
      this.vms = this.vms.filter((x: VMMeta) => x.id !== vm.id)
      await this.saveAllVMs()
      hilog.info(0x0000, 'VM_DELETE', '删除VM: %{public}s', vm.name)
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e)
      this.errorMessage = `删除失败: ${msg}`
    } finally {
      this.isLoading = false
    }
  }

  private async saveAllVMs() {
    if (!this.store) return
    const list: VMMetaPersist[] = this.vms.map((vm: VMMeta) : VMMetaPersist => ({
      id: vm.id,
      name: vm.name,
      osType: vm.osType,
      status: vm.status,
      createdAt: vm.createdAt,
      config: {
        name: vm.config.name,
        osType: vm.config.osType,
        diskSizeGB: vm.config.diskSizeGB,
        memoryMB: vm.config.memoryMB,
        cpuCount: vm.config.cpuCount,
        isoPath: vm.config.isoPath || ''
      }
    }))
    await this.store.saveAll(list)
  }

  // 将选中的 ISO 复制到应用沙箱目录 files/isos/
  private async ensureIsoInSandbox(srcPath: string): Promise<CopyResult> {
    try {
      const sandboxRoot = '/data/storage/el2/base/haps/entry/files'
      if (srcPath.startsWith(sandboxRoot)) {
        return { ok: true, path: srcPath }
      }
      const name = srcPath.split('?')[0].split('/').pop() || 'image.iso'
      const dstDir = sandboxRoot + '/isos'
      const dstPath = dstDir + '/' + name
      try { await fs.mkdir(dstDir) } catch (_e) { /* 目录可能已存在 */ }
      // 逐块复制
      const src = await fs.open(srcPath, fs.OpenMode.READ_ONLY)
      const dst = await fs.open(dstPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
      const chunkSize = 1024 * 1024
      const buf = new ArrayBuffer(chunkSize)
      const u8 = new Uint8Array(buf)
      while (true) {
        const n: number = await fs.read(src.fd, buf)
        if (!n || n <= 0) break
        await fs.write(dst.fd, buf.slice(0, n))
        if (n < chunkSize) break
      }
      await fs.close(src)
      await fs.close(dst)
      return { ok: true, path: dstPath }
    } catch (e) {
      console.error('复制 ISO 失败: ' + (e as Error).message)
      return { ok: false, path: '' }
    }
  }

  // 重置创建表单
  resetCreateForm() {
    this.newVMName = '';
    this.newVMOS = 'Windows';
    this.newVMArchType = 'aarch64';
    this.newVMDiskSize = 64;
    this.newVMMemory = 6144;
    this.newVMCPU = 4;
    this.newVMISOPath = '';
  }

  // 获取状态颜色
  getStatusColor(status: string): string {
    switch (status) {
      case 'running': return '#00C853';
      case 'starting': return '#FF9800';
      case 'stopping': return '#FF9800';
      case 'stopped': return '#9E9E9E';
      case 'failed': return '#F44336';
      case 'creating': return '#2196F3';
      case 'preparing': return '#2196F3';
      default: return '#9E9E9E';
    }
  }

  // 获取状态文本
  getStatusText(status: string): string {
    switch (status) {
      case 'running': return '运行中';
      case 'starting': return '启动中';
      case 'stopping': return '停止中';
      case 'stopped': return '已停止';
      case 'failed': return '启动失败';
      case 'creating': return '创建中';
      case 'preparing': return '准备中';
      default: return '未知状态';
    }
  }

  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          Column() {
            // 顶部标题区域
            Row() {
              Column() {
                Text('虚拟机管理')
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .margin({ bottom: 4 });
                Text('QEMU功能测试')
                  .fontSize(14)
                  .fontColor('#666666')
                Row() {
                  Button('诊断依赖')
                    .type(ButtonType.Capsule)
                    .onClick(() => this.runDiagnostics())
                    .margin({ top: 8 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1);

              if (this.isLoading) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color('#007DFF');
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 16, bottom: 20 });

            // QEMU功能测试卡片
    Column() {
              Text('系统能力检测')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1A1A1A')
                .margin({ bottom: 12 });

              if (this.isLoading) {
      Row() {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color('#007DFF')
                    .margin({ right: 8 });
                  Text('正在检测...')
                    .fontSize(14)
                    .fontColor('#666666')
                }
                .margin({ bottom: 12 });
              }

              Text(this.testResult)
                .fontSize(13)
                .fontColor('#333333')
                .textAlign(TextAlign.Start)
                .backgroundColor('#F8F9FA')
                .padding(16)
                .borderRadius(12)
                .width('100%')
                .border({ width: 1, color: '#E8E8E8' });

              if (this.errorMessage) {
                Text(this.errorMessage)
                  .fontSize(12)
                  .fontColor('#F44336')
                  .margin({ top: 8 })
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .backgroundColor('#FFEBEE')
                  .borderRadius(8)
                  .width('100%');
              }
            }
            .padding(20)
            .backgroundColor(Color.White)
            .borderRadius(16)
            .margin({ left: 20, right: 20, bottom: 20 })
            .shadow({ radius: 8, color: '#00000008', offsetX: 0, offsetY: 2 });

            // 创建新虚拟机按钮
            Button('创建新虚拟机')
              .width('90%')
              .height(52)
              .backgroundColor('#007DFF')
              .fontColor(Color.White)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .borderRadius(26)
          .onClick(() => {
                this.showCreateDialog = true;
              })
              .margin({ bottom: 24 })
              .shadow({ radius: 12, color: '#007DFF40', offsetX: 0, offsetY: 4 });

            // VM列表
            if (this.vms.length > 0) {
              List() {
                ForEach(this.vms, (vm: VMMeta) => {
                  ListItem() {
                    Column() {
                      Row() {
                        Column() {
                          Text(vm.name)
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor('#1A1A1A');
                          Text(vm.osType)
          .fontSize(12)
                            .fontColor('#666666')
                            .margin({ top: 4 });
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start);

                        Column() {
                          Text(this.getStatusText(vm.status))
                            .fontSize(11)
                            .fontColor(Color.White)
                            .backgroundColor(this.getStatusColor(vm.status))
                            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                            .borderRadius(12);
                          Text(`${vm.config.cpuCount}核 ${vm.config.memoryMB / 1024}GB`)
                            .fontSize(10)
                            .fontColor('#999999')
                            .margin({ top: 6 });
                        }
                        .alignItems(HorizontalAlign.End);
                      }
                      .width('100%')
                      .margin({ bottom: 16 });

                      Row() {
                        Button(vm.status === 'running' ? '停止' : '启动')
                          .width(72)
                          .height(36)
                          .fontSize(13)
                          .backgroundColor(vm.status === 'running' ? '#FF9800' : '#00C853')
                          .fontColor(Color.White)
                          .borderRadius(18)
                          .onClick(() => {
                            if (vm.status === 'running') {
                              this.stopVM(vm);
                            } else {
                              this.startVM(vm);
                            }
                          })
                          .enabled(!this.isLoading && vm.status !== 'starting' && vm.status !== 'stopping');

                        Button('快照')
                          .width(72)
                          .height(36)
                          .fontSize(13)
                          .backgroundColor('#9C27B0')
                          .fontColor(Color.White)
                          .borderRadius(18)
                          .margin({ left: 12 })
                          .enabled(vm.status === 'running');

                        Button('删除')
                          .width(72)
                          .height(36)
                          .fontSize(13)
                          .backgroundColor('#F44336')
                          .fontColor(Color.White)
                          .borderRadius(18)
                          .margin({ left: 12 })
                          .enabled(vm.status === 'stopped')
                          .onClick(() => this.deleteVM(vm));
                      }
                      .width('100%')
                      .justifyContent(FlexAlign.Start);
                    }
                    .padding(20)
                    .backgroundColor(Color.White)
                    .borderRadius(16)
                    .margin({ left: 20, right: 20, bottom: 16 })
                    .shadow({ radius: 8, color: '#00000008', offsetX: 0, offsetY: 2 });
                  }
                });
      }
      .width('100%')
              .layoutWeight(1);
            } else {
              // 空状态
              Column() {
                Circle()
                  .width(120)
                  .height(120)
                  .fill('#E8E8E8')
                  .margin({ bottom: 16 })
                  .opacity(0.6);

                Text('暂无虚拟机')
                  .fontSize(16)
                  .fontColor('#999999')
                  .margin({ bottom: 8 });

                Text('点击上方按钮创建第一个虚拟机')
                  .fontSize(14)
                  .fontColor('#CCCCCC');
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#F5F7FA');
        }
        .tabBar('虚拟机')
        .backgroundColor('#F5F7FA');

        TabContent() {
          Column() {
            // 顶部标题
            Text('应用管理')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1A1A1A')
              .margin({ top: 100, bottom: 20 });

            // 功能卡片
            Column() {
              Text('功能特性')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1A1A1A')
                .margin({ bottom: 16 });

              Row() {
                Column() {
                  Circle()
                    .width(48)
                    .height(48)
                    .fill('#007DFF')
                    .margin({ bottom: 8 });
                  Text('应用启动')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333');
                  Text('启动虚拟机应用')
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ top: 4 });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center);

                Column() {
                  Circle()
                    .width(48)
                    .height(48)
                    .fill('#00C853')
                    .margin({ bottom: 8 });
                  Text('远程窗口')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333');
                  Text('独立应用窗口')
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ top: 4 });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center);

                Column() {
                  Circle()
                    .width(48)
                    .height(48)
                    .fill('#FF9800')
                    .margin({ bottom: 8 });
                  Text('桌面集成')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333');
                  Text('鸿蒙桌面集成')
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ top: 4 });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center);
              }
              .width('100%')
              .margin({ bottom: 24 });

              Text('• 支持Windows和Linux应用程序')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ bottom: 8 });

              Text('• 远程应用窗口独立显示')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ bottom: 8 });

              Text('• 与鸿蒙系统深度集成')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ bottom: 8 });

              Text('• 支持应用快捷方式创建')
                .fontSize(14)
                .fontColor('#666666');
            }
            .padding(24)
            .backgroundColor(Color.White)
            .borderRadius(16)
            .margin({ left: 20, right: 20 })
            .shadow({ radius: 8, color: '#00000008', offsetX: 0, offsetY: 2 });
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#F5F7FA')
          .padding({ top: 20 });
        }
        .tabBar('应用')
        .backgroundColor('#F5F7FA');

        TabContent() {
          Column() {
            // 顶部标题
            Text('个人中心')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1A1A1A')
              .margin({ top: 100, bottom: 20 });

            // 功能卡片
            Column() {
              Text('系统功能')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1A1A1A')
                .margin({ bottom: 16 });

              Row() {
                Column() {
                  Circle()
                    .width(48)
                    .height(48)
                    .fill('#9C27B0')
                    .margin({ bottom: 8 });
                  Text('设备能力')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333');
                  Text('JIT/KVM检测')
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ top: 4 });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
                .onClick(() => this.showDeviceCapabilities());

                Column() {
                  Circle()
                    .width(48)
                    .height(48)
                    .fill('#607D8B')
                    .margin({ bottom: 8 });
                  Text('日志查看')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333');
                  Text('系统日志导出')
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ top: 4 });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
                .onClick(() => this.showSystemLogs());

                Column() {
                  Circle()
                    .width(48)
                    .height(48)
                    .fill('#795548')
                    .margin({ bottom: 8 });
                  Text('系统设置')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333');
                  Text('应用配置选项')
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ top: 4 });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
                .onClick(() => this.showSystemSettings());
              }
              .width('100%')
              .margin({ bottom: 24 });

              Text('• JIT权限检测与启用')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ bottom: 8 });

              Text('• KVM硬件加速支持')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ bottom: 8 });

              Text('• 系统日志实时查看')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ top: 8 });
            }
            .padding(24)
            .backgroundColor(Color.White)
            .borderRadius(16)
            .margin({ left: 20, right: 20 })
            .shadow({ radius: 8, color: '#00000008', offsetX: 0, offsetY: 2 });
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#F5F7FA')
          .padding({ top: 20 });
        }
        .tabBar('我的')
        .backgroundColor('#F5F7FA');
      }
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .barHeight(64)
      .backgroundColor(Color.White)
      .border({ width: { top: 1 }, color: '#E8E8E8' });

      // VM创建对话框
      if (this.showCreateDialog) {
        Column() {
          Column() {
            Row() {
              Text('创建新虚拟机')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1A1A1A')
                .layoutWeight(1);

              Button({ type: ButtonType.Circle }) {
                Text('×')
                  .fontSize(18)
                  .fontColor('#666666')
              }
              .width(32)
              .height(32)
              .backgroundColor('#F5F5F5')
              .onClick(() => {
                this.showCreateDialog = false;
                this.resetCreateForm();
              });
            }
            .width('100%')
            .margin({ bottom: 24 });

            TextInput({ placeholder: '请输入虚拟机名称' })
              .width('100%')
              .height(48)
              .backgroundColor('#F8F9FA')
              .borderRadius(12)
              .margin({ bottom: 20 })
              .padding({ left: 16, right: 16 })
              .border({ width: 1, color: '#E8E8E8' })
              .onChange((value: string) => {
                this.newVMName = value;
              });

            Row() {
              Text('操作系统')
                .fontSize(14)
                .fontColor('#666666')
                .width(80);

              Select([
                { value: 'Windows' },
                { value: 'Linux' }
              ])
                .selected(0)
                .onSelect((index: number) => {
                  this.newVMOS = index === 0 ? 'Windows' : 'Linux';
                })
                .layoutWeight(1);
            }
            .width('100%')
            .margin({ bottom: 20 });

            // 架构选择
            Row() {
              Text('架构类型')
                .fontSize(14)
                .fontColor('#666666')
                .width(80);

              Select([
                { value: 'aarch64 (推荐)' },
                { value: 'x86_64 (兼容)' },
                { value: 'i386 (兼容)' }
              ])
                .selected(0)
                .onSelect((index: number) => {
                  const archTypes = ['aarch64', 'x86_64', 'i386'];
                  this.newVMArchType = archTypes[index] as 'aarch64' | 'x86_64' | 'i386';
                })
                .layoutWeight(1);
            }
            .width('100%')
            .margin({ bottom: 20 });

            // ISO 路径（可选）
            Row() {
              Text('ISO路径')
                .fontSize(14)
                .fontColor('#666666')
                .width(80);

              TextInput({ placeholder: '如 /data/.../files/isos/win11.iso', text: this.newVMISOPath })
                .onChange((v: string) => { this.newVMISOPath = v })
                .layoutWeight(1)

              Button('选择')
                .onClick(async () => {
                  try {
                    const dp = new picker.DocumentViewPicker()
                    const uris = await dp.select({ maxSelectNumber: 1, fileSuffixFilters: ['iso','ISO'] })
                    if (uris && uris.length > 0) {
                      const u = uris[0]
                      this.newVMISOPath = u.startsWith('file://') ? u.substring(7) : u
                    }
                  } catch (e) {}
                })
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ bottom: 20 })

            Row() {
              Text('磁盘大小')
                .fontSize(14)
                .fontColor('#666666')
                .width(80);

              Select([
                { value: '32' },
                { value: '64' },
                { value: '128' },
                { value: '256' }
              ])
                .selected(1)
                .onSelect((index: number) => {
                  const sizes = [32, 64, 128, 256];
                  this.newVMDiskSize = sizes[index];
                })
                .layoutWeight(1);
            }
            .width('100%')
            .margin({ bottom: 20 });

            Row() {
              Text('内存大小')
                .fontSize(14)
                .fontColor('#666666')
                .width(80);

              Select([
                { value: '2048' },
                { value: '4096' },
                { value: '6144' },
                { value: '8192' }
              ])
                .selected(2)
                .onSelect((index: number) => {
                  const memories = [2048, 4096, 6144, 8192];
                  this.newVMMemory = memories[index];
                })
                .layoutWeight(1);
            }
            .width('100%')
            .margin({ bottom: 20 });

            Row() {
              Text('CPU核心')
                .fontSize(14)
                .fontColor('#666666')
                .width(80);

              Select([
                { value: '1' },
                { value: '2' },
                { value: '4' },
                { value: '8' }
              ])
                .selected(2)
                .onSelect((index: number) => {
                  const cpus = [1, 2, 4, 8];
                  this.newVMCPU = cpus[index];
                })
                .layoutWeight(1);
            }
            .width('100%')
            .margin({ bottom: 32 });

            Row() {
              Button('取消')
                .width(120)
                .height(44)
                .backgroundColor('#F5F5F5')
                .fontColor('#666666')
                .fontSize(16)
                .borderRadius(22)
                .onClick(() => {
                  this.showCreateDialog = false;
                  this.resetCreateForm();
                });

              Button('创建')
                .width(120)
                .height(44)
                .backgroundColor('#007DFF')
                .fontColor(Color.White)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .borderRadius(22)
                .margin({ left: 16 })
                .onClick(() => {
                  this.createVM();
                })
                .enabled(!this.isLoading);
            }
            .width('100%')
            .justifyContent(FlexAlign.Center);
          }
          .padding(24)
          .backgroundColor(Color.White)
          .borderRadius(20)
          .width('90%');
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      }
      // 启动模式选择弹窗（覆盖层）
      if (this.showStartModeDialog && this.startTargetVM) {
        Column() {
        Text('选择启动模式')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })
        Text('安装阶段使用 VNC 观察安装；系统装好后使用 RDP。')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 12 })
        Row() {
          Button('安装期 (VNC - Web)')
            .width('32%')
            .onClick(() => this.doStartVM(this.startTargetVM!, 'install'))
          Button('安装期 (VNC - 原生)')
            .width('32%')
            .backgroundColor('#F1F3F5')
            .fontColor('#333333')
            .onClick(() => {
              // 启动不带 websocket 的 VNC 并进入原生VNC页面
              const vm = this.startTargetVM!
              this.isLoading = true
              const ok: boolean = qemu.startVm({
                name: vm.name,
                accel: qemu.kvmSupported() ? 'kvm' : 'tcg',
                display: 'vnc=:1',
                nographic: false
              })
              this.isLoading = false
              this.showStartModeDialog = false
              this.startTargetVM = null
              if (ok) {
                router.pushUrl({ url: 'pages/VNCNativeViewer', params: { vmName: vm.name } })
              } else {
                this.errorMessage = 'VM启动失败 (原生VNC)'
              }
            })
          Button('已安装 (RDP)')
            .width('32%')
            .backgroundColor('#007DFF')
            .fontColor(Color.White)
            .onClick(() => this.doStartVM(this.startTargetVM!, 'normal'))
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        Button('取消')
          .width('100%')
          .backgroundColor('#F1F3F5')
          .fontColor('#333333')
          .margin({ top: 12 })
          .onClick(() => { this.showStartModeDialog = false; this.startTargetVM = null })
        }
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .width('90%')
        .shadow({ radius: 10, color: '#00000020' })
        .position({ x: '5%', y: '30%' })
      }
    }
    .width('100%')
    .height('100%');
  }

  async runDiagnostics() {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const rm = ctx.resourceManager
      // 检测核心库（真实NAPI接口）
      const defaultCore: CoreDiag = {
        loaded: false,
        foundLd: false,
        selfDir: '',
        foundSelfDir: false,
        existsFilesPath: false,
        filesPath: '/data/storage/el2/base/haps/entry/files/libqemu_full.so',
        foundFiles: false
      }
      const qd = qemu as QemuDiagAPI
      const core: CoreDiag = (typeof qd.checkCoreLib === 'function')
        ? qd.checkCoreLib!()
        : defaultCore
      // 检测 noVNC 资源（真实 rawfile 探测）
      let hasMin = false, hasEsm = false
      try { await rm.getRawFileContent('novnc/novnc.min.js'); hasMin = true } catch (_) {}
      try { await rm.getRawFileContent('novnc/novnc.esm.js'); hasEsm = true } catch (_) {}

      // 获取设备能力信息
      const capabilities = qemu.getDeviceCapabilities()

      const lines: string[] = []
      lines.push(`Core.loaded: ${core.loaded === true}`)
      lines.push(`Core.foundLd: ${core.foundLd === true}${core.errLd ? ' ('+core.errLd+')' : ''}`)
      lines.push(`Core.symFound: ${core.symFound === true}${core.symErr ? ' ('+core.symErr+')' : ''}`)
      lines.push(`Core.selfDir: ${core.selfDir || ''}`)
      lines.push(`Core.foundSelfDir: ${core.foundSelfDir === true}${core.errSelfDir ? ' ('+core.errSelfDir+')' : ''}`)
      lines.push(`Core.filesPath: ${core.filesPath || '/data/storage/el2/base/haps/entry/files/libqemu_full.so'}`)
      lines.push(`Core.existsFilesPath: ${core.existsFilesPath === true}`)
      lines.push(`Core.foundFiles: ${core.foundFiles === true}${core.errFiles ? ' ('+core.errFiles+')' : ''}`)
      lines.push(`noVNC.min.js: ${hasMin}`)
      lines.push(`noVNC.esm.js: ${hasEsm}`)
      lines.push(`KVM支持: ${capabilities.kvmSupported}`)
      lines.push(`JIT支持: ${capabilities.jitSupported}`)
      lines.push(`总内存: ${Math.round(capabilities.totalMemory / 1024 / 1024 / 1024)}GB`)
      lines.push(`CPU核心: ${capabilities.cpuCores}`)

      AlertDialog.show({
        title: '依赖诊断',
        message: lines.join('\n'),
        primaryButton: { value: '确定', action: () => {} }
      })
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : `${e}`
      AlertDialog.show({ title: '诊断失败', message: msg, primaryButton: { value: '确定', action: () => {} } })
    }
  }

  // 显示设备能力
  showDeviceCapabilities() {
    try {
      const jitEnabled = qemu.enableJit()
      const kvmSupported = qemu.kvmSupported()
      const version = qemu.version()
      
      const capabilities = [
        `QEMU版本: ${version}`,
        `JIT权限: ${jitEnabled ? '✓ 已启用' : '✗ 未启用'}`,
        `KVM支持: ${kvmSupported ? '✓ 支持' : '✗ 不支持'}`,
        `加速模式: ${kvmSupported ? 'KVM硬件加速' : 'TCG软件模拟'}`,
        `推荐配置: ${kvmSupported ? '4核6GB' : '2核4GB'}`,
        `注意事项: ${jitEnabled ? 'JIT已启用，性能最佳' : 'JIT未启用，需要调试签名'}`
      ]
      
      AlertDialog.show({
        title: '设备能力检测',
        message: capabilities.join('\n'),
        primaryButton: { value: '确定', action: () => {} },
        secondaryButton: { value: '导出日志', action: () => this.exportLogs() }
      })
    } catch (e) {
      AlertDialog.show({
        title: '检测失败',
        message: `设备能力检测失败: ${e}`,
        primaryButton: { value: '确定', action: () => {} }
      })
    }
  }

  // 导出日志
  async exportLogs() {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
      const rm = ctx.resourceManager
      
      // 获取设备能力信息
      const capabilities = qemu.getDeviceCapabilities()
      
      // 获取VM日志
      const vmLogs = qemu.getVmLogs('default-vm')
      
      // 构建日志内容
      const logContent = [
        '=== QEMU-HMOS 系统日志 ===',
        `导出时间: ${new Date().toISOString()}`,
        '',
        '=== 设备能力 ===',
        `KVM支持: ${capabilities.kvmSupported}`,
        `JIT支持: ${capabilities.jitSupported}`,
        `总内存: ${Math.round(capabilities.totalMemory / 1024 / 1024 / 1024)}GB`,
        `CPU核心: ${capabilities.cpuCores}`,
        '',
        '=== VM日志 ===',
        ...vmLogs,
        '',
        '=== 系统信息 ===',
        `HarmonyOS版本: ${os.getProperty('os.version')}`,
        `设备型号: ${os.getProperty('os.name')}`,
        `架构: ${os.getProperty('os.arch')}`
      ].join('\n')
      
      // 保存日志文件
      const logPath = '/data/storage/el2/base/haps/entry/files/qemu_logs.txt'
      const file = await fileIo.open(logPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      await fileIo.write(file.fd, new TextEncoder().encode(logContent))
      await fileIo.close(file.fd)
      
      AlertDialog.show({
        title: '日志导出成功',
        message: `日志已保存到: ${logPath}`,
        primaryButton: { value: '确定', action: () => {} }
      })
      
    } catch (e) {
      AlertDialog.show({
        title: '日志导出失败',
        message: `导出失败: ${e}`,
        primaryButton: { value: '确定', action: () => {} }
      })
    }
  }

  // 显示系统日志
  showSystemLogs() {
    try {
      const logs = qemu.getVmLogs('system', 0)
      const logText = logs.length > 0 ? logs.join('\n') : '暂无系统日志'
      
      AlertDialog.show({
        title: '系统日志',
        message: logText,
        primaryButton: { value: '确定', action: () => {} }
      })
    } catch (e) {
      AlertDialog.show({
        title: '日志获取失败',
        message: `无法获取系统日志: ${e}`,
        primaryButton: { value: '确定', action: () => {} }
      })
    }
  }

  // 显示系统设置
  showSystemSettings() {
    AlertDialog.show({
      title: '系统设置',
      message: '系统设置功能开发中...\n\n将包含：\n• QEMU参数配置\n• 网络设置\n• 存储管理\n• 性能调优',
      primaryButton: { value: '确定', action: () => {} }
    })
  }
}
