# Claude Key Setup

快速配置 Claude Code 的 StepFun API Key 和端点设置。

## 特性

- ✅ 支持 2 种 StepFun 接入方式（官方 API、Step Plan）
- ✅ 自动检测 Claude Code 配置位置
- ✅ 自动创建基础配置文件（如果不存在）
- ✅ 前置条件检查（jq、bash/PowerShell、配置）
- ✅ 交互式菜单，简单易用
- ✅ 自动备份原配置
- ✅ 跨平台支持（macOS、Linux、Windows）

## 快速开始

### macOS / Linux（Bash）
```bash
curl -fsSL https://raw.githubusercontent.com/Zgh332358/claude-key-setup/main/configure_claude.sh -o configure_claude.sh
chmod +x configure_claude.sh
bash configure_claude.sh
```

### Windows（PowerShell 管理员模式）

> ⚠️ 必须在**管理员模式**的 PowerShell 下运行，否则脚本会提示并退出。

1. 右键点击 Windows 开始菜单，选择「终端管理员」或「Windows PowerShell (管理员)」
2. 执行以下命令：
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
irm https://raw.githubusercontent.com/Zgh332358/claude-key-setup/main/configure_claude.ps1 -OutFile configure_claude.ps1
.\configure_claude.ps1
```

### 指定配置文件路径
```bash
# macOS/Linux
bash configure_claude.sh -c /path/to/settings.json

# Windows PowerShell
.\configure_claude.ps1 -c C:\path\to\settings.json
```

## 支持模式

| 选项 | 模式 | Base URL | 说明 | API Key 获取 |
|------|------|----------|------|-------------|
| 1 | StepFun 官方 API | `https://api.stepfun.com` | 按量计费 | https://platform.stepfun.com/interface-key |
| 2 | StepFun Step Plan | `https://api.stepfun.com/step_plan` | 订阅制 | https://platform.stepfun.com/interface-key |

## 前置条件

### 必需
- **bash** (macOS/Linux) 或 **PowerShell** (Windows)

- **Claude Code** - 已安装 CLI 工具

### 可选
- **配置文件** - 如果不存在，脚本会自动创建

## 配置文件位置

| 系统 | 配置文件路径 |
|------|-------------|
| macOS/Linux | `~/.claude/settings.json` |
| Windows | `%USERPROFILE%\.claude\settings.json` |

如果配置文件不存在，脚本会自动创建。

## 配置流程

1. ✅ 检查前置条件（bash/PowerShell、环境）
2. ✅ 查找/创建配置文件
3. ✅ 显示菜单（StepFun 两个选项）
4. ✅ 输入 API Key
5. ✅ 输入模型名称（默认 `step-3.5-flash`，可回车跳过）
6. ✅ 备份原配置
7. ✅ 写入新配置
8. ✅ 提示重启 Claude Code

## 使用示例

```bash
# macOS/Linux
bash configure_claude.sh

# 选择 1 (StepFun 官方 API)
# 输入 API Key: sk-xxx
# 模型名称: step-3.5-flash (或回车使用默认)
```

```powershell
# Windows PowerShell
.\configure_claude.ps1

# 选择 1 (StepFun 官方 API)
# 输入 API Key: sk-xxx
# 模型名称: step-3.5-flash (或回车使用默认)
```

## 脚本说明

仓库包含两个脚本：
- `configure_claude.sh` - Bash 版本（macOS、Linux、WSL）
- `configure_claude.ps1` - PowerShell 版本（Windows）

两个脚本功能完全相同，只是针对不同平台做了适配。

## 配置结构

脚本会全量覆盖 `settings.json`，写入以下字段：
- `env.ANTHROPIC_AUTH_TOKEN` - API Key
- `env.ANTHROPIC_BASE_URL` - API 端点
- `env.ANTHROPIC_MODEL` - 默认模型
- `env.ANTHROPIC_SMALL_FAST_MODEL` - 快速模型
- `env.ANTHROPIC_DEFAULT_SONNET_MODEL` - Sonnet 模型
- `env.ANTHROPIC_DEFAULT_OPUS_MODEL` - Opus 模型
- `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` - Haiku 模型

> ⚠️ 脚本会备份原配置后全量覆盖，确保不会残留旧的模型配置。

## License

MIT License
