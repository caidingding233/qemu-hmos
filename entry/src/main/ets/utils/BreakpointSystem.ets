/**
 * 响应式断点系统
 * 
 * 断点定义（基于窗口宽度 vp）：
 * - xs: < 320vp  - 超小悬浮窗
 * - sm: 320-600vp - 小屏（手机竖屏、小悬浮窗）
 * - md: 600-840vp - 中屏（手机横屏、中等悬浮窗）
 * - lg: > 840vp   - 大屏（平板、电脑）
 * 
 * 布局策略：
 * - xs/sm: 竖屏布局，TabBar 在底部，使用手机风格半模态
 * - md/lg: 横屏布局，TabBar 在左侧，使用平板风格半模态
 */
import window from '@ohos.window'
import display from '@ohos.display'
import hilog from '@ohos.hilog'

// 断点类型
export type BreakpointType = 'xs' | 'sm' | 'md' | 'lg'

// 断点阈值（单位：vp）
const BREAKPOINT_XS = 320
const BREAKPOINT_SM = 600
const BREAKPOINT_MD = 840

// 布局模式
export type LayoutMode = 'compact' | 'medium' | 'expanded'

// 断点信息
export interface BreakpointInfo {
  breakpoint: BreakpointType
  layoutMode: LayoutMode
  windowWidth: number
  windowHeight: number
  isPortrait: boolean        // 是否竖屏
  isCompact: boolean         // 是否紧凑模式（xs/sm）
  tabBarPosition: 'bottom' | 'left'  // TabBar 位置
  usePhoneSheet: boolean     // 是否使用手机风格半模态
}

/**
 * 断点系统管理器
 */
export class BreakpointSystem {
  private static instance: BreakpointSystem | null = null
  
  private constructor() {}
  
  static getInstance(): BreakpointSystem {
    if (!BreakpointSystem.instance) {
      BreakpointSystem.instance = new BreakpointSystem()
    }
    return BreakpointSystem.instance
  }
  
  /**
   * 根据窗口宽度计算断点
   */
  static getBreakpoint(widthVp: number): BreakpointType {
    if (widthVp < BREAKPOINT_XS) {
      return 'xs'
    } else if (widthVp < BREAKPOINT_SM) {
      return 'sm'
    } else if (widthVp < BREAKPOINT_MD) {
      return 'md'
    } else {
      return 'lg'
    }
  }
  
  /**
   * 根据断点获取布局模式
   */
  static getLayoutMode(breakpoint: BreakpointType): LayoutMode {
    switch (breakpoint) {
      case 'xs':
      case 'sm':
        return 'compact'
      case 'md':
        return 'medium'
      case 'lg':
        return 'expanded'
    }
  }
  
  /**
   * 计算完整的断点信息
   */
  static calculateBreakpointInfo(windowWidth: number, windowHeight: number): BreakpointInfo {
    const breakpoint = BreakpointSystem.getBreakpoint(windowWidth)
    const layoutMode = BreakpointSystem.getLayoutMode(breakpoint)
    const isPortrait = windowHeight > windowWidth
    const isCompact = breakpoint === 'xs' || breakpoint === 'sm'
    
    // TabBar 位置：紧凑模式在底部，其他在左侧
    const tabBarPosition: 'bottom' | 'left' = isCompact ? 'bottom' : 'left'
    
    // 半模态样式：紧凑模式使用手机风格（从底部滑出），其他使用居中弹窗
    const usePhoneSheet = isCompact
    
    return {
      breakpoint,
      layoutMode,
      windowWidth,
      windowHeight,
      isPortrait,
      isCompact,
      tabBarPosition,
      usePhoneSheet
    }
  }
  
  /**
   * 获取当前显示器信息并计算断点
   */
  static async getCurrentBreakpointInfo(): Promise<BreakpointInfo> {
    try {
      const displayInfo = display.getDefaultDisplaySync()
      // px 转 vp: vp = px / density
      const density = displayInfo.densityPixels || 1
      const widthVp = displayInfo.width / density
      const heightVp = displayInfo.height / density
      
      hilog.info(0x0000, 'BREAKPOINT', '显示器: %{public}dx%{public}d px, density=%{public}f, vp=%{public}dx%{public}d',
        displayInfo.width, displayInfo.height, density, widthVp, heightVp)
      
      return BreakpointSystem.calculateBreakpointInfo(widthVp, heightVp)
    } catch (e) {
      hilog.error(0x0000, 'BREAKPOINT', '获取显示器信息失败: %{public}s', (e as Error).message)
      // 默认返回大屏配置
      return BreakpointSystem.calculateBreakpointInfo(1200, 800)
    }
  }
}

/**
 * 初始化断点系统到 AppStorage
 * 在 EntryAbility 中调用
 */
export function initBreakpointStorage(): void {
  // 初始化默认值（大屏配置）
  const defaultInfo: BreakpointInfo = {
    breakpoint: 'lg',
    layoutMode: 'expanded',
    windowWidth: 1200,
    windowHeight: 800,
    isPortrait: false,
    isCompact: false,
    tabBarPosition: 'left',
    usePhoneSheet: false
  }
  
  AppStorage.setOrCreate<string>('currentBreakpoint', defaultInfo.breakpoint)
  AppStorage.setOrCreate<string>('layoutMode', defaultInfo.layoutMode)
  AppStorage.setOrCreate<number>('windowWidth', defaultInfo.windowWidth)
  AppStorage.setOrCreate<number>('windowHeight', defaultInfo.windowHeight)
  AppStorage.setOrCreate<boolean>('isPortrait', defaultInfo.isPortrait)
  AppStorage.setOrCreate<boolean>('isCompact', defaultInfo.isCompact)
  AppStorage.setOrCreate<string>('tabBarPosition', defaultInfo.tabBarPosition)
  AppStorage.setOrCreate<boolean>('usePhoneSheet', defaultInfo.usePhoneSheet)
  
  hilog.info(0x0000, 'BREAKPOINT', '断点系统已初始化')
}

/**
 * 更新断点信息到 AppStorage
 * 在窗口尺寸变化时调用
 */
export function updateBreakpointStorage(windowWidth: number, windowHeight: number): void {
  const info = BreakpointSystem.calculateBreakpointInfo(windowWidth, windowHeight)
  
  AppStorage.set<string>('currentBreakpoint', info.breakpoint)
  AppStorage.set<string>('layoutMode', info.layoutMode)
  AppStorage.set<number>('windowWidth', windowWidth)
  AppStorage.set<number>('windowHeight', windowHeight)
  AppStorage.set<boolean>('isPortrait', info.isPortrait)
  AppStorage.set<boolean>('isCompact', info.isCompact)
  AppStorage.set<string>('tabBarPosition', info.tabBarPosition)
  AppStorage.set<boolean>('usePhoneSheet', info.usePhoneSheet)
  
  hilog.info(0x0000, 'BREAKPOINT', '断点更新: %{public}s, layout=%{public}s, compact=%{public}s, tabBar=%{public}s',
    info.breakpoint, info.layoutMode, String(info.isCompact), info.tabBarPosition)
}

