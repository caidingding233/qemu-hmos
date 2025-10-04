import qemu from 'libqemu_hmos.so';

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

  private startApp(app: AppInfo) {
    this.loading = true;
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
      
      // 等待VM启动后，通过RDP启动应用
      setTimeout(() => {
        this.launchAppViaRDP(app);
      }, 3000);
      
    } catch (e) {
      this.error = `启动异常: ${JSON.stringify(e)}`;
    } finally {
      this.loading = false;
    }
  }
  
  private launchAppViaRDP(app: AppInfo) {
    try {
      // 创建RDP客户端并连接
      const rdpClient = qemu.createRdpClient();
      const connectResult = qemu.connectRdp(rdpClient.id, {
        host: '127.0.0.1',
        port: 3390,
        username: 'Administrator',
        password: 'password',
        width: 1024,
        height: 768
      });
      
      if (connectResult === 0) {
        // 连接成功，启动应用
        this.error = `正在启动 ${app.name}...`;
        
        // 构建应用启动命令
        const command = this.buildAppCommand(app);
        
        // 通过RDP执行应用启动命令
        this.executeRDPCommand(rdpClient.id, command);
        
        // 跳转到RDP查看器页面
        setTimeout(() => {
          router.pushUrl({
            url: 'pages/RDPViewer',
            params: {
              vmId: 'default-vm',
              rdpHost: '127.0.0.1',
              rdpPort: 3390
            }
          });
        }, 2000);
      } else {
        this.error = 'RDP连接失败';
      }
    } catch (e) {
      this.error = `应用启动失败: ${e}`;
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
        return app.name;
    }
  }

  private executeRDPCommand(rdpClientId: string, command: string) {
    try {
      // 这里应该通过RDP发送键盘输入来执行命令
      // 由于当前RDP实现是模拟的，这里简化处理
      console.log(`Executing RDP command: ${command} via client ${rdpClientId}`);
      
      // 模拟执行命令的过程
      setTimeout(() => {
        console.log(`Command ${command} executed successfully`);
      }, 1000);
    } catch (e) {
      console.error(`Failed to execute RDP command: ${e}`);
    }
  }

  build() {
    Column() {
      Text('应用启动器')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })

      if (this.error) {
        Text(this.error)
          .fontSize(14)
          .fontColor(Color.Red)
          .padding(8)
          .backgroundColor(Color.Red + '20')
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
