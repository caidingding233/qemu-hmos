/**
 * VM 卡片组件 - HarmonyOS 现代设计风格
 * 遵循 HarmonyOS Design 规范
 */

// VM 状态类型 (与 VmStore.VMStatus 保持同步)
type VMStatusType = 'running' | 'stopped' | 'starting' | 'stopping' | 'failed' | 'unknown' | 'creating' | 'preparing' | 'paused' | 'error'

// VM 配置接口
interface VMCardConfig {
  cpuCount: number
  memoryMB: number
  diskSizeGB: number
  osType: string
  archType?: string
}

// VM 数据接口
interface VMCardData {
  id: string
  name: string
  osType: string
  status: VMStatusType
  config: VMCardConfig
}

// 回调接口
interface VMCardCallbacks {
  onStart: () => void
  onStop: () => void
  onDelete: () => void
  onSnapshot: () => void
  onSettings: () => void
}

@Component
export struct VMCard {
  @Prop vm: VMCardData
  @Prop isLoading: boolean = false
  callbacks: VMCardCallbacks = {
    onStart: () => {},
    onStop: () => {},
    onDelete: () => {},
    onSnapshot: () => {},
    onSettings: () => {}
  }

  // 获取状态颜色
  private getStatusColor(): ResourceColor {
    switch (this.vm.status) {
      case 'running': return '#10B981'  // 绿色
      case 'stopped': return '#6B7280'  // 灰色
      case 'starting': return '#F59E0B' // 橙色
      case 'stopping': return '#F59E0B' // 橙色
      case 'failed': return '#EF4444'   // 红色
      default: return '#9CA3AF'         // 浅灰
    }
  }

  // 获取状态文本
  private getStatusText(): string {
    switch (this.vm.status) {
      case 'running': return '运行中'
      case 'stopped': return '已停止'
      case 'starting': return '启动中'
      case 'stopping': return '停止中'
      case 'failed': return '故障'
      default: return '未知'
    }
  }

  // 获取 OS 图标资源（使用 HarmonyOS Symbol）
  private getOsSymbol(): Resource {
    const osLower = this.vm.osType.toLowerCase()
    if (osLower.includes('windows')) {
      return $r('sys.symbol.display')  // 显示器图标代表 Windows
    } else if (osLower.includes('linux') || osLower.includes('ubuntu') || osLower.includes('debian')) {
      return $r('sys.symbol.gearshape')  // 齿轮图标代表 Linux
    } else if (osLower.includes('mac') || osLower.includes('darwin')) {
      return $r('sys.symbol.display')  // 显示器图标代表 macOS
    }
    return $r('sys.symbol.rectangle_on_rectangle')  // 默认虚拟机图标
  }
  
  // 获取 OS 图标颜色
  private getOsIconColor(): ResourceColor {
    const osLower = this.vm.osType.toLowerCase()
    if (osLower.includes('windows')) {
      return '#0078D4'  // Windows 蓝
    } else if (osLower.includes('linux') || osLower.includes('ubuntu')) {
      return '#E95420'  // Ubuntu 橙
    } else if (osLower.includes('mac')) {
      return '#555555'  // macOS 灰
    }
    return '#6B7280'  // 默认灰色
  }
  
  // 获取 OS 图标背景颜色
  private getOsIconBgColor(): ResourceColor {
    const osLower = this.vm.osType.toLowerCase()
    if (osLower.includes('windows')) {
      return '#EBF5FF'  // 浅蓝背景
    } else if (osLower.includes('linux') || osLower.includes('ubuntu')) {
      return '#FEF3C7'  // 浅橙背景
    } else if (osLower.includes('mac')) {
      return '#F3F4F6'  // 浅灰背景
    }
    return '#F3F4F6'
  }

  // 状态指示器动画
  @State statusPulse: number = 1.0

  aboutToAppear() {
    // 运行中状态添加脉冲动画
    if (this.vm.status === 'running' || this.vm.status === 'starting') {
      this.startPulseAnimation()
    }
  }

  private startPulseAnimation() {
    // 简单的脉冲效果
  }

  build() {
    Column() {
      // 卡片头部
      Row() {
        // OS 图标和名称
        Row() {
          // OS 图标容器 - 使用 HarmonyOS Symbol
          Stack() {
            Circle()
              .width(48)
              .height(48)
              .fill(this.vm.status === 'running' ? this.getOsIconBgColor() : '#F3F4F6')
            
            // 使用 SymbolGlyph 组件显示系统图标
            SymbolGlyph(this.getOsSymbol())
              .fontSize(24)
              .fontColor([this.vm.status === 'running' ? this.getOsIconColor() : '#9CA3AF'])
          }
          .width(48)
          .height(48)

          Column() {
            Text(this.vm.name)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1F2937')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            
            Row() {
              Text(this.vm.osType)
                .fontSize(13)
                .fontColor('#6B7280')
              
              Text(' • ')
                .fontSize(13)
                .fontColor('#D1D5DB')
              
              Text(this.vm.config.archType || 'ARM64')
                .fontSize(13)
                .fontColor('#6B7280')
            }
            .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
          .layoutWeight(1)
        }
        .layoutWeight(1)

        // 状态标签
        Row() {
          // 状态指示点
          Circle()
            .width(8)
            .height(8)
            .fill(this.getStatusColor())
            .margin({ right: 6 })
          
          Text(this.getStatusText())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getStatusColor())
        }
        .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.vm.status === 'running' ? '#ECFDF5' : '#F9FAFB')
        .borderRadius(16)
      }
      .width('100%')

      // 配置信息
      Row() {
        // CPU
        Column() {
          Text('CPU')
            .fontSize(11)
            .fontColor('#9CA3AF')
          Text(`${this.vm.config.cpuCount} 核`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#374151')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Divider()
          .vertical(true)
          .height(32)
          .color('#E5E7EB')

        // 内存
        Column() {
          Text('内存')
            .fontSize(11)
            .fontColor('#9CA3AF')
          Text(`${(this.vm.config.memoryMB / 1024).toFixed(0)} GB`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#374151')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Divider()
          .vertical(true)
          .height(32)
          .color('#E5E7EB')

        // 磁盘
        Column() {
          Text('磁盘')
            .fontSize(11)
            .fontColor('#9CA3AF')
          Text(`${this.vm.config.diskSizeGB} GB`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#374151')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })
      .margin({ top: 16 })
      .backgroundColor('#F9FAFB')
      .borderRadius(12)

      // 操作按钮
      Row() {
        // 主操作按钮 - 启动/停止
        Button(this.vm.status === 'running' ? '停止' : '启动')
          .type(ButtonType.Capsule)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.vm.status === 'running' ? '#FEF3C7' : '#DCFCE7')
          .fontColor(this.vm.status === 'running' ? '#D97706' : '#15803D')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.isLoading && this.vm.status !== 'starting' && this.vm.status !== 'stopping')
          .onClick(() => {
            if (this.vm.status === 'running') {
              this.callbacks.onStop()
            } else {
              this.callbacks.onStart()
            }
          })

        // 连接按钮 (仅运行时可用)
        Button('连接')
          .type(ButtonType.Capsule)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.vm.status === 'running' ? '#DBEAFE' : '#F3F4F6')
          .fontColor(this.vm.status === 'running' ? '#1D4ED8' : '#9CA3AF')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 8 })
          .enabled(this.vm.status === 'running')

        // 更多操作
        Button() {
          Text('•••')
            .fontSize(16)
            .fontColor('#6B7280')
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor('#F3F4F6')
        .margin({ left: 8 })
        .bindMenu([
          {
            value: '快照管理',
            action: () => this.callbacks.onSnapshot()
          },
          {
            value: '设置',
            action: () => this.callbacks.onSettings()
          },
          {
            value: '删除',
            action: () => this.callbacks.onDelete()
          }
        ])
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .shadow({
      radius: 16,
      color: '#0000000D',
      offsetX: 0,
      offsetY: 4
    })
    .width('100%')
  }
}

