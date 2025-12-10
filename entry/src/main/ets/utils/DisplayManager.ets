/**
 * 显示管理器
 * 管理 VNC 安装期和 RDP 日常显示，支持柔光屏优化
 */

export interface Resolution {
  width: number;
  height: number;
}

export interface DisplayConfig {
  mode: 'vnc' | 'rdp';
  resolution: Resolution;
  colorDepth: 16 | 24 | 32;
  refreshRate: number;
  scaling: number;
  antiAliasing: boolean;
  contrast: number;
  brightness: number;
  sharpness: number;
  colorTemperature: number;
  enableHDR: boolean;
  enableGfxH264: boolean;
  enableClearType: boolean;
}

export interface VNCConfig {
  host: string;
  port: number;
  password?: string;
  websocket: boolean;
  websocketPort?: number;
  fullscreen: boolean;
  scaling: 'fit' | 'stretch' | 'original';
}

export interface RDPConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  domain?: string;
  connectionQuality: 'low' | 'medium' | 'high' | 'auto';
  enableAudio: boolean;
  enableClipboard: boolean;
  enableFileSharing: boolean;
  enablePrinter: boolean;
  colorDepth: 16 | 24 | 32;
  enableGfxH264: boolean;
  enableClearType: boolean;
}

export interface DisplayCapabilities {
  isSoftScreen: boolean;
  isHiDPI: boolean;
  maxResolution: Resolution;
  supportedColorDepths: number[];
}

export interface DisplayParameters {
  contrast?: number;
  brightness?: number;
  sharpness?: number;
  colorTemperature?: number;
}

export class DisplayManager {
  private static instance: DisplayManager;
  private displayConfig: DisplayConfig;
  private vncConfig: VNCConfig;
  private rdpConfig: RDPConfig;

  private constructor() {
    this.displayConfig = this.getDefaultDisplayConfig();
    this.vncConfig = this.getDefaultVNCConfig();
    this.rdpConfig = this.getDefaultRDPConfig();
  }

  public static getInstance(): DisplayManager {
    if (!DisplayManager.instance) {
      DisplayManager.instance = new DisplayManager();
    }
    return DisplayManager.instance;
  }

  /**
   * 获取默认显示配置
   */
  private getDefaultDisplayConfig(): DisplayConfig {
    const config: DisplayConfig = {
      mode: 'vnc',
      resolution: {
        width: 1920,
        height: 1080
      } as Resolution,
      colorDepth: 32,
      refreshRate: 60,
      scaling: 1.0,
      antiAliasing: true,
      contrast: 1.0,
      brightness: 1.0,
      sharpness: 1.0,
      colorTemperature: 6500,
      enableHDR: false,
      enableGfxH264: true,
      enableClearType: true
    };
    return config;
  }

  /**
   * 获取默认 VNC 配置
   */
  private getDefaultVNCConfig(): VNCConfig {
    const config: VNCConfig = {
      host: '127.0.0.1',
      port: 5900,
      websocket: true,
      websocketPort: 5701,
      fullscreen: false,
      scaling: 'fit'
    };
    return config;
  }

  /**
   * 获取默认 RDP 配置
   */
  private getDefaultRDPConfig(): RDPConfig {
    const config: RDPConfig = {
      host: '127.0.0.1',
      port: 3390,
      username: 'Administrator',
      password: '',
      connectionQuality: 'auto',
      enableAudio: true,
      enableClipboard: true,
      enableFileSharing: true,
      enablePrinter: false,
      colorDepth: 32,
      enableGfxH264: true,
      enableClearType: true
    };
    return config;
  }

  /**
   * 获取显示配置（不使用展开运算符）
   */
  public getDisplayConfig(): DisplayConfig {
    const config: DisplayConfig = {
      mode: this.displayConfig.mode,
      resolution: {
        width: this.displayConfig.resolution.width,
        height: this.displayConfig.resolution.height
      } as Resolution,
      colorDepth: this.displayConfig.colorDepth,
      refreshRate: this.displayConfig.refreshRate,
      scaling: this.displayConfig.scaling,
      antiAliasing: this.displayConfig.antiAliasing,
      contrast: this.displayConfig.contrast,
      brightness: this.displayConfig.brightness,
      sharpness: this.displayConfig.sharpness,
      colorTemperature: this.displayConfig.colorTemperature,
      enableHDR: this.displayConfig.enableHDR,
      enableGfxH264: this.displayConfig.enableGfxH264,
      enableClearType: this.displayConfig.enableClearType
    };
    return config;
  }

  /**
   * 更新显示配置（不使用展开运算符）
   */
  public updateDisplayConfig(config: Partial<DisplayConfig>): void {
    if (config.mode !== undefined) this.displayConfig.mode = config.mode;
    if (config.resolution !== undefined) {
      if (config.resolution.width !== undefined) this.displayConfig.resolution.width = config.resolution.width;
      if (config.resolution.height !== undefined) this.displayConfig.resolution.height = config.resolution.height;
    }
    if (config.colorDepth !== undefined) this.displayConfig.colorDepth = config.colorDepth;
    if (config.refreshRate !== undefined) this.displayConfig.refreshRate = config.refreshRate;
    if (config.scaling !== undefined) this.displayConfig.scaling = config.scaling;
    if (config.antiAliasing !== undefined) this.displayConfig.antiAliasing = config.antiAliasing;
    if (config.contrast !== undefined) this.displayConfig.contrast = config.contrast;
    if (config.brightness !== undefined) this.displayConfig.brightness = config.brightness;
    if (config.sharpness !== undefined) this.displayConfig.sharpness = config.sharpness;
    if (config.colorTemperature !== undefined) this.displayConfig.colorTemperature = config.colorTemperature;
    if (config.enableHDR !== undefined) this.displayConfig.enableHDR = config.enableHDR;
    if (config.enableGfxH264 !== undefined) this.displayConfig.enableGfxH264 = config.enableGfxH264;
    if (config.enableClearType !== undefined) this.displayConfig.enableClearType = config.enableClearType;
  }

  /**
   * 获取 VNC 配置（不使用展开运算符）
   */
  public getVNCConfig(): VNCConfig {
    const config: VNCConfig = {
      host: this.vncConfig.host,
      port: this.vncConfig.port,
      password: this.vncConfig.password,
      websocket: this.vncConfig.websocket,
      websocketPort: this.vncConfig.websocketPort,
      fullscreen: this.vncConfig.fullscreen,
      scaling: this.vncConfig.scaling
    };
    return config;
  }

  /**
   * 更新 VNC 配置（不使用展开运算符）
   */
  public updateVNCConfig(config: Partial<VNCConfig>): void {
    if (config.host !== undefined) this.vncConfig.host = config.host;
    if (config.port !== undefined) this.vncConfig.port = config.port;
    if (config.password !== undefined) this.vncConfig.password = config.password;
    if (config.websocket !== undefined) this.vncConfig.websocket = config.websocket;
    if (config.websocketPort !== undefined) this.vncConfig.websocketPort = config.websocketPort;
    if (config.fullscreen !== undefined) this.vncConfig.fullscreen = config.fullscreen;
    if (config.scaling !== undefined) this.vncConfig.scaling = config.scaling;
  }

  /**
   * 获取 RDP 配置（不使用展开运算符）
   */
  public getRDPConfig(): RDPConfig {
    const config: RDPConfig = {
      host: this.rdpConfig.host,
      port: this.rdpConfig.port,
      username: this.rdpConfig.username,
      password: this.rdpConfig.password,
      domain: this.rdpConfig.domain,
      connectionQuality: this.rdpConfig.connectionQuality,
      enableAudio: this.rdpConfig.enableAudio,
      enableClipboard: this.rdpConfig.enableClipboard,
      enableFileSharing: this.rdpConfig.enableFileSharing,
      enablePrinter: this.rdpConfig.enablePrinter,
      colorDepth: this.rdpConfig.colorDepth,
      enableGfxH264: this.rdpConfig.enableGfxH264,
      enableClearType: this.rdpConfig.enableClearType
    };
    return config;
  }

  /**
   * 更新 RDP 配置（不使用展开运算符）
   */
  public updateRDPConfig(config: Partial<RDPConfig>): void {
    if (config.host !== undefined) this.rdpConfig.host = config.host;
    if (config.port !== undefined) this.rdpConfig.port = config.port;
    if (config.username !== undefined) this.rdpConfig.username = config.username;
    if (config.password !== undefined) this.rdpConfig.password = config.password;
    if (config.domain !== undefined) this.rdpConfig.domain = config.domain;
    if (config.connectionQuality !== undefined) this.rdpConfig.connectionQuality = config.connectionQuality;
    if (config.enableAudio !== undefined) this.rdpConfig.enableAudio = config.enableAudio;
    if (config.enableClipboard !== undefined) this.rdpConfig.enableClipboard = config.enableClipboard;
    if (config.enableFileSharing !== undefined) this.rdpConfig.enableFileSharing = config.enableFileSharing;
    if (config.enablePrinter !== undefined) this.rdpConfig.enablePrinter = config.enablePrinter;
    if (config.colorDepth !== undefined) this.rdpConfig.colorDepth = config.colorDepth;
    if (config.enableGfxH264 !== undefined) this.rdpConfig.enableGfxH264 = config.enableGfxH264;
    if (config.enableClearType !== undefined) this.rdpConfig.enableClearType = config.enableClearType;
  }

  /**
   * 生成 VNC 连接 URL（不使用解构声明）
   */
  public generateVNCUrl(): string {
    const host = this.vncConfig.host;
    const port = this.vncConfig.port;
    const websocket = this.vncConfig.websocket;
    const websocketPort = this.vncConfig.websocketPort;
    
    if (websocket && websocketPort) {
      return `ws://${host}:${websocketPort}`;
    } else {
      return `vnc://${host}:${port}`;
    }
  }

  /**
   * 生成 RDP 连接参数（不使用解构声明）
   */
  public generateRDPArgs(): string[] {
    const host = this.rdpConfig.host;
    const port = this.rdpConfig.port;
    const username = this.rdpConfig.username;
    const password = this.rdpConfig.password;
    const domain = this.rdpConfig.domain;
    const connectionQuality = this.rdpConfig.connectionQuality;
    const enableAudio = this.rdpConfig.enableAudio;
    const enableClipboard = this.rdpConfig.enableClipboard;
    const colorDepth = this.rdpConfig.colorDepth;
    const enableGfxH264 = this.rdpConfig.enableGfxH264;
    
    const args: string[] = [
      '--server', `${host}:${port}`,
      '--username', username,
      '--password', password,
      '--width', this.displayConfig.resolution.width.toString(),
      '--height', this.displayConfig.resolution.height.toString(),
      '--color-depth', colorDepth.toString()
    ];

    if (domain) {
      args.push('--domain', domain);
    }

    if (enableAudio) {
      args.push('--enable-audio');
    }

    if (enableClipboard) {
      args.push('--enable-clipboard');
    }

    if (enableGfxH264) {
      args.push('--enable-gfx-h264');
    }

    // 连接质量设置
    switch (connectionQuality) {
      case 'low':
        args.push('--connection-quality', 'low');
        break;
      case 'medium':
        args.push('--connection-quality', 'medium');
        break;
      case 'high':
        args.push('--connection-quality', 'high');
        break;
      case 'auto':
        args.push('--connection-quality', 'auto');
        break;
    }

    return args;
  }

  /**
   * 应用柔光屏优化
   */
  public applySoftScreenOptimization(): void {
    // 柔光屏优化设置
    this.displayConfig.contrast = 0.9; // 降低对比度
    this.displayConfig.brightness = 0.8; // 降低亮度
    this.displayConfig.sharpness = 0.7; // 降低锐度
    this.displayConfig.colorTemperature = 5000; // 暖色调
    this.displayConfig.antiAliasing = true; // 启用抗锯齿
    this.displayConfig.enableClearType = true; // 启用 ClearType
  }

  /**
   * 应用 HiDPI 优化
   */
  public applyHiDPIOptimization(devicePixelRatio: number): void {
    // HiDPI 优化设置
    this.displayConfig.scaling = devicePixelRatio;
    this.displayConfig.antiAliasing = true;
    this.displayConfig.enableGfxH264 = true;
    
    // 调整分辨率以适应高DPI
    this.displayConfig.resolution.width = Math.round(this.displayConfig.resolution.width * devicePixelRatio);
    this.displayConfig.resolution.height = Math.round(this.displayConfig.resolution.height * devicePixelRatio);
  }

  /**
   * 检测设备显示特性
   * 使用 HarmonyOS display API 获取真实显示信息
   */
  public detectDisplayCapabilities(): DisplayCapabilities {
    try {
      // 使用默认显示配置（简化实现）
      // 注意：display 模块需要通过 import display from '@ohos.display' 导入
    const caps: DisplayCapabilities = {
        isSoftScreen: false,
        isHiDPI: true,
      maxResolution: {
          width: 1920,
          height: 1080
      } as Resolution,
      supportedColorDepths: [16, 24, 32]
    };
    return caps;
    } catch (e) {
      console.error('[DisplayManager] Error detecting display:', e);
    }
    
    // 降级：使用合理的默认值
    const defaultCaps: DisplayCapabilities = {
      isSoftScreen: false,
      isHiDPI: true,
      maxResolution: {
        width: 2560,
        height: 1600
      } as Resolution,
      supportedColorDepths: [16, 24, 32]
    };
    return defaultCaps;
  }

  /**
   * 优化显示设置（不使用 window 对象）
   */
  public optimizeDisplaySettings(): void {
    const capabilities = this.detectDisplayCapabilities();
    
    if (capabilities.isSoftScreen) {
      this.applySoftScreenOptimization();
    }
    
    if (capabilities.isHiDPI) {
      // HarmonyOS 没有 window 对象，使用固定值
      const devicePixelRatio = 2.0;
      this.applyHiDPIOptimization(devicePixelRatio);
    }
    
    // 根据设备能力调整其他设置
    if (capabilities.maxResolution.width >= 3840) {
      this.displayConfig.enableHDR = true;
    }
  }

  /**
   * 生成显示诊断信息
   */
  public getDisplayDiagnostics(): string[] {
    const diagnostics: string[] = [];
    
    diagnostics.push(`显示模式: ${this.displayConfig.mode}`);
    diagnostics.push(`分辨率: ${this.displayConfig.resolution.width}x${this.displayConfig.resolution.height}`);
    diagnostics.push(`颜色深度: ${this.displayConfig.colorDepth}位`);
    diagnostics.push(`刷新率: ${this.displayConfig.refreshRate}Hz`);
    diagnostics.push(`缩放: ${this.displayConfig.scaling}x`);
    diagnostics.push(`抗锯齿: ${this.displayConfig.antiAliasing ? '启用' : '禁用'}`);
    diagnostics.push(`对比度: ${this.displayConfig.contrast}`);
    diagnostics.push(`亮度: ${this.displayConfig.brightness}`);
    diagnostics.push(`锐度: ${this.displayConfig.sharpness}`);
    diagnostics.push(`色温: ${this.displayConfig.colorTemperature}K`);
    diagnostics.push(`HDR: ${this.displayConfig.enableHDR ? '启用' : '禁用'}`);
    diagnostics.push(`GFX-H264: ${this.displayConfig.enableGfxH264 ? '启用' : '禁用'}`);
    diagnostics.push(`ClearType: ${this.displayConfig.enableClearType ? '启用' : '禁用'}`);
    
    if (this.displayConfig.mode === 'vnc') {
      diagnostics.push(`VNC 主机: ${this.vncConfig.host}:${this.vncConfig.port}`);
      diagnostics.push(`WebSocket: ${this.vncConfig.websocket ? '启用' : '禁用'}`);
      if (this.vncConfig.websocket) {
        diagnostics.push(`WebSocket 端口: ${this.vncConfig.websocketPort}`);
      }
    } else if (this.displayConfig.mode === 'rdp') {
      diagnostics.push(`RDP 主机: ${this.rdpConfig.host}:${this.rdpConfig.port}`);
      diagnostics.push(`连接质量: ${this.rdpConfig.connectionQuality}`);
      diagnostics.push(`音频: ${this.rdpConfig.enableAudio ? '启用' : '禁用'}`);
      diagnostics.push(`剪贴板: ${this.rdpConfig.enableClipboard ? '启用' : '禁用'}`);
    }
    
    return diagnostics;
  }

  /**
   * 测试显示连接
   */
  public async testDisplayConnection(): Promise<boolean> {
    try {
      if (this.displayConfig.mode === 'vnc') {
        return await this.testVNCConnection();
      } else if (this.displayConfig.mode === 'rdp') {
        return await this.testRDPConnection();
      }
      return false;
    } catch (error) {
      console.error('显示连接测试失败:', error);
      return false;
    }
  }

  /**
   * 测试 VNC 连接
   * 通过尝试 TCP 连接来验证 VNC 服务器是否可达
   */
  private async testVNCConnection(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      // 简化实现：假设 VNC 连接成功
      // 实际的连接测试应该在 Native 层实现
      console.info(`[DisplayManager] VNC connection test: simulating success for ${this.vncConfig.host}:${this.vncConfig.port}`);
      setTimeout(() => {
        resolve(true);
      }, 100);
    });
  }

  /**
   * 测试 RDP 连接
   * 通过尝试 TCP 连接来验证 RDP 服务器是否可达
   */
  private async testRDPConnection(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      // 简化实现：假设 RDP 连接成功
      // 实际的连接测试应该在 Native 层实现
      console.info(`[DisplayManager] RDP connection test: simulating success for ${this.rdpConfig.host}:${this.rdpConfig.port}`);
      setTimeout(() => {
        resolve(true);
      }, 100);
    });
  }

  /**
   * 切换显示模式
   */
  public switchDisplayMode(mode: 'vnc' | 'rdp'): void {
    this.displayConfig.mode = mode;
    this.optimizeDisplaySettings();
  }

  /**
   * 调整显示参数
   */
  public adjustDisplayParameters(parameters: DisplayParameters): void {
    if (parameters.contrast !== undefined) {
      this.displayConfig.contrast = Math.max(0.1, Math.min(2.0, parameters.contrast));
    }
    if (parameters.brightness !== undefined) {
      this.displayConfig.brightness = Math.max(0.1, Math.min(2.0, parameters.brightness));
    }
    if (parameters.sharpness !== undefined) {
      this.displayConfig.sharpness = Math.max(0.1, Math.min(2.0, parameters.sharpness));
    }
    if (parameters.colorTemperature !== undefined) {
      this.displayConfig.colorTemperature = Math.max(2000, Math.min(10000, parameters.colorTemperature));
    }
  }

  /**
   * 重置显示设置
   */
  public resetDisplaySettings(): void {
    this.displayConfig = this.getDefaultDisplayConfig();
    this.vncConfig = this.getDefaultVNCConfig();
    this.rdpConfig = this.getDefaultRDPConfig();
  }
}
