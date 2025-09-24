# 项目整理说明

## 整理目标

让代码库更加整洁有序，避免混乱的文件结构。

## 整理规则

### 1. 文件分类规则

#### Markdown文档 → `docs/` 文件夹
- 所有 `.md` 文件必须放在 `docs/` 文件夹中
- 包括：README、说明文档、修复记录等
- **规则**：以后创建任何markdown文件都要放在 `docs/` 文件夹

#### 脚本文件 → `scripts/` 文件夹  
- 所有 `.sh` 脚本文件必须放在 `scripts/` 文件夹中
- 包括：构建脚本、测试脚本、调试脚本等
- **规则**：以后创建任何脚本文件都要放在 `scripts/` 文件夹

#### 测试文件 → `scripts/` 文件夹
- 所有以 `test` 开头的文件必须放在 `scripts/` 文件夹中
- 包括：测试脚本、测试配置、测试数据等
- **规则**：以后创建任何测试文件都要放在 `scripts/` 文件夹

### 2. 忽略规则

#### 排除所有以点开头的文件和文件夹（除了 `.github`）
```gitignore
# 排除所有以点开头的文件和文件夹（除了.github）
.*
!.github/
!.github/**
```

#### 排除所有test开头的文件
```gitignore
# 排除所有test开头的文件
test*
**/test*
```

#### 排除 .cursor 文件夹
```gitignore
.cursor/
.cursor/**
```

#### 排除系统文件
```gitignore
.DS_Store
.trae/
.claude/
```

## 整理后的目录结构

```
qemu-hmos/
├── docs/                    # 所有文档
│   ├── AGENTS.md
│   ├── BUILD_FIX_SUMMARY.md
│   ├── CLOUD_BUILD_README.md
│   ├── FINAL_BUILD_FIX.md
│   ├── GITHUB_ACTIONS_GUIDE.md
│   ├── GITIGNORE_FIX.md
│   ├── NAPI_FIX_SUMMARY.md
│   ├── PERMISSION_FIX.md
│   ├── PROJECT_ORGANIZATION.md
│   └── WARP.md
├── scripts/                 # 所有脚本和测试文件
│   ├── check_qemu_status.sh
│   ├── comprehensive_debug.sh
│   ├── debug_current_status.sh
│   ├── detailed_qemu_diag.sh
│   ├── detailed_vnc_debug.sh
│   ├── diagnose_vnc_issue.sh
│   ├── simple_check.sh
│   ├── test_e2e
│   ├── test_e2e_qemu_integration.cpp
│   ├── test_napi_direct.js
│   ├── test_napi_fix.sh
│   ├── test_napi_functions
│   ├── test_napi_functions.cpp
│   ├── test_napi_integration.js
│   ├── test_vm_config.json
│   └── test_vnc_logs.sh
├── .github/                 # GitHub Actions配置
├── entry/                   # 主应用代码
├── third_party/            # 第三方依赖
├── .gitignore              # Git忽略规则
└── 其他配置文件...
```

## 已完成的整理工作

### 1. 文件移动
- ✅ 移动所有 `.md` 文件到 `docs/` 文件夹
- ✅ 移动所有 `.sh` 脚本到 `scripts/` 文件夹  
- ✅ 移动所有 `test*` 文件到 `scripts/` 文件夹

### 2. Git清理
- ✅ 从Git中移除已跟踪的 `.cursor/` 文件夹
- ✅ 从Git中移除已跟踪的 `test*` 文件
- ✅ 从Git中移除已跟踪的 `.vscode/` 文件夹
- ✅ 从Git中移除已跟踪的库文件

### 3. .gitignore 更新
- ✅ 添加排除所有以点开头的文件和文件夹（除了 `.github`）
- ✅ 添加排除所有 `test*` 文件
- ✅ 添加排除 `.cursor/` 文件夹
- ✅ 完善库文件排除规则

## 使用指南

### 创建新文档
```bash
# 创建新的markdown文档
touch docs/NEW_DOCUMENT.md
```

### 创建新脚本
```bash
# 创建新的脚本文件
touch scripts/new_script.sh
chmod +x scripts/new_script.sh
```

### 创建新测试
```bash
# 创建新的测试文件
touch scripts/test_new_feature.sh
chmod +x scripts/test_new_feature.sh
```

### 检查文件状态
```bash
# 检查Git状态
git status

# 检查被忽略的文件
git status --ignored

# 检查特定类型的文件
find . -name "*.md" | grep -v "./docs/"
find . -name "*.sh" | grep -v "./scripts/"
find . -name "test*" | grep -v "./scripts/"
```

## 注意事项

1. **严格遵守规则**：以后创建任何文件都要按照分类规则放置
2. **定期检查**：定期运行检查命令确保文件结构整洁
3. **提交前检查**：提交代码前检查是否有文件放错位置
4. **团队协作**：团队成员都要遵守这些整理规则

## 维护命令

### 检查文件分类
```bash
# 检查是否有markdown文件在错误位置
find . -maxdepth 1 -name "*.md" -type f

# 检查是否有脚本文件在错误位置  
find . -maxdepth 1 -name "*.sh" -type f

# 检查是否有test文件在错误位置
find . -maxdepth 1 -name "test*" -type f
```

### 自动整理脚本
```bash
# 移动根目录的markdown文件到docs
find . -maxdepth 1 -name "*.md" -type f -exec mv {} docs/ \;

# 移动根目录的脚本文件到scripts
find . -maxdepth 1 -name "*.sh" -type f -exec mv {} scripts/ \;

# 移动根目录的test文件到scripts
find . -maxdepth 1 -name "test*" -type f -exec mv {} scripts/ \;
```

---

**记住**：保持代码库整洁是每个开发者的责任！ 🧹✨
