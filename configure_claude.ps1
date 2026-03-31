# Claude Code API Key 配置脚本 (Windows PowerShell 版本)
# 支持：直接运行 .\configure_claude.ps1

# 需要管理员权限检查（某些系统可能需要）
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "注意：某些操作可能需要管理员权限"
}

# 颜色函数
function Write-Info($message) { Write-Host $message -ForegroundColor Blue }
function Write-Success($message) { Write-Host $message -ForegroundColor Green }
function Write-Warn($message) { Write-Host $message -ForegroundColor Yellow }
function Write-Error($message) { Write-Host $message -ForegroundColor Red }

# 前置条件检查
function Check-Prerequisites {
    $all_ok = $true

    Write-Host "🔍 检查前置条件..." -ForegroundColor Cyan
    Write-Host ""

    # 1. 检查 jq（PowerShell 可能需要单独安装）
    if (Get-Command jq -ErrorAction SilentlyContinue) {
        $jqVersion = jq --version 2>&1 | Select-Object -First 1
        Write-Host "  ✅ jq: $jqVersion" -ForegroundColor Green
    } else {
        Write-Host "  ❌ jq: 未安装" -ForegroundColor Red
        Write-Host ""
        Write-Host "  安装方法：" -ForegroundColor Yellow
        Write-Host "    1. 从 https://stedolan.github.io/jq/download/ 下载"
        Write-Host "    2. 或使用 chocolatey: choco install jq"
        Write-Host "    3. 或使用 winget: winget install jq"
        $global:all_ok = $false
    }

    # 2. 检查 PowerShell 版本
    $psVersion = $PSVersionTable.PSVersion.ToString()
    Write-Host "  ✅ PowerShell: $psVersion"

    # 3. 检查 Claude Code 配置文件
    $config_found = $false
    $config_paths = @(
        "$env:APPDATA\Claude\settings.json",
        "$env:APPDATA\Claude\settings.local.json",
        "$env:LOCALAPPDATA\Claude\settings.json"
    )

    foreach ($cfg in $config_paths) {
        if (Test-Path $cfg) {
            Write-Host "  ✅ Claude 配置: $cfg" -ForegroundColor Green
            $config_found = $true
            break
        }
    }

    if (-not $config_found) {
        Write-Host "  ⚠️  Claude 配置: 未找到" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  提示：" -ForegroundColor Blue
        Write-Host "    - 如果 Claude Code 未运行过，这是正常的"
        Write-Host "    - 脚本将在配置时创建配置文件"
    }

    Write-Host ""

    if (-not $all_ok) {
        Write-Host "❌ 前置条件检查失败，请解决上述问题后重试" -ForegroundColor Red
        exit 1
    }

    Write-Host "✅ 所有必需条件检查通过！" -ForegroundColor Green
    Write-Host ""
}

# 查找配置文件
function Find-ConfigFile {
    param([string]$CustomConfig)

    # 如果用户指定了配置，优先使用
    if ($CustomConfig -and (Test-Path $CustomConfig)) {
        return $CustomConfig
    }

    # 检查常见位置
    $candidates = @(
        "$env:APPDATA\Claude\settings.json",
        "$env:APPDATA\Claude\settings.local.json",
        "$env:LOCALAPPDATA\Claude\settings.json"
    )

    foreach ($cfg in $candidates) {
        if (Test-Path $cfg) {
            return $cfg
        }
    }

    # 默认使用 settings.json
    return "$env:APPDATA\Claude\settings.json"
}

# 创建基础配置
function New-BaseConfig {
    param([string]$ConfigFile)

    # 确保目录存在
    $config_dir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $config_dir)) {
        New-Item -ItemType Directory -Path $config_dir -Force | Out-Null
        Write-Host "📁 创建配置目录: $config_dir"
    }

    # 创建基础配置
    @'
{
  "env": {},
  "model": "step-1",
  "statusLine": {
    "type": "command",
    "command": "echo Claude Code"
  },
  "enabledPlugins": {},
  "extraKnownMarketplaces": {}
}
'@ | Out-File -FilePath $ConfigFile -Encoding UTF8

    Write-Host "✅ 已创建基础配置文件: $ConfigFile"
    Write-Host ""
}

# ========== 主程序开始 ==========

# 1. 检查前置条件
Check-Prerequisites

# 2. 确定配置文件（支持 -c 参数）
$CONFIG_FILE = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-c" -and $i + 1 -lt $args.Count) {
        $CONFIG_FILE = $args[$i + 1]
        break
    }
}
$CONFIG_FILE = Find-ConfigFile -CustomConfig $CONFIG_FILE

if (-not (Test-Path $CONFIG_FILE)) {
    Write-Host "⚠️  配置文件不存在，将自动创建" -ForegroundColor Yellow
    New-BaseConfig -ConfigFile $CONFIG_FILE
}

Write-Host "📁 使用配置文件: $CONFIG_FILE"
Write-Host ""

# 验证配置文件
try {
    $null = Get-Content $CONFIG_FILE | ConvertFrom-Json
} catch {
    Write-Host "❌ 配置文件不是有效的 JSON: $CONFIG_FILE" -ForegroundColor Red
    exit 1
}

# 3. 菜单
Write-Host "=========================================="
Write-Host "  Claude Code 配置 - 设置 StepFun"
Write-Host "=========================================="
Write-Host ""
Write-Host "请选择 StepFun 接入方式："
Write-Host "  1) StepFun 官方 API（按量计费）"
Write-Host "  2) StepFun Step Plan（订阅制）"
Write-Host ""

# 4. 读取选择
do {
    $choice = Read-Host "请输入数字 [1-2]"
    if ($choice -notmatch '^[1-2]$') {
        Write-Host "无效输入，请输入 1 或 2"
    }
} while ($choice -notmatch '^[1-2]$')

Write-Host ""

# 5. 根据选择获取配置信息
switch ($choice) {
    '1' {
        $PROVIDER = "stepfun-official"
        $PROMPT = "请输入 StepFun API Key: "
        $DEFAULT_MODEL = "step-3.5-flash"
        $BASE_URL = "https://api.stepfun.com"
    }
    '2' {
        $PROVIDER = "stepfun-plan"
        $PROMPT = "请输入 StepFun API Key: "
        $DEFAULT_MODEL = "step-3.5-flash"
        $BASE_URL = "https://api.stepfun.com/step_plan"
    }
}

# 6. 读取 API Key
do {
    $API_KEY = Read-Host -Prompt $PROMPT
    if ([string]::IsNullOrWhiteSpace($API_KEY)) {
        Write-Host "API Key 不能为空，请重新输入"
    }
} while ([string]::IsNullOrWhiteSpace($API_KEY))

# 7. 读取模型名称
$MODEL_NAME = Read-Host "模型名称 [默认: $DEFAULT_MODEL]"
if ([string]::IsNullOrWhiteSpace($MODEL_NAME)) {
    $MODEL_NAME = $DEFAULT_MODEL
}

# 8. 备份配置
Write-Host ""
Write-Host "📦 正在备份配置文件..."
$backup_file = "$CONFIG_FILE.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item $CONFIG_FILE $backup_file -Force
Write-Host "   备份文件: $backup_file"
Write-Host ""

# 9. 应用配置
Write-Host "⚙️  正在配置 Claude Code..."

# 读取并修改配置
$config = Get-Content $CONFIG_FILE | ConvertFrom-Json

# 设置环境变量
if (-not $config.env) { $config.env = @{} }
$config.env.ANTHROPIC_AUTH_TOKEN = $API_KEY
$config.env.ANTHROPIC_BASE_URL = $BASE_URL

# 设置模型
$config.model = $MODEL_NAME

# 保存配置
$config | ConvertTo-Json -Depth 10 | Out-File -FilePath $CONFIG_FILE -Encoding UTF8

Write-Host "  ✅ Claude Code 配置已更新" -ForegroundColor Green
Write-Host ""
Write-Host "=========================================="
Write-Host "✨ 配置完成！" -ForegroundColor Green
Write-Host "=========================================="
Write-Host ""
Write-Host "📝 配置文件: $CONFIG_FILE"
Write-Host "📦 备份文件: $backup_file"
Write-Host ""
Write-Host "⚙️  当前配置："
$providerName = if ($choice -eq '1') { 'StepFun 官方 API' } else { 'StepFun Step Plan' }
Write-Host "   提供商: $providerName"
Write-Host "   API Key: $($API_KEY.Substring(0, [Math]::Min(10, $API_KEY.Length)))..."
Write-Host "   端点: $BASE_URL"
Write-Host "   模型: $MODEL_NAME"
Write-Host ""
Write-Host "⚠️  重要：请重启 Claude Code 使配置生效"
Write-Host ""
Write-Host "获取 API Key："
Write-Host "  StepFun: https://platform.stepfun.com/console/apikeys"
Write-Host ""

Write-Host "按 Enter 键退出..."
[void][Console]::ReadKey($true)
