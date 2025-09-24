# HarmonyOS权限配置修复说明

## 问题描述

构建时出现错误：
```
ERROR: 00303221 Configuration Error
Error Message: The ohos.permission.WRITE_USER_STORAGE permission under requestPermissions must be a value that is predefined within the SDK or a custom one that you have included under definePermissions.
```

## 根本原因

在HarmonyOS NEXT (API 12)中，以下权限已被废弃：
- `ohos.permission.WRITE_USER_STORAGE`
- `ohos.permission.READ_USER_STORAGE`

这些权限在当前版本的SDK中不再支持，导致构建失败。

## 修复方案

### 1. 移除废弃的权限

从 `entry/src/main/module.json5` 中移除了以下权限：
```json5
{
  "name": "ohos.permission.WRITE_USER_STORAGE"
},
{
  "name": "ohos.permission.READ_USER_STORAGE"
}
```

### 2. 保留有效的权限

当前保留的权限配置：
```json5
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET"
  },
  {
    "name": "ohos.permission.READ_MEDIA",
    "reason": "$string:permission_read_media_reason",
    "usedScene": {
      "when": "always",
      "abilities": ["EntryAbility"]
    }
  },
  {
    "name": "ohos.permission.WRITE_MEDIA",
    "reason": "$string:permission_write_media_reason",
    "usedScene": {
      "when": "always",
      "abilities": ["EntryAbility"]
    }
  },
  {
    "name": "ohos.permission.GET_NETWORK_INFO"
  }
]
```

### 3. 清理字符串资源

从 `entry/src/main/resources/base/element/string.json` 中移除了不再需要的字符串：
- `permission_write_user_storage_reason`
- `permission_read_user_storage_reason`

## 替代方案

对于需要访问用户存储的功能，可以使用以下替代方案：

### 1. 应用沙箱存储
使用应用自身的沙箱目录，无需特殊权限：
```typescript
// 获取应用沙箱目录
const context = getContext(this) as common.UIAbilityContext;
const filesDir = context.filesDir; // /data/storage/el2/base/haps/entry/files/
```

### 2. 媒体存储权限
如果需要访问媒体文件，使用：
- `ohos.permission.READ_MEDIA` - 读取媒体文件
- `ohos.permission.WRITE_MEDIA` - 写入媒体文件

### 3. 动态权限申请
对于敏感操作，在运行时动态申请权限：
```typescript
import { Permissions } from '@ohos.permission';

async function requestPermission() {
  try {
    const result = await Permissions.requestPermission('ohos.permission.READ_MEDIA');
    if (result === Permissions.Granted) {
      // 权限已授予
    }
  } catch (error) {
    console.error('权限申请失败:', error);
  }
}
```

## 当前权限用途

- **INTERNET**: 网络访问，用于下载ISO镜像和RDP连接
- **READ_MEDIA**: 读取媒体文件，用于访问VM磁盘和固件文件
- **WRITE_MEDIA**: 写入媒体文件，用于创建和修改VM磁盘文件
- **GET_NETWORK_INFO**: 获取网络信息，用于网络配置

## 验证步骤

1. **构建测试**：
   ```bash
   hvigor assembleDebug
   ```

2. **检查权限**：
   构建成功后，应用将只请求支持的权限

3. **功能验证**：
   确认VM文件操作在应用沙箱内正常工作

## 注意事项

1. **文件存储位置**：VM相关文件将存储在应用沙箱目录中
2. **权限申请**：某些操作可能需要用户手动授权
3. **兼容性**：确保在目标HarmonyOS版本上测试

## 修复完成

- ✅ 移除废弃的权限配置
- ✅ 清理相关字符串资源
- ✅ 修复JSON语法错误
- ✅ 保持核心功能权限

现在可以重新构建项目，应该不会再出现权限配置错误。

---

**修复时间**: 2025-09-25  
**影响范围**: 权限配置和字符串资源  
**测试状态**: 待构建验证

