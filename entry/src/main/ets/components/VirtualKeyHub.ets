/**
 * 虚拟按键Hub组件
 * 
 * 为触摸屏设备提供特殊按键支持，用于VNC远程桌面操作
 * 包含：修饰键（Ctrl/Alt/Shift/Win）、功能键（F1-F12）、常用组合键
 * 
 * 交互特性：
 * - 悬浮小球收起状态，点击展开
 * - 华为风格弹簧动画
 * - 下滑手势收起
 * - 展开时从底部弹出
 */

import { curves } from '@kit.ArkUI'

// X11 Keysym 定义（显式列出所有字段，避免使用索引签名）
interface KeySymMap {
  // 修饰键
  Shift_L: number
  Shift_R: number
  Control_L: number
  Control_R: number
  Alt_L: number
  Alt_R: number
  Super_L: number
  Super_R: number

  // 功能键
  Escape: number
  Tab: number
  Return: number
  BackSpace: number
  Delete: number
  Insert: number
  Home: number
  End: number
  Page_Up: number
  Page_Down: number

  // 方向键
  Up: number
  Down: number
  Left: number
  Right: number

  // F1-F12
  F1: number
  F2: number
  F3: number
  F4: number
  F5: number
  F6: number
  F7: number
  F8: number
  F9: number
  F10: number
  F11: number
  F12: number

  // 常用字母
  a: number
  c: number
  v: number
  x: number
  z: number
  s: number
  f: number
  p: number
  w: number
  t: number
  n: number
  r: number

  // 特殊键
  Print: number
  Scroll_Lock: number
  Pause: number
  Num_Lock: number
  Caps_Lock: number
}

const KeySym: KeySymMap = {
  // 修饰键
  Shift_L: 0xFFE1,
  Shift_R: 0xFFE2,
  Control_L: 0xFFE3,
  Control_R: 0xFFE4,
  Alt_L: 0xFFE9,
  Alt_R: 0xFFEA,
  Super_L: 0xFFEB,      // Windows/鸿蒙键
  Super_R: 0xFFEC,
  
  // 功能键
  Escape: 0xFF1B,
  Tab: 0xFF09,
  Return: 0xFF0D,
  BackSpace: 0xFF08,
  Delete: 0xFFFF,
  Insert: 0xFF63,
  Home: 0xFF50,
  End: 0xFF57,
  Page_Up: 0xFF55,
  Page_Down: 0xFF56,
  
  // 方向键
  Up: 0xFF52,
  Down: 0xFF54,
  Left: 0xFF51,
  Right: 0xFF53,
  
  // F1-F12
  F1: 0xFFBE,
  F2: 0xFFBF,
  F3: 0xFFC0,
  F4: 0xFFC1,
  F5: 0xFFC2,
  F6: 0xFFC3,
  F7: 0xFFC4,
  F8: 0xFFC5,
  F9: 0xFFC6,
  F10: 0xFFC7,
  F11: 0xFFC8,
  F12: 0xFFC9,
  
  // 常用字母（用于组合键）
  a: 0x61,
  c: 0x63,
  v: 0x76,
  x: 0x78,
  z: 0x7A,
  s: 0x73,
  f: 0x66,
  p: 0x70,
  w: 0x77,
  t: 0x74,
  n: 0x6E,
  r: 0x72,
  
  // 特殊键
  Print: 0xFF61,        // Print Screen
  Scroll_Lock: 0xFF14,
  Pause: 0xFF13,
  Num_Lock: 0xFF7F,
  Caps_Lock: 0xFFE5,
}

// 按键配置接口
interface VirtualKey {
  label: string
  icon?: Resource
  keysym: number
  isModifier?: boolean
  width?: number        // 按键宽度倍数，默认1
  color?: string
}

// 组合键配置
interface ComboKey {
  label: string
  icon?: Resource
  modifiers: number[]
  key: number
  description?: string
}

// 按键发送回调
export interface VirtualKeyHubCallbacks {
  onKeyDown?: (keysym: number) => void
  onKeyUp?: (keysym: number) => void
  onCombo?: (modifiers: number[], key: number) => void
}

@Component
export struct VirtualKeyHub {
  // 回调函数
  callbacks?: VirtualKeyHubCallbacks
  
  // 内部状态
  @State isExpanded: boolean = false
  @State activeTab: number = 0  // 0: 修饰键, 1: 功能键, 2: 组合键, 3: 导航键
  
  // 修饰键状态（用于锁定）
  @State ctrlLocked: boolean = false
  @State altLocked: boolean = false
  @State shiftLocked: boolean = false
  @State winLocked: boolean = false
  
  // 修饰键定义
  private modifierKeys: VirtualKey[] = [
    { label: 'Ctrl', keysym: KeySym.Control_L, isModifier: true, color: '#FF6B6B' },
    { label: 'Alt', keysym: KeySym.Alt_L, isModifier: true, color: '#4ECDC4' },
    { label: 'Shift', keysym: KeySym.Shift_L, isModifier: true, color: '#45B7D1' },
    { label: '', icon: $r('app.media.ic_harmony_key'), keysym: KeySym.Super_L, isModifier: true, color: '#0078D4' },  // 鸿蒙键/Windows
    { label: '', icon: $r('app.media.ic_xiaoyi_key'), keysym: KeySym.Super_R, isModifier: true, color: '#9B59B6' },  // 小艺键/Copilot
  ]
  
  // 功能键定义
  private functionKeys: VirtualKey[] = [
    { label: 'Esc', keysym: KeySym.Escape, color: '#E74C3C' },
    { label: 'F1', keysym: KeySym.F1 },
    { label: 'F2', keysym: KeySym.F2 },
    { label: 'F3', keysym: KeySym.F3 },
    { label: 'F4', keysym: KeySym.F4 },
    { label: 'F5', keysym: KeySym.F5 },
    { label: 'F6', keysym: KeySym.F6 },
    { label: 'F7', keysym: KeySym.F7 },
    { label: 'F8', keysym: KeySym.F8 },
    { label: 'F9', keysym: KeySym.F9 },
    { label: 'F10', keysym: KeySym.F10 },
    { label: 'F11', keysym: KeySym.F11 },
    { label: 'F12', keysym: KeySym.F12 },
  ]
  
  // 导航键定义
  private navKeys: VirtualKey[] = [
    { label: 'Tab', keysym: KeySym.Tab, width: 1.5 },
    { label: '⌫', keysym: KeySym.BackSpace },
    { label: 'Del', keysym: KeySym.Delete },
    { label: 'Ins', keysym: KeySym.Insert },
    { label: 'Home', keysym: KeySym.Home },
    { label: 'End', keysym: KeySym.End },
    { label: 'PgUp', keysym: KeySym.Page_Up },
    { label: 'PgDn', keysym: KeySym.Page_Down },
    { label: '↑', keysym: KeySym.Up },
    { label: '↓', keysym: KeySym.Down },
    { label: '←', keysym: KeySym.Left },
    { label: '→', keysym: KeySym.Right },
    { label: '⏎', keysym: KeySym.Return, width: 1.5, color: '#2ECC71' },
  ]
  
  // 常用组合键
  private comboKeys: ComboKey[] = [
    { label: '复制', modifiers: [KeySym.Control_L], key: KeySym.c, description: 'Ctrl+C' },
    { label: '粘贴', modifiers: [KeySym.Control_L], key: KeySym.v, description: 'Ctrl+V' },
    { label: '剪切', modifiers: [KeySym.Control_L], key: KeySym.x, description: 'Ctrl+X' },
    { label: '撤销', modifiers: [KeySym.Control_L], key: KeySym.z, description: 'Ctrl+Z' },
    { label: '保存', modifiers: [KeySym.Control_L], key: KeySym.s, description: 'Ctrl+S' },
    { label: '查找', modifiers: [KeySym.Control_L], key: KeySym.f, description: 'Ctrl+F' },
    { label: '全选', modifiers: [KeySym.Control_L], key: KeySym.a, description: 'Ctrl+A' },
    { label: '打印', modifiers: [KeySym.Control_L], key: KeySym.p, description: 'Ctrl+P' },
    { label: '新建', modifiers: [KeySym.Control_L], key: KeySym.n, description: 'Ctrl+N' },
    { label: '新标签', modifiers: [KeySym.Control_L], key: KeySym.t, description: 'Ctrl+T' },
    { label: '关闭', modifiers: [KeySym.Control_L], key: KeySym.w, description: 'Ctrl+W' },
    { label: '刷新', modifiers: [KeySym.Control_L], key: KeySym.r, description: 'Ctrl+R' },
    { label: '任务管理器', modifiers: [KeySym.Control_L, KeySym.Shift_L], key: KeySym.Escape, description: 'Ctrl+Shift+Esc' },
    { label: '安全选项', modifiers: [KeySym.Control_L, KeySym.Alt_L], key: KeySym.Delete, description: 'Ctrl+Alt+Del' },
    { label: '切换窗口', modifiers: [KeySym.Alt_L], key: KeySym.Tab, description: 'Alt+Tab' },
    { label: '截图', modifiers: [KeySym.Super_L, KeySym.Shift_L], key: KeySym.s, description: 'Win+Shift+S' },
  ]
  
  // Tab 标签
  private tabs: string[] = ['修饰键', '功能键', '组合键', '导航键']
  
  // 华为弹簧动画参数
  private springMotion = curves.springMotion(0.35, 0.9, 0)  // 响应度、阻尼比、过冲
  private responsiveSpring = curves.responsiveSpringMotion(0.35, 0.9, 0)
  
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 收起状态：悬浮小球按钮
      if (!this.isExpanded) {
        Row() {
          // 悬浮小球
          Row() {
            Text('⌨')
              .fontSize(20)
              .fontColor('#FFFFFF')
          }
          .width(48)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0, 122, 255, 0.9)')
          .borderRadius(24)
          .shadow({
            radius: 12,
            color: 'rgba(0, 122, 255, 0.4)',
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => {
            // 华为弹簧动画展开
            animateTo({
              duration: 400,
              curve: this.springMotion,
              onFinish: () => {}
            }, () => {
              this.isExpanded = true
            })
          })
          .gesture(
            // 长按显示提示
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction(() => {
                // 可以添加震动反馈
              })
          )
          .scale({ x: this.isExpanded ? 0 : 1, y: this.isExpanded ? 0 : 1 })
          .opacity(this.isExpanded ? 0 : 1)
          
          // 修饰键状态指示器（收起时也显示）
          if (this.ctrlLocked || this.altLocked || this.shiftLocked || this.winLocked) {
            Row() {
              if (this.ctrlLocked) this.ModifierIndicator('C', '#FF6B6B')
              if (this.altLocked) this.ModifierIndicator('A', '#4ECDC4')
              if (this.shiftLocked) this.ModifierIndicator('S', '#45B7D1')
              if (this.winLocked) this.ModifierIndicator('W', '#0078D4')
            }
            .margin({ left: 8 })
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('rgba(0, 0, 0, 0.6)')
            .borderRadius(12)
          }
        }
        .margin({ bottom: 16 })
        // 小球出现/消失动画（与面板动画配合）
        .transition(
          TransitionEffect.asymmetric(
            // 入场：从面板缩小位置弹出
            TransitionEffect.scale({ x: 0.3, y: 0.3 })
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 350, curve: this.springMotion, delay: 100 }),
            // 出场：缩小消失（让位给面板展开）
            TransitionEffect.scale({ x: 0.3, y: 0.3 })
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 150, curve: Curve.EaseIn })
          )
        )
      }
      
      // 展开状态：完整键盘面板
      if (this.isExpanded) {
        Column() {
          // 顶部拖动条 + 收起按钮
          Row() {
            // 拖动条指示器
            Row()
              .width(40)
              .height(4)
              .backgroundColor('rgba(255, 255, 255, 0.3)')
              .borderRadius(2)
          }
          .width('100%')
          .height(24)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            // 华为弹簧动画收起
            animateTo({
              duration: 350,
              curve: this.responsiveSpring,
            }, () => {
              this.isExpanded = false
            })
          })
          .gesture(
            // 下滑手势收起
            PanGesture({ direction: PanDirection.Down })
              .onActionEnd((event: GestureEvent) => {
                if (event && event.offsetY > 50) {
                  animateTo({
                    duration: 300,
                    curve: this.springMotion,
                  }, () => {
                    this.isExpanded = false
                  })
                }
              })
          )
          
          // Tab 切换栏
          Row() {
            ForEach(this.tabs, (tab: string, index: number) => {
              Column() {
                Text(tab)
                  .fontSize(13)
                  .fontColor(this.activeTab === index ? '#FFFFFF' : '#888888')
                  .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
                
                // 选中指示器
                Row()
                  .width(this.activeTab === index ? 20 : 0)
                  .height(3)
                  .backgroundColor('#007AFF')
                  .borderRadius(1.5)
                  .margin({ top: 4 })
              }
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => {
                animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                  this.activeTab = index
                })
              })
            })
            
            Blank()
            
            // 收起按钮
            Button({ type: ButtonType.Circle }) {
              Text('✕')
                .fontSize(14)
                .fontColor('#888888')
            }
            .width(28)
            .height(28)
            .backgroundColor('rgba(255, 255, 255, 0.1)')
            .margin({ right: 12 })
            .onClick(() => {
              animateTo({
                duration: 300,
                curve: this.springMotion,
              }, () => {
                this.isExpanded = false
              })
            })
          }
          .width('100%')
          .padding({ left: 8 })
          
          // 修饰键锁定状态指示器
          if (this.ctrlLocked || this.altLocked || this.shiftLocked || this.winLocked) {
            Row() {
              Text('已锁定: ')
                .fontSize(11)
                .fontColor('#666666')
              if (this.ctrlLocked) this.ModifierIndicator('Ctrl', '#FF6B6B')
              if (this.altLocked) this.ModifierIndicator('Alt', '#4ECDC4')
              if (this.shiftLocked) this.ModifierIndicator('Shift', '#45B7D1')
              if (this.winLocked) this.ModifierIndicator('Win', '#0078D4')
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            .justifyContent(FlexAlign.Start)
          }
          
          // 键盘内容区
          Column() {
            if (this.activeTab === 0) {
              this.ModifierKeysPanel()
            } else if (this.activeTab === 1) {
              this.FunctionKeysPanel()
            } else if (this.activeTab === 2) {
              this.ComboKeysPanel()
            } else {
              this.NavKeysPanel()
            }
          }
          .width('100%')
        }
        .width('100%')
        .backgroundColor('rgba(25, 25, 25, 0.98)')
        .borderRadius({ topLeft: 20, topRight: 20 })
        .padding({ bottom: 20 })
        .shadow({
          radius: 20,
          color: 'rgba(0, 0, 0, 0.5)',
          offsetX: 0,
          offsetY: -4
        })
        // 从小球位置缩放展开/收起（从哪来回哪去）
        .transition(
          TransitionEffect.asymmetric(
            // 入场：从小球位置放大展开（底部中心缩放）
            TransitionEffect.scale({ x: 0.1, y: 0.1, centerY: '100%' })
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 400, curve: this.springMotion }),
            // 出场：缩小回到小球位置
            TransitionEffect.scale({ x: 0.1, y: 0.1, centerY: '100%' })
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 300, curve: this.responsiveSpring })
          )
        )
      }
    }
    .width('100%')
    .height('100%')
  }
  
  @Builder
  ModifierIndicator(label: string, color: string) {
    Text(label)
      .fontSize(10)
      .fontColor('#FFFFFF')
      .fontWeight(FontWeight.Bold)
      .width(18)
      .height(18)
      .textAlign(TextAlign.Center)
      .backgroundColor(color)
      .borderRadius(9)
      .margin({ left: 4 })
  }
  
  @Builder
  ModifierKeysPanel() {
    Column() {
      Text('长按锁定，再次点击解锁')
        .fontSize(11)
        .fontColor('#666666')
        .margin({ bottom: 8 })
      
      Row() {
        ForEach(this.modifierKeys, (key: VirtualKey) => {
          this.ModifierKeyButton(key)
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ left: 8, right: 8 })
    }
    .padding({ top: 8, bottom: 8 })
  }
  
  @Builder
  ModifierKeyButton(key: VirtualKey) {
    Column() {
      // 如果有图标则显示图标，否则显示文字
      if (key.icon) {
        Image(key.icon)
          .width(28)
          .height(28)
          .fillColor('#FFFFFF')
      } else {
        Text(key.label)
          .fontSize(key.label.length > 2 ? 14 : 20)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Medium)
      }
      
      Text(this.getModifierLabel(key.keysym))
        .fontSize(9)
        .fontColor('#AAAAAA')
        .margin({ top: 2 })
    }
    .width(60)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.isModifierLocked(key.keysym) ? key.color ?? '#555555' : '#3A3A3A')
    .borderRadius(12)
    .border({
      width: this.isModifierLocked(key.keysym) ? 2 : 0,
      color: key.color ?? '#555555'
    })
    .shadow({
      radius: 4,
      color: this.isModifierLocked(key.keysym) ? key.color ?? '#000000' : '#000000',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.toggleModifier(key.keysym)
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.lockModifier(key.keysym)
        })
    )
  }
  
  @Builder
  FunctionKeysPanel() {
    Column() {
      // 第一行：Esc + F1-F6
      Row() {
        ForEach(this.functionKeys.slice(0, 7), (key: VirtualKey) => {
          this.FunctionKeyButton(key)
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ left: 4, right: 4 })
      
      // 第二行：F7-F12
      Row() {
        ForEach(this.functionKeys.slice(7), (key: VirtualKey) => {
          this.FunctionKeyButton(key)
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ left: 4, right: 4 })
      .margin({ top: 8 })
    }
    .padding({ top: 12, bottom: 8 })
  }
  
  @Builder
  FunctionKeyButton(key: VirtualKey) {
    Text(key.label)
      .fontSize(12)
      .fontColor('#FFFFFF')
      .fontWeight(FontWeight.Medium)
      .width(44)
      .height(36)
      .textAlign(TextAlign.Center)
      .backgroundColor(key.color ?? '#444444')
      .borderRadius(8)
      .shadow({ radius: 2, color: '#000000', offsetX: 0, offsetY: 1 })
      .onClick(() => {
        this.sendKeyWithModifiers(key.keysym)
      })
  }
  
  @Builder
  NavKeysPanel() {
    Column() {
      // 第一行
      Row() {
        ForEach(this.navKeys.slice(0, 4), (key: VirtualKey) => {
          this.NavKeyButton(key)
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      
      // 第二行
      Row() {
        ForEach(this.navKeys.slice(4, 8), (key: VirtualKey) => {
          this.NavKeyButton(key)
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 8 })
      
      // 第三行：方向键
      Row() {
        Blank().width(50)
        this.NavKeyButton(this.navKeys[8])  // ↑
        Blank().width(50)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 12 })
      
      Row() {
        this.NavKeyButton(this.navKeys[10])  // ←
        this.NavKeyButton(this.navKeys[9])   // ↓
        this.NavKeyButton(this.navKeys[11])  // →
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 4 })
      
      // Enter 键
      Row() {
        this.NavKeyButton(this.navKeys[12])  // Enter
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 12 })
    }
    .padding({ top: 12, bottom: 8 })
  }
  
  @Builder
  NavKeyButton(key: VirtualKey) {
    Text(key.label)
      .fontSize(key.label.length > 2 ? 11 : 16)
      .fontColor('#FFFFFF')
      .fontWeight(FontWeight.Medium)
      .width(key.width ? 44 * key.width : 44)
      .height(40)
      .textAlign(TextAlign.Center)
      .backgroundColor(key.color ?? '#3A3A3A')
      .borderRadius(8)
      .shadow({ radius: 2, color: '#000000', offsetX: 0, offsetY: 1 })
      .margin({ left: 4, right: 4 })
      .onClick(() => {
        this.sendKeyWithModifiers(key.keysym)
      })
  }
  
  @Builder
  ComboKeysPanel() {
    Column() {
      // 分成多行显示
      Grid() {
        ForEach(this.comboKeys, (combo: ComboKey) => {
          GridItem() {
            Column() {
              Text(combo.label)
                .fontSize(12)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium)
              
              Text(combo.description ?? '')
                .fontSize(9)
                .fontColor('#888888')
                .margin({ top: 2 })
            }
            .width('100%')
            .height(50)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#3A3A3A')
            .borderRadius(8)
            .onClick(() => {
              this.sendCombo(combo)
            })
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .padding({ left: 12, right: 12 })
      .height(180)
    }
    .padding({ top: 12, bottom: 8 })
  }
  
  // 获取修饰键标签
  private getModifierLabel(keysym: number): string {
    switch (keysym) {
      case KeySym.Control_L: return '控制'
      case KeySym.Alt_L: return '替代'
      case KeySym.Shift_L: return '上档'
      case KeySym.Super_L: return '鸿蒙/Win'
      case KeySym.Super_R: return '小艺/Copilot'
      default: return ''
    }
  }
  
  // 检查修饰键是否锁定
  private isModifierLocked(keysym: number): boolean {
    switch (keysym) {
      case KeySym.Control_L: return this.ctrlLocked
      case KeySym.Alt_L: return this.altLocked
      case KeySym.Shift_L: return this.shiftLocked
      case KeySym.Super_L:
      case KeySym.Super_R: return this.winLocked
      default: return false
    }
  }
  
  // 切换修饰键状态
  private toggleModifier(keysym: number) {
    const isLocked = this.isModifierLocked(keysym)
    if (isLocked) {
      // 解锁
      this.unlockModifier(keysym)
    } else {
      // 发送单次按键
      this.callbacks?.onKeyDown?.(keysym)
      setTimeout(() => {
        this.callbacks?.onKeyUp?.(keysym)
      }, 50)
    }
  }
  
  // 锁定修饰键
  private lockModifier(keysym: number) {
    switch (keysym) {
      case KeySym.Control_L:
        this.ctrlLocked = true
        break
      case KeySym.Alt_L:
        this.altLocked = true
        break
      case KeySym.Shift_L:
        this.shiftLocked = true
        break
      case KeySym.Super_L:
      case KeySym.Super_R:
        this.winLocked = true
        break
    }
    this.callbacks?.onKeyDown?.(keysym)
  }
  
  // 解锁修饰键
  private unlockModifier(keysym: number) {
    switch (keysym) {
      case KeySym.Control_L:
        this.ctrlLocked = false
        break
      case KeySym.Alt_L:
        this.altLocked = false
        break
      case KeySym.Shift_L:
        this.shiftLocked = false
        break
      case KeySym.Super_L:
      case KeySym.Super_R:
        this.winLocked = false
        break
    }
    this.callbacks?.onKeyUp?.(keysym)
  }
  
  // 发送按键（带修饰键）
  private sendKeyWithModifiers(keysym: number) {
    // 收集当前锁定的修饰键
    const modifiers: number[] = []
    if (this.ctrlLocked) modifiers.push(KeySym.Control_L)
    if (this.altLocked) modifiers.push(KeySym.Alt_L)
    if (this.shiftLocked) modifiers.push(KeySym.Shift_L)
    if (this.winLocked) modifiers.push(KeySym.Super_L)
    
    if (modifiers.length > 0) {
      // 发送组合键
      this.callbacks?.onCombo?.(modifiers, keysym)
      
      // 自动解锁非粘滞修饰键
      this.ctrlLocked = false
      this.altLocked = false
      this.shiftLocked = false
      this.winLocked = false
      
      // 发送修饰键释放
      modifiers.forEach(mod => {
        this.callbacks?.onKeyUp?.(mod)
      })
    } else {
      // 发送单个按键
      this.callbacks?.onKeyDown?.(keysym)
      setTimeout(() => {
        this.callbacks?.onKeyUp?.(keysym)
      }, 50)
    }
  }
  
  // 发送组合键
  private sendCombo(combo: ComboKey) {
    this.callbacks?.onCombo?.(combo.modifiers, combo.key)
  }
  
  // 公共方法：重置所有修饰键状态
  resetModifiers() {
    if (this.ctrlLocked) {
      this.ctrlLocked = false
      this.callbacks?.onKeyUp?.(KeySym.Control_L)
    }
    if (this.altLocked) {
      this.altLocked = false
      this.callbacks?.onKeyUp?.(KeySym.Alt_L)
    }
    if (this.shiftLocked) {
      this.shiftLocked = false
      this.callbacks?.onKeyUp?.(KeySym.Shift_L)
    }
    if (this.winLocked) {
      this.winLocked = false
      this.callbacks?.onKeyUp?.(KeySym.Super_L)
    }
  }
}

// 导出 KeySym 供外部使用
export { KeySym }

