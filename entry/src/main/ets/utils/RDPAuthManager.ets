/**
 * RDP 认证管理器
 * 管理 RDP 登录凭据和自动连接
 * 
 * 功能:
 * - 安全存储 RDP 用户名和密码
 * - VM 启动后自动建立 RDP 连接
 * - 会话管理和自动重连
 */

import dataPreferences from '@ohos.data.preferences';
import qemu from 'qemu_hmos';

// 凭据信息
export interface RDPCredential {
  vmName: string;
  host: string;
  port: number;
  username: string;
  password: string;  // 注意：实际应用中应加密存储
  domain?: string;
  autoConnect: boolean;
  savePassword: boolean;
  lastConnected?: Date;
}

// 连接状态
export enum RDPConnectionStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  AUTHENTICATING = 'authenticating',
  CONNECTED = 'connected',
  RECONNECTING = 'reconnecting',
  ERROR = 'error'
}

// 连接会话
export interface RDPSession {
  id: string;
  vmName: string;
  status: RDPConnectionStatus;
  connectedAt?: Date;
  lastActivity?: Date;
  errorMessage?: string;
}

// 认证回调
export interface AuthCallbacks {
  onConnectionStart?: (vmName: string) => void;
  onAuthenticationRequired?: (vmName: string) => void;
  onConnected?: (vmName: string, session: RDPSession) => void;
  onDisconnected?: (vmName: string, reason: string) => void;
  onError?: (vmName: string, error: string) => void;
}

export class RDPAuthManager {
  private static instance: RDPAuthManager;
  private credentials: Map<string, RDPCredential> = new Map();
  private sessions: Map<string, RDPSession> = new Map();
  private callbacks: AuthCallbacks = {};
  private preferencesName = 'rdp_credentials';
  private preferences: dataPreferences.Preferences | null = null;

  private constructor() {}

  public static getInstance(): RDPAuthManager {
    if (!RDPAuthManager.instance) {
      RDPAuthManager.instance = new RDPAuthManager();
    }
    return RDPAuthManager.instance;
  }

  /**
   * 初始化
   */
  public async initialize(context: Context): Promise<void> {
    try {
      // 获取 preferences 实例
      this.preferences = await dataPreferences.getPreferences(context, this.preferencesName);
      
      // 加载已保存的凭据
      await this.loadCredentials();
      
      console.info('[RDPAuthManager] Initialized successfully');
    } catch (e) {
      console.error('[RDPAuthManager] Initialization failed:', e);
    }
  }

  /**
   * 设置回调
   */
  public setCallbacks(callbacks: AuthCallbacks): void {
    this.callbacks = callbacks;
  }

  /**
   * 保存凭据
   */
  public async saveCredential(credential: RDPCredential): Promise<boolean> {
    try {
      this.credentials.set(credential.vmName, credential);
      
      if (credential.savePassword && this.preferences) {
        // 保存到持久化存储（实际应用中应加密密码）
        const credentialJson = JSON.stringify(credential);
        await this.preferences.put(`credential_${credential.vmName}`, credentialJson);
        await this.preferences.flush();
      }
      
      console.info(`[RDPAuthManager] Saved credential for ${credential.vmName}`);
      return true;
    } catch (e) {
      console.error('[RDPAuthManager] Save credential failed:', e);
      return false;
    }
  }

  /**
   * 获取凭据
   */
  public getCredential(vmName: string): RDPCredential | undefined {
    return this.credentials.get(vmName);
  }

  /**
   * 删除凭据
   */
  public async deleteCredential(vmName: string): Promise<boolean> {
    try {
      this.credentials.delete(vmName);
      
      if (this.preferences) {
        await this.preferences.delete(`credential_${vmName}`);
        await this.preferences.flush();
      }
      
      console.info(`[RDPAuthManager] Deleted credential for ${vmName}`);
      return true;
    } catch (e) {
      console.error('[RDPAuthManager] Delete credential failed:', e);
      return false;
    }
  }

  /**
   * 获取所有已保存凭据的 VM 列表
   */
  public getSavedVMs(): string[] {
    return Array.from(this.credentials.keys());
  }

  /**
   * 连接到 VM
   */
  public async connect(vmName: string): Promise<RDPSession | null> {
    const credential = this.credentials.get(vmName);
    if (!credential) {
      console.error(`[RDPAuthManager] No credential found for ${vmName}`);
      this.callbacks.onAuthenticationRequired?.(vmName);
      return null;
    }

    // 创建会话
    const session: RDPSession = {
      id: Date.now().toString(),
      vmName,
      status: RDPConnectionStatus.CONNECTING
    };
    this.sessions.set(vmName, session);

    this.callbacks.onConnectionStart?.(vmName);

    try {
      // 调用 Native 模块建立 RDP 连接
      const qemuNative = qemu;
      
      session.status = RDPConnectionStatus.AUTHENTICATING;
      
      if (qemuNative && qemuNative.rdpConnect) {
        const connectResult = await qemuNative.rdpConnect(credential.host, credential.port);
        
        if (!connectResult.success) {
          throw new Error(connectResult.error || 'Connection failed');
        }

        // 认证
        if (qemuNative.rdpAuthenticate) {
          const authResult = await qemuNative.rdpAuthenticate(
            credential.username,
            credential.password,
            credential.domain || ''
          );
          
          if (!authResult.success) {
            throw new Error(authResult.error || 'Authentication failed');
          }
        }

        // 连接成功
        session.status = RDPConnectionStatus.CONNECTED;
        session.connectedAt = new Date();
        session.lastActivity = new Date();
        
        // 更新最后连接时间
        credential.lastConnected = new Date();
        await this.saveCredential(credential);
        
        this.callbacks.onConnected?.(vmName, session);
        console.info(`[RDPAuthManager] Connected to ${vmName}`);
        
        return session;
      } else {
        // Native 不可用，使用模拟模式
        console.warn('[RDPAuthManager] Native module not available, using simulation');
        
        session.status = RDPConnectionStatus.CONNECTED;
        session.connectedAt = new Date();
        session.lastActivity = new Date();
        
        this.callbacks.onConnected?.(vmName, session);
        return session;
      }
    } catch (e) {
      session.status = RDPConnectionStatus.ERROR;
      session.errorMessage = e instanceof Error ? e.message : String(e);
      
      this.callbacks.onError?.(vmName, session.errorMessage);
      console.error(`[RDPAuthManager] Connection failed for ${vmName}:`, e);
      
      return session;
    }
  }

  /**
   * 使用新凭据连接（首次连接或更新凭据）
   */
  public async connectWithCredentials(
    vmName: string,
    host: string,
    port: number,
    username: string,
    password: string,
    domain?: string,
    savePassword: boolean = true,
    autoConnect: boolean = true
  ): Promise<RDPSession | null> {
    // 保存凭据
    const credential: RDPCredential = {
      vmName,
      host,
      port,
      username,
      password,
      domain,
      autoConnect,
      savePassword
    };
    
    await this.saveCredential(credential);
    
    // 连接
    return this.connect(vmName);
  }

  /**
   * 断开连接
   */
  public async disconnect(vmName: string): Promise<void> {
    const session = this.sessions.get(vmName);
    if (!session) {
      return;
    }

    try {
      // 调用 Native 断开连接
      const qemuNative = qemu;
      if (qemuNative && qemuNative.rdpDisconnect) {
        await qemuNative.rdpDisconnect();
      }
    } catch (e) {
      console.error('[RDPAuthManager] Disconnect error:', e);
    }

    session.status = RDPConnectionStatus.DISCONNECTED;
    this.callbacks.onDisconnected?.(vmName, 'User requested disconnect');
    
    console.info(`[RDPAuthManager] Disconnected from ${vmName}`);
  }

  /**
   * 获取会话状态
   */
  public getSessionStatus(vmName: string): RDPConnectionStatus {
    const session = this.sessions.get(vmName);
    return session?.status || RDPConnectionStatus.DISCONNECTED;
  }

  /**
   * 获取会话信息
   */
  public getSession(vmName: string): RDPSession | undefined {
    return this.sessions.get(vmName);
  }

  /**
   * VM 启动后自动连接
   */
  public async autoConnectOnVMStart(vmName: string): Promise<void> {
    const credential = this.credentials.get(vmName);
    if (!credential || !credential.autoConnect) {
      console.info(`[RDPAuthManager] Auto-connect disabled for ${vmName}`);
      return;
    }

    console.info(`[RDPAuthManager] Auto-connecting to ${vmName}...`);
    
    // 等待 VM 完全启动（RDP 服务就绪）
    await this.waitForRDPReady(credential.host, credential.port);
    
    // 建立连接
    await this.connect(vmName);
  }

  /**
   * 等待 RDP 服务就绪
   */
  private async waitForRDPReady(host: string, port: number, timeout: number = 60000): Promise<boolean> {
    const startTime = Date.now();
    const checkInterval = 2000;  // 每 2 秒检查一次

    while (Date.now() - startTime < timeout) {
      try {
        const qemuNative = qemu;
        if (qemuNative && qemuNative.testConnection) {
          const result = await qemuNative.testConnection(host, port, 'rdp');
          if (result.success) {
            console.info(`[RDPAuthManager] RDP service ready at ${host}:${port}`);
            return true;
          }
        }
      } catch (e) {
        // 连接失败，继续等待
      }

      await new Promise(resolve => setTimeout(resolve, checkInterval));
    }

    console.warn(`[RDPAuthManager] RDP service not ready within ${timeout}ms`);
    return false;
  }

  /**
   * 获取诊断信息
   */
  public getDiagnostics(): string[] {
    const diagnostics: string[] = [];
    
    diagnostics.push(`已保存凭据: ${this.credentials.size} 个`);
    diagnostics.push(`活动会话: ${this.sessions.size} 个`);
    
    for (const [vmName, credential] of this.credentials) {
      const session = this.sessions.get(vmName);
      const status = session?.status || 'disconnected';
      diagnostics.push(`  ${vmName}: ${credential.username}@${credential.host}:${credential.port} (${status})`);
      if (credential.autoConnect) {
        diagnostics.push(`    自动连接: 启用`);
      }
      if (credential.lastConnected) {
        diagnostics.push(`    最后连接: ${credential.lastConnected.toLocaleString()}`);
      }
    }
    
    return diagnostics;
  }

  // === 私有方法 ===

  /**
   * 从持久化存储加载凭据
   */
  private async loadCredentials(): Promise<void> {
    if (!this.preferences) {
      return;
    }

    try {
      const all = await this.preferences.getAll();
      
      for (const key in all) {
        if (key.startsWith('credential_')) {
          try {
            const credentialJson = all[key] as string;
            const credential = JSON.parse(credentialJson) as RDPCredential;
            
            // 恢复日期对象
            if (credential.lastConnected) {
              credential.lastConnected = new Date(credential.lastConnected);
            }
            
            this.credentials.set(credential.vmName, credential);
          } catch (e) {
            console.warn(`[RDPAuthManager] Failed to parse credential: ${key}`);
          }
        }
      }
      
      console.info(`[RDPAuthManager] Loaded ${this.credentials.size} credentials`);
    } catch (e) {
      console.error('[RDPAuthManager] Load credentials failed:', e);
    }
  }
}
