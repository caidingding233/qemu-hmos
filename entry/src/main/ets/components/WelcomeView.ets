/**
 * 欢迎页组件 - 开箱即用体验
 * 在没有创建任何 VM 时显示
 * 使用 HarmonyOS Symbol 图标
 */

interface WelcomeCallbacks {
  onCreateWindows: () => void
  onCreateLinux: () => void
  onImportVM: () => void
}

@Component
export struct WelcomeView {
  callbacks: WelcomeCallbacks = {
    onCreateWindows: (): void => {},
    onCreateLinux: (): void => {},
    onImportVM: (): void => {}
  }

  @State selectedOS: string = ''

  build() {
    Column() {
      // 顶部留白
      Blank()
        .height(40)

      // 主标题区域
      Column() {
        // 顶部图标
        Stack() {
          Circle()
            .width(80)
            .height(80)
            .fill('#EBF5FF')
          
          SymbolGlyph($r('sys.symbol.rectangle_on_rectangle'))
            .fontSize(40)
            .fontColor(['#3B82F6'])
        }
        .margin({ bottom: 24 })

        Text('欢迎使用')
          .fontSize(16)
          .fontColor('#6B7280')
          .fontWeight(FontWeight.Medium)
        
        Text('QEMU 虚拟机')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .margin({ top: 8 })
        
        Text('在鸿蒙设备上运行 Windows 和 Linux')
          .fontSize(15)
          .fontColor('#9CA3AF')
          .margin({ top: 12 })
      }
      .alignItems(HorizontalAlign.Center)

      // 设备插图区域 - 简化版
      Row() {
        // 平板图标
        Column() {
          Stack() {
            Column()
              .width(80)
              .height(56)
              .backgroundColor('#F3F4F6')
              .borderRadius(8)
              .border({ width: 2, color: '#E5E7EB' })
            
            SymbolGlyph($r('sys.symbol.display'))
              .fontSize(32)
              .fontColor(['#6B7280'])
          }
          
          Text('平板/电脑')
            .fontSize(12)
            .fontColor('#6B7280')
            .margin({ top: 8 })
        }
        .margin({ right: 20 })

        // 加号
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor(['#D1D5DB'])
          .margin({ right: 20 })

        // 操作系统图标
        Column() {
          Row() {
            // Windows 图标
            Stack() {
              Circle()
                .width(40)
                .height(40)
                .fill('#EBF5FF')
              SymbolGlyph($r('sys.symbol.display'))
                .fontSize(20)
                .fontColor(['#0078D4'])
            }
            .margin({ right: 8 })
            
            // Linux 图标
            Stack() {
              Circle()
                .width(40)
                .height(40)
                .fill('#FEF3C7')
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(20)
                .fontColor(['#D97706'])
            }
          }
          
          Text('操作系统')
            .fontSize(12)
            .fontColor('#6B7280')
            .margin({ top: 8 })
        }
      }
      .margin({ top: 40, bottom: 40 })
      .justifyContent(FlexAlign.Center)

      // 快速创建卡片
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.bolt_fill'))
            .fontSize(16)
            .fontColor(['#F59E0B'])
            .margin({ right: 8 })
          Text('快速创建')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#374151')
        }
        .margin({ bottom: 20 })

        Row() {
          // Windows 选项
          Column() {
            Stack() {
              Column()
                .width(80)
                .height(80)
                .backgroundColor(this.selectedOS === 'windows' ? '#DBEAFE' : '#F9FAFB')
                .borderRadius(20)
                .border({
                  width: 2,
                  color: this.selectedOS === 'windows' ? '#3B82F6' : '#E5E7EB'
                })
              
              SymbolGlyph($r('sys.symbol.display'))
                .fontSize(32)
                .fontColor(['#0078D4'])
            }
            
            Text('Windows')
              .fontSize(13)
              .fontColor('#374151')
              .fontWeight(FontWeight.Medium)
              .margin({ top: 10 })
            
            Text('ARM64')
              .fontSize(11)
              .fontColor('#9CA3AF')
              .margin({ top: 2 })
          }
          .onClick(() => {
            this.selectedOS = 'windows'
            this.callbacks.onCreateWindows()
          })
          .margin({ right: 24 })

          // Linux 选项
          Column() {
            Stack() {
              Column()
                .width(80)
                .height(80)
                .backgroundColor(this.selectedOS === 'linux' ? '#FEF3C7' : '#F9FAFB')
                .borderRadius(20)
                .border({
                  width: 2,
                  color: this.selectedOS === 'linux' ? '#F59E0B' : '#E5E7EB'
                })
              
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(32)
                .fontColor(['#D97706'])
            }
            
            Text('Linux')
              .fontSize(13)
              .fontColor('#374151')
              .fontWeight(FontWeight.Medium)
              .margin({ top: 10 })
            
            Text('ARM64')
              .fontSize(11)
              .fontColor('#9CA3AF')
              .margin({ top: 2 })
          }
          .onClick(() => {
            this.selectedOS = 'linux'
            this.callbacks.onCreateLinux()
          })
        }
        .justifyContent(FlexAlign.Center)
      }
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(24)
      .shadow({
        radius: 20,
        color: '#0000000A',
        offsetX: 0,
        offsetY: 4
      })
      .margin({ left: 24, right: 24 })

      // 底部提示
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(16)
            .fontColor(['#D97706'])
            .margin({ right: 8 })
          Text('需要华为批准的 KVM 权限才能获得最佳性能')
            .fontSize(13)
            .fontColor('#6B7280')
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#FFFBEB')
        .borderRadius(12)
        .margin({ top: 24 })

        Row() {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(14)
            .fontColor(['#3B82F6'])
            .margin({ right: 4 })
          Text('了解如何申请 KVM 权限')
            .fontSize(13)
            .fontColor('#3B82F6')
            .fontWeight(FontWeight.Medium)
        }
        .margin({ top: 12 })
      }
      .margin({ left: 24, right: 24 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F9FAFB')
  }
}
