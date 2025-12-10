/**
 * VNC 显示组件 - 完整实现
 * 通过 WebView 加载 noVNC 或使用 Canvas 直接渲染
 * 集成虚拟按键Hub支持触摸屏操作
 */
import web_webview from '@ohos.web.webview';
import image from '@ohos.multimedia.image';
import { VirtualKeyHub, VirtualKeyHubCallbacks, KeySym } from './VirtualKeyHub';

// VNC 连接状态
export enum VNCConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  ERROR = 'error'
}

// VNC 连接配置
export interface VNCConfig {
  host: string;
  port: number;
  password?: string;
  viewOnly?: boolean;
  scaleViewport?: boolean;
  quality?: number; // 0-9, 图像质量
}

// VNC 事件回调
export interface VNCCallbacks {
  onConnected?: () => void;
  onDisconnected?: () => void;
  onError?: (error: string) => void;
  onBellRing?: () => void;
  onClipboard?: (text: string) => void;
}

@Component
export struct VNCDisplay {
  // 连接配置（端口是QEMU的WebSocket端口，不是RFB端口）
  @Prop config: VNCConfig = { host: '127.0.0.1', port: 5700 };
  
  // 回调函数
  @Prop callbacks?: VNCCallbacks;
  
  // 显示选项
  @Prop showToolbar: boolean = true;
  @Prop autoReconnect: boolean = true;
  
  // 内部状态
  @State connectionState: VNCConnectionState = VNCConnectionState.DISCONNECTED;
  @State errorMessage: string = '';
  @State isFullscreen: boolean = false;
  @State scaleFactor: number = 1.0;
  @State showKeyboard: boolean = false;
  
  // WebView 控制器
  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  
  // 重连计数
  private reconnectAttempts: number = 0;
  private maxReconnectAttempts: number = 5;
  
  aboutToAppear() {
    // 初始化时自动连接
    this.connect();
  }
  
  aboutToDisappear() {
    // 组件销毁时断开连接
    this.disconnect();
  }
  
  /**
   * 连接到 VNC 服务器
   */
  connect() {
    if (this.connectionState === VNCConnectionState.CONNECTING ||
        this.connectionState === VNCConnectionState.CONNECTED) {
      return;
    }
    
    this.connectionState = VNCConnectionState.CONNECTING;
    this.errorMessage = '';
    
    console.info(`[VNCDisplay] Connecting to ${this.config.host}:${this.config.port}`);
    
    // 使用 WebView 加载 noVNC
    // noVNC 页面会通过 WebSocket 连接到 VNC 服务器
    try {
      const vncUrl = this.buildVNCUrl();
      console.info(`[VNCDisplay] Loading URL: ${vncUrl}`);
      
      // WebView 会在 onPageEnd 中处理连接结果
    } catch (e) {
      this.handleError(`连接失败: ${e}`);
    }
  }
  
  /**
   * 断开连接
   */
  disconnect() {
    if (this.connectionState === VNCConnectionState.DISCONNECTED) {
      return;
    }
    
    console.info('[VNCDisplay] Disconnecting');
    
    // 调用 noVNC 的断开方法
    try {
      this.webController.runJavaScript('if(typeof rfb !== "undefined") rfb.disconnect();');
    } catch (e) {
      console.error('[VNCDisplay] Error disconnecting:', e);
    }
    
    this.connectionState = VNCConnectionState.DISCONNECTED;
    this.callbacks?.onDisconnected?.();
  }
  
  /**
   * 重新连接
   */
  reconnect() {
    this.disconnect();
    setTimeout(() => {
      this.connect();
    }, 1000);
  }
  
  /**
   * 发送按键事件
   */
  sendKey(keysym: number, down: boolean) {
    if (this.connectionState !== VNCConnectionState.CONNECTED) {
      return;
    }
    
    try {
      const method = down ? 'sendKey' : 'sendKey';
      this.webController.runJavaScript(
        `if(typeof rfb !== "undefined") rfb.sendKey(${keysym}, null, ${down});`
      );
    } catch (e) {
      console.error('[VNCDisplay] Error sending key:', e);
    }
  }
  
  /**
   * 发送 Ctrl+Alt+Del
   */
  sendCtrlAltDel() {
    if (this.connectionState !== VNCConnectionState.CONNECTED) {
      return;
    }
    
    try {
      this.webController.runJavaScript(
        'if(typeof rfb !== "undefined") rfb.sendCtrlAltDel();'
      );
    } catch (e) {
      console.error('[VNCDisplay] Error sending Ctrl+Alt+Del:', e);
    }
  }
  
  /**
   * 发送剪贴板内容
   */
  sendClipboard(text: string) {
    if (this.connectionState !== VNCConnectionState.CONNECTED) {
      return;
    }
    
    try {
      const escapedText = text.replace(/'/g, "\\'").replace(/\n/g, '\\n');
      this.webController.runJavaScript(
        `if(typeof rfb !== "undefined") rfb.clipboardPasteFrom('${escapedText}');`
      );
    } catch (e) {
      console.error('[VNCDisplay] Error sending clipboard:', e);
    }
  }
  
  /**
   * 构建 VNC URL
   */
  private buildVNCUrl(): string {
    // noVNC 需要 WebSocket 代理
    // 格式: vnc.html?host=X&port=Y&password=Z
    const params: string[] = [];
    params.push(`host=${encodeURIComponent(this.config.host)}`);
    params.push(`port=${this.config.port}`);
    params.push('autoconnect=true');
    params.push('resize=scale');
    
    if (this.config.password) {
      params.push(`password=${encodeURIComponent(this.config.password)}`);
    }
    
    if (this.config.viewOnly) {
      params.push('view_only=true');
    }
    
    if (this.config.quality !== undefined) {
      params.push(`quality=${this.config.quality}`);
    }
    
    // noVNC 资源路径
    return `resource://rawfile/novnc/vnc.html?${params.join('&')}`;
  }
  
  /**
   * 处理连接成功
   */
  private handleConnected() {
    this.connectionState = VNCConnectionState.CONNECTED;
    this.reconnectAttempts = 0;
    this.errorMessage = '';
    console.info('[VNCDisplay] Connected successfully');
    this.callbacks?.onConnected?.();
  }
  
  /**
   * 处理错误
   */
  private handleError(error: string) {
    this.connectionState = VNCConnectionState.ERROR;
    this.errorMessage = error;
    console.error('[VNCDisplay] Error:', error);
    this.callbacks?.onError?.(error);
    
    // 自动重连
    if (this.autoReconnect && this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      console.info(`[VNCDisplay] Attempting reconnect ${this.reconnectAttempts}/${this.maxReconnectAttempts}`);
      setTimeout(() => {
        this.connect();
      }, 2000 * this.reconnectAttempts);
    }
  }
  
  /**
   * 切换全屏
   */
  toggleFullscreen() {
    this.isFullscreen = !this.isFullscreen;
  }
  
  /**
   * 缩放视图
   */
  setScale(scale: number) {
    this.scaleFactor = Math.max(0.25, Math.min(4.0, scale));
    try {
      this.webController.runJavaScript(
        `if(typeof rfb !== "undefined") { document.getElementById('screen').style.transform = 'scale(${this.scaleFactor})'; }`
      );
    } catch (e) {
      console.error('[VNCDisplay] Error setting scale:', e);
    }
  }
  
  build() {
    Column() {
      Stack() {
        // 1. 底层：VNC WebView 内容（始终渲染，以便加载资源和连接）
        this.VNCContentView()
        
        // 2. 覆盖层：状态提示（连接中、错误、断开）
        if (this.connectionState !== VNCConnectionState.CONNECTED) {
          // 半透明遮罩
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#1A1A1A')
            .opacity(this.connectionState === VNCConnectionState.CONNECTING ? 0.8 : 1.0)
            
          // 状态内容
          if (this.connectionState === VNCConnectionState.CONNECTING) {
            this.LoadingView()
          } else if (this.connectionState === VNCConnectionState.ERROR) {
            this.ErrorView()
          } else if (this.connectionState === VNCConnectionState.DISCONNECTED) {
            this.DisconnectedView()
          }
        }
        
        // 3. 顶层：工具栏
        if (this.showToolbar && this.connectionState === VNCConnectionState.CONNECTED) {
          this.ToolbarView()
        }
      }
      .width('100%')
      .layoutWeight(1)
      
      // 虚拟按键Hub（仅在连接状态显示）
      if (this.connectionState === VNCConnectionState.CONNECTED) {
        VirtualKeyHub({
          callbacks: {
            onKeyDown: (keysym: number) => {
              this.sendKey(keysym, true)
            },
            onKeyUp: (keysym: number) => {
              this.sendKey(keysym, false)
            },
            onCombo: (modifiers: number[], key: number) => {
              this.sendKeyCombo(modifiers, key)
            }
          } as VirtualKeyHubCallbacks
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A1A')
  }
  
  /**
   * 发送组合键
   */
  sendKeyCombo(modifiers: number[], key: number) {
    if (this.connectionState !== VNCConnectionState.CONNECTED) {
      return;
    }
    
    try {
      // 按下所有修饰键
      modifiers.forEach(mod => {
        this.webController.runJavaScript(
          `if(typeof rfb !== "undefined") rfb.sendKey(${mod}, null, true);`
        );
      });
      
      // 按下并释放主键
      this.webController.runJavaScript(
        `if(typeof rfb !== "undefined") { rfb.sendKey(${key}, null, true); rfb.sendKey(${key}, null, false); }`
      );
      
      // 释放所有修饰键（逆序）
      [...modifiers].reverse().forEach(mod => {
        this.webController.runJavaScript(
          `if(typeof rfb !== "undefined") rfb.sendKey(${mod}, null, false);`
        );
      });
    } catch (e) {
      console.error('[VNCDisplay] Error sending key combo:', e);
    }
  }
  
  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(60)
        .height(60)
        .color('#007AFF')
      
      Text('正在连接 VNC 服务器...')
        .fontSize(16)
        .fontColor('#FFFFFF')
        .margin({ top: 20 })
      
      Text(`${this.config.host}:${this.config.port}`)
        .fontSize(14)
        .fontColor('#888888')
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
  
  @Builder
  ErrorView() {
    Column() {
      Circle()
        .width(64)
        .height(64)
        .fill('#FF3B30')
      
      Text('连接失败')
        .fontSize(20)
        .fontColor('#FF3B30')
        .fontWeight(FontWeight.Medium)
        .margin({ top: 16 })
      
      Text(this.errorMessage)
        .fontSize(14)
        .fontColor('#888888')
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
        .padding({ left: 32, right: 32 })
      
      Row() {
        Button('重新连接')
          .onClick(() => this.reconnect())
          .backgroundColor('#007AFF')
          .fontColor(Color.White)
          .margin({ right: 16 })
        
        Button('取消')
          .onClick(() => {
            this.connectionState = VNCConnectionState.DISCONNECTED;
          })
          .backgroundColor('#333333')
          .fontColor(Color.White)
      }
      .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
  
  @Builder
  DisconnectedView() {
    Column() {
      Circle()
        .width(80)
        .height(80)
        .fill('#444444')
      
      Text('VNC 显示')
        .fontSize(20)
        .fontColor('#FFFFFF')
        .margin({ top: 16 })
      
      Text('点击连接按钮开始远程桌面会话')
        .fontSize(14)
        .fontColor('#888888')
        .margin({ top: 8 })
      
      Button('连接')
        .onClick(() => this.connect())
        .backgroundColor('#007AFF')
        .fontColor(Color.White)
        .width(120)
        .height(44)
        .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
  
  @Builder
  VNCContentView() {
    // 使用 WebView 加载 noVNC
    Web({
      src: this.buildVNCUrl(),
      controller: this.webController
    })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .mixedMode(MixedMode.All)
      .onPageEnd(() => {
        console.info('[VNCDisplay] Page loaded');
        this.handleConnected();
      })
      .onErrorReceive((event) => {
        if (event && event.error) {
          this.handleError(event.error.getErrorInfo());
        }
      })
      .onConsole((event) => {
        if (event) {
          console.info(`[noVNC] ${event.message.getMessage()}`);
          
          // 检测 VNC 连接状态变化
          const msg = event.message.getMessage();
          if (msg.includes('connected')) {
            this.handleConnected();
          } else if (msg.includes('disconnected') || msg.includes('error')) {
            this.handleError(msg);
          }
        }
        return false;
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          // 双指缩放
          PinchGesture({ fingers: 2 })
            .onActionUpdate((event: GestureEvent) => {
              if (event) {
                this.setScale(this.scaleFactor * event.scale);
              }
            }),
          // 双击切换全屏
          TapGesture({ count: 2 })
            .onAction(() => {
              this.toggleFullscreen();
            })
        )
      )
  }
  
  @Builder
  ToolbarView() {
    Column() {
      Blank()
      
      Row() {
        // Ctrl+Alt+Del 按钮
        Button({ type: ButtonType.Circle }) {
          Text('⌨')
            .fontSize(18)
            .fontColor(Color.White)
        }
        .width(44)
        .height(44)
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .onClick(() => this.sendCtrlAltDel())
        
        // 键盘按钮
        Button({ type: ButtonType.Circle }) {
          Text('⌨')
            .fontSize(18)
            .fontColor(Color.White)
        }
        .width(44)
        .height(44)
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .margin({ left: 12 })
        .onClick(() => {
          this.showKeyboard = !this.showKeyboard;
        })
        
        // 全屏按钮
        Button({ type: ButtonType.Circle }) {
          Text('⤢')
            .fontSize(18)
            .fontColor(Color.White)
        }
        .width(44)
        .height(44)
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .margin({ left: 12 })
        .onClick(() => this.toggleFullscreen())
        
        // 断开连接按钮
        Button({ type: ButtonType.Circle }) {
          Text('✕')
            .fontSize(18)
            .fontColor('#FF3B30')
        }
        .width(44)
        .height(44)
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .margin({ left: 12 })
        .onClick(() => this.disconnect())
      }
      .padding(16)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height('100%')
  }
}
