/**
 * 自定义标题栏组件 - 鸿蒙规范
 * 高度：50px（华为要求）
 * 
 * 注意：在自由多窗模式下，系统已经提供了三大金刚键，我们只显示搜索框
 */
import window from '@ohos.window'
import hilog from '@ohos.hilog'

@Component
export struct CustomTitleBar {
  // 窗口状态
  @State isMaximized: boolean = false
  @State isHoveringClose: boolean = false
  @State isHoveringMax: boolean = false
  @State isHoveringMin: boolean = false
  
  // 外部传入
  @Prop windowTitle: string = 'QEMU 鸿蒙版'
  @Prop showSearch: boolean = true
  @Prop showWindowControls: boolean = false  // 是否显示窗口控制按钮（三大金刚键）
  
  // 回调
  onSearchClick?: () => void
  
  // 窗口操作
  private async minimizeWindow(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this))
      await win.minimize()
    } catch (e) {
      hilog.error(0x0000, 'TITLEBAR', '最小化失败: %{public}s', (e as Error).message)
    }
  }
  
  private async toggleMaximize(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this))
      if (this.isMaximized) {
        await win.recover()
      } else {
        await win.maximize()
      }
      this.isMaximized = !this.isMaximized
    } catch (e) {
      hilog.error(0x0000, 'TITLEBAR', '最大化切换失败: %{public}s', (e as Error).message)
    }
  }
  
  private async closeWindow(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this))
      await win.destroyWindow()
    } catch (e) {
      hilog.error(0x0000, 'TITLEBAR', '关闭窗口失败: %{public}s', (e as Error).message)
    }
  }

  build() {
    Row() {
      // 左侧：应用图标和名称
      Row() {
        Image($r('app.media.app_icon'))
          .width(22)
          .height(22)
          .margin({ left: 16, right: 10 })
        Text(this.windowTitle)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
      }
      .height('100%')
      .alignItems(VerticalAlign.Center)
      
      // 中间占位 + 搜索框（居中，最大宽度 1000px）
      Blank()
      
      if (this.showSearch) {
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(15)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ right: 10 })
          Text('搜索虚拟机或输入 / 执行命令...')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
            .maxLines(1)
          
          // 快捷键提示
          Row() {
            Text('Ctrl+Alt+C')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(4)
        }
        .width('100%')
        .constraintSize({ maxWidth: 600 }) // 搜索框最大宽度
        .height(34)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.sidebar_background'))
        .borderRadius(8)
        .onClick((): void => {
          if (this.onSearchClick) this.onSearchClick()
        })
        .hoverEffect(HoverEffect.Highlight)
      }
      
      Blank()
      
      // 右侧：窗口控制按钮（仅在需要时显示，自由多窗模式下系统已提供）
      if (this.showWindowControls) {
        Row() {
          // 最大化/还原
          Row() {
            SymbolGlyph(this.isMaximized ? $r('sys.symbol.rectangle_on_rectangle') : $r('sys.symbol.square'))
              .fontSize(13)
              .fontColor([this.isHoveringMax ? $r('app.color.text_primary') : $r('app.color.text_secondary')])
          }
          .width(50)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.isHoveringMax ? $r('app.color.sidebar_background') : Color.Transparent)
          .onClick((): void => { this.toggleMaximize() })
          .onHover((isHover: boolean): void => { this.isHoveringMax = isHover })
          
          // 最小化
          Row() {
            SymbolGlyph($r('sys.symbol.minus'))
              .fontSize(15)
              .fontColor([this.isHoveringMin ? $r('app.color.text_primary') : $r('app.color.text_secondary')])
          }
          .width(50)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.isHoveringMin ? $r('app.color.sidebar_background') : Color.Transparent)
          .onClick((): void => { this.minimizeWindow() })
          .onHover((isHover: boolean): void => { this.isHoveringMin = isHover })
          
          // 退出（关闭）
          Row() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(15)
              .fontColor([this.isHoveringClose ? Color.White : $r('app.color.text_secondary')])
          }
          .width(50)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.isHoveringClose ? '#E81123' : Color.Transparent)
          .onClick((): void => { this.closeWindow() })
          .onHover((isHover: boolean): void => { this.isHoveringClose = isHover })
        }
        .height('100%')
      }
    }
    .width('100%')
    .height(50) // 华为要求至少 50px
    .backgroundColor($r('app.color.titlebar_background'))
  }
}
