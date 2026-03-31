# Claude Code API Key 配置脚本 (Windows PowerShell 版本)
# 支持：直接运行 .\configure_claude.ps1

param(
    [Alias("c")]
    [string]$ConfigPath
)

# 管理员权限检查
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host ""
    Write-Host "=========================================="  -ForegroundColor Red
    Write-Host "  请在管理员模式的 PowerShell 下运行此脚本" -ForegroundColor Red
    Write-Host "=========================================="  -ForegroundColor Red
    Write-Host ""
    Write-Host "操作步骤：" -ForegroundColor Yellow
    Write-Host "  1. 右键点击 Windows 开始菜单"
    Write-Host "  2. 选择「终端管理员」或「Windows PowerShell (管理员)」"
    Write-Host "  3. 重新执行以下命令："
    Write-Host ""
    Write-Host "     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass" -ForegroundColor Cyan
    Write-Host "     .\configure_claude.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "按任意键退出..."
    [void][Console]::ReadKey($true)
    exit 1
}

# 颜色函数
function Write-Info($message) { Write-Host $message -ForegroundColor Blue }
function Write-Success($message) { Write-Host $message -ForegroundColor Green }
function Write-Warn($message) { Write-Host $message -ForegroundColor Yellow }
function Write-ErrorMsg($message) { Write-Host $message -ForegroundColor Red }

# 前置条件检查
function Check-Prerequisites {
    $all_ok = $true

    Write-Host "检查前置条件..." -ForegroundColor Cyan
    Write-Host ""

    # 1. 检查 PowerShell 版本
    $psVersion = $PSVersionTable.PSVersion.ToString()
    Write-Host "  PowerShell: $psVersion" -ForegroundColor Green

    # 2. 检查 Claude Code 配置文件
    $config_found = $false
    $config_paths = @(
        "$HOME\.claude\settings.json",
        "$HOME\.claude\settings.local.json"
    )

    foreach ($cfg in $config_paths) {
        if (Test-Path $cfg) {
            Write-Host "  Claude 配置: $cfg" -ForegroundColor Green
            $config_found = $true
            break
        }
    }

    if (-not $config_found) {
        Write-Host "  Claude 配置: 未找到" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  提示：" -ForegroundColor Blue
        Write-Host "    - 如果 Claude Code 未运行过，这是正常的"
        Write-Host "    - 脚本将在配置时创建配置文件"
    }

    Write-Host ""

    if (-not $all_ok) {
        Write-Host "前置条件检查失败，请解决上述问题后重试" -ForegroundColor Red
        exit 1
    }

    Write-Host "所有必需条件检查通过！" -ForegroundColor Green
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
        "$HOME\.claude\settings.json",
        "$HOME\.claude\settings.local.json"
    )

    foreach ($cfg in $candidates) {
        if (Test-Path $cfg) {
            return $cfg
        }
    }

    # 默认使用 settings.json
    return "$HOME\.claude\settings.json"
}

# 创建基础配置
function New-BaseConfig {
    param([string]$ConfigFile)

    # 确保目录存在
    $config_dir = Split-Path $ConfigFile -Parent
    if (-not (Test-Path $config_dir)) {
        New-Item -ItemType Directory -Path $config_dir -Force | Out-Null
        Write-Host "创建配置目录: $config_dir"
    }

    # 创建基础配置
    $configObj = [ordered]@{
        env = @{}
        model = "step-3.5-flash"
        statusLine = [ordered]@{
            type = "command"
            command = "echo Claude Code"
        }
        enabledPlugins = @{}
        extraKnownMarketplaces = @{}
    }
    $configObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigFile -Encoding UTF8

    Write-Host "已创建基础配置文件: $ConfigFile" -ForegroundColor Green
    Write-Host ""
}

# ========== 主程序开始 ==========

# 1. 检查前置条件
Check-Prerequisites

# 2. 确定配置文件（支持 -c / -ConfigPath 参数）
$CONFIG_FILE = Find-ConfigFile -CustomConfig $ConfigPath

if (-not (Test-Path $CONFIG_FILE)) {
    Write-Host "配置文件不存在，将自动创建" -ForegroundColor Yellow
    New-BaseConfig -ConfigFile $CONFIG_FILE
}

Write-Host "使用配置文件: $CONFIG_FILE"
Write-Host ""

# 3. 菜单
Write-Host "=========================================="
Write-Host "  Claude Code 配置 - 设置 StepFun"
Write-Host "=========================================="
Write-Host ""
Write-Host "获取 API Key："
Write-Host "  StepFun: https://platform.stepfun.com/interface-key"
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
        $PROMPT = "请输入 StepFun API Key"
        $DEFAULT_MODEL = "step-3.5-flash"
        $BASE_URL = "https://api.stepfun.com"
    }
    '2' {
        $PROVIDER = "stepfun-plan"
        $PROMPT = "请输入 StepFun API Key"
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
Write-Host "正在备份配置文件..."
$backup_file = "$CONFIG_FILE.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item $CONFIG_FILE $backup_file -Force
Write-Host "   备份文件: $backup_file"
Write-Host ""

# 9. 应用配置（全量覆盖，避免残留旧模型配置）
Write-Host "正在配置 Claude Code..."

$newConfig = [ordered]@{
    env = [ordered]@{
        ANTHROPIC_BASE_URL = $BASE_URL
        ANTHROPIC_AUTH_TOKEN = $API_KEY
        ANTHROPIC_MODEL = $MODEL_NAME
        ANTHROPIC_SMALL_FAST_MODEL = $MODEL_NAME
        ANTHROPIC_DEFAULT_SONNET_MODEL = $MODEL_NAME
        ANTHROPIC_DEFAULT_OPUS_MODEL = $MODEL_NAME
        ANTHROPIC_DEFAULT_HAIKU_MODEL = $MODEL_NAME
    }
}
$newConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $CONFIG_FILE -Encoding UTF8

Write-Host "  Claude Code 配置已更新" -ForegroundColor Green
Write-Host ""
Write-Host "=========================================="
Write-Host "配置完成！" -ForegroundColor Green
Write-Host "=========================================="
Write-Host ""
Write-Host "配置文件: $CONFIG_FILE"
Write-Host "备份文件: $backup_file"
Write-Host ""
Write-Host "当前配置："
$providerName = if ($choice -eq '1') { 'StepFun 官方 API' } else { 'StepFun Step Plan' }
Write-Host "   提供商: $providerName"
Write-Host "   API Key: $($API_KEY.Substring(0, [Math]::Min(10, $API_KEY.Length)))..."
Write-Host "   端点: $BASE_URL"
Write-Host "   模型: $MODEL_NAME"
Write-Host ""
Write-Host "重要：请重启 Claude Code 使配置生效" -ForegroundColor Yellow
Write-Host ""

Write-Host "按任意键退出..."
[void][Console]::ReadKey($true)
