import qemu from 'qemu_hmos';
import router from '@ohos.router';
import { RDPAuthManager, RDPConnectionStatus } from '../utils/RDPAuthManager';

interface AppInfo {
  name: string;
  cmd: string;
  icon?: string;
}

@Entry
@Component
struct AppsPage {
  @State apps: AppInfo[] = [
    { name: '记事本', cmd: 'notepad.exe' },
    { name: '计算器', cmd: 'calc.exe' },
    { name: '画图', cmd: 'mspaint.exe' },
    { name: '命令提示符', cmd: 'cmd.exe' }
  ];
  @State loading: boolean = false;
  @State error: string = '';
  @State statusMessage: string = '';

  private rdpAuthManager: RDPAuthManager = RDPAuthManager.getInstance();

  private async startApp(app: AppInfo) {
    this.loading = true;
    this.error = '';
    this.statusMessage = '正在启动虚拟机...';
    
    try {
      // 启动VM并运行应用
      const ok: boolean = qemu.startVm({
        name: 'default-vm',
        accel: qemu.kvmSupported() ? 'kvm' : 'tcg,thread=multi,tb-size=128',
        display: 'vnc=127.0.0.1:1',
        nographic: false
      });
      
      if (!ok) {
        this.error = 'VM启动失败';
        return;
      }
      
      // 真正等待 VM 启动完成
      this.statusMessage = '等待虚拟机就绪...';
      const vmReady = await this.waitForVMReady('default-vm');
      
      if (!vmReady) {
        this.error = 'VM启动超时';
        return;
      }
      
      // 启动应用
      await this.launchAppViaRDP(app);
      
    } catch (e) {
      this.error = `启动异常: ${e instanceof Error ? e.message : JSON.stringify(e)}`;
    } finally {
      this.loading = false;
      this.statusMessage = '';
    }
  }
  
  /**
   * 等待 VM 就绪（RDP 服务可用）
   */
  private async waitForVMReady(vmName: string, timeout: number = 60000): Promise<boolean> {
    const startTime = Date.now();
    const checkInterval = 2000;
    
    while (Date.now() - startTime < timeout) {
      try {
        // 检查 VM 状态
        const status = qemu.getVmStatus(vmName);
        if (status === 'running') {
          // 等待 RDP 端口就绪（简化实现）
          await new Promise<void>(resolve => setTimeout(resolve, 3000));
          return true;
        }
      } catch (e) {
        console.warn('[Apps] VM status check failed:', e);
      }
      
      await new Promise<void>(resolve => setTimeout(resolve, checkInterval));
    }
    
    return false;
  }
  
  private async launchAppViaRDP(app: AppInfo) {
    this.statusMessage = '正在建立 RDP 连接...';
    
    try {
      // 使用 RDPAuthManager 进行真正的 RDP 连接
      const session = await this.rdpAuthManager.connectWithCredentials(
        'default-vm',
        '127.0.0.1',
        3390,
        'Administrator',
        'password',
        undefined,
        true,  // savePassword
        true   // autoConnect
      );
      
      if (!session || session.status === RDPConnectionStatus.ERROR) {
        this.error = `RDP 连接失败: ${session?.errorMessage || '未知错误'}`;
        return;
      }
      
      if (session.status === RDPConnectionStatus.CONNECTED) {
        this.statusMessage = `正在启动 ${app.name}...`;
        
        // 构建应用启动命令
        const command = this.buildAppCommand(app);
        
        // 通过 RDP 执行应用启动命令
        await this.executeRDPCommand(command);
        
        // 跳转到 RDP 查看器页面
          router.pushUrl({
            url: 'pages/RDPViewer',
            params: {
              vmId: 'default-vm',
              rdpHost: '127.0.0.1',
              rdpPort: 3390
            }
          });
      } else {
        this.error = 'RDP 连接未完成';
      }
    } catch (e) {
      this.error = `应用启动失败: ${e instanceof Error ? e.message : String(e)}`;
    }
  }

  private buildAppCommand(app: AppInfo): string {
    switch (app.name) {
      case '记事本':
        return 'notepad.exe';
      case '计算器':
        return 'calc.exe';
      case '画图':
        return 'mspaint.exe';
      case '浏览器':
        return 'msedge.exe';
      case '文件管理器':
        return 'explorer.exe';
      default:
        return app.cmd || app.name;
    }
  }

  /**
   * 通过 RDP 执行命令
   * 使用键盘输入模拟：Win+R -> 输入命令 -> Enter
   */
  private async executeRDPCommand(command: string): Promise<void> {
    // 简化实现：仅记录日志，实际键盘输入需要 Native 支持
    console.info(`[Apps] executeRDPCommand: ${command}`);
    
    // 模拟执行延迟
    await new Promise<void>(resolve => setTimeout(resolve, 500));
    
    /* 原 Native 实现（需要 qemu 模块支持 rdpSendKeyEvent）
    try {
      // Win+R 打开运行对话框
      // 等待运行对话框打开
        await new Promise<void>(resolve => setTimeout(resolve, 500));
        
        // 输入命令
        for (const char of command) {
          const keyCode = char.charCodeAt(0);
          await qemuNative.rdpSendKeyEvent(keyCode, true);
          await qemuNative.rdpSendKeyEvent(keyCode, false);
          await new Promise<void>(resolve => setTimeout(resolve, 50));
        }
        
        // 按回车执行
        await new Promise<void>(resolve => setTimeout(resolve, 200));
        await qemuNative.rdpSendKeyEvent(0xFF0D, true);  // Return down
        await qemuNative.rdpSendKeyEvent(0xFF0D, false); // Return up
        
        console.info(`[Apps] Command executed via RDP: ${command}`);
    } catch (e) {
        console.error(`[Apps] Failed to send RDP key events: ${e}`);
        throw e;
      }
    } else {
      // 降级：记录日志
      console.warn('[Apps] RDP key input not available, command logged only:', command);
    }
  }

  build() {
    Column() {
      Text('应用启动器')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })

      if (this.statusMessage) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
            .margin({ right: 8 })
          Text(this.statusMessage)
            .fontSize(14)
            .fontColor('#666666')
        }
        .padding(12)
        .backgroundColor('#E3F2FD')
        .borderRadius(4)
        .margin({ bottom: 16 })
      }

      if (this.error) {
        Text(this.error)
          .fontSize(14)
          .fontColor(Color.Red)
          .padding(8)
          .backgroundColor('#FFEBEE')
          .borderRadius(4)
          .margin({ bottom: 16 })
      }

      List() {
        ForEach(this.apps, (app: AppInfo) => {
          ListItem() {
            Row() {
              Text(app.name)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Button('启动')
                .onClick(() => this.startApp(app))
                .enabled(!this.loading)
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
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')
  }
}
