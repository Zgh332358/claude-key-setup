# Run in ordinary Windows PowerShell 5.1 and PowerShell 7 on an ACL-capable volume:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_configure_claude.ps1 -Language zh-CN
# pwsh -NoProfile -File .\tests\test_configure_claude.ps1 -Language en
# Uses only fake credentials and a unique private temporary directory.
param(
    [ValidateSet('zh-CN', 'en')]
    [string]$Language = 'zh-CN'
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'These tests require Windows ACL support.' }

$releaseDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) $Language
$scriptPath = Join-Path $releaseDirectory 'configure_claude.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "PowerShell parse errors: $($parseErrors.Count)" }
# Load only function definitions: never run prompts or touch the real Claude config.
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert-True $failed $Message
}
function Assert-Bytes([string]$Path, [byte[]]$Expected) {
    $actual = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    Assert-True ($actual -ceq [Convert]::ToBase64String($Expected)) 'File bytes changed unexpectedly.'
}

$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-key-setup-test-' + [Guid]::NewGuid().ToString('N'))
$directorySecurity = New-Object System.Security.AccessControl.DirectorySecurity
$directorySecurity.SetAccessRuleProtection($true, $false)
$userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
foreach ($sid in @($userSid, [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
    $directorySecurity.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
        $sid, [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow))
}
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [System.IO.Directory]::CreateDirectory($fixture, $directorySecurity) | Out-Null
} else {
    [System.IO.FileSystemAclExtensions]::Create([System.IO.DirectoryInfo]::new($fixture), $directorySecurity)
}
$encoding = [System.Text.UTF8Encoding]::new($false)
$fakeKey = 'test-only-key-"\$`-never-real'
$baseUrl = 'https://api.stepfun.com/step_plan'
$passed = 0
try {
    # Explicit missing paths stay explicit; a bare filename resolves in the current directory.
    Push-Location $fixture
    try {
        Assert-True ((Find-ConfigFile 'new config[1].json') -ceq 'new config[1].json') 'Explicit path was changed.'
        $backup = Update-ConfigFile 'new config[1].json' $baseUrl $fakeKey 'step-5-preview'
    } finally { Pop-Location }
    $created = Join-Path $fixture 'new config[1].json'
    Assert-True ($null -eq $backup) 'A new config unexpectedly had a backup.'
    $result = Get-Content -LiteralPath $created -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($result.env.ANTHROPIC_AUTH_TOKEN -ceq $fakeKey) 'Special characters in key were not preserved.'
    Assert-True ($result.env.ANTHROPIC_MODEL -ceq 'step-5-preview') 'Model was not preserved.'
    Assert-PrivateFileSecurity (Get-Acl -LiteralPath $created)
    $passed++

    # Backups retain exact original bytes, and only env is replaced.
    $existing = Join-Path $fixture 'existing.json'
    [byte[]]$original = @(0xEF, 0xBB, 0xBF) + $encoding.GetBytes('{"env":{"old":"old-test-key"},"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"echo test"}]}]},"theme":"dark","model":"kept-model","permissions":{"allow":["Read"]}}')
    Write-PrivateFile $existing $original
    $broadAcl = Get-Acl -LiteralPath $existing
    $broadAcl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
        [System.Security.Principal.SecurityIdentifier]::new('S-1-1-0'),
        [System.Security.AccessControl.FileSystemRights]::Read,
        [System.Security.AccessControl.AccessControlType]::Allow))
    Set-Acl -LiteralPath $existing -AclObject $broadAcl
    $parentAclBefore = (Get-Acl -LiteralPath $fixture).Sddl
    $backup = Update-ConfigFile $existing $baseUrl $fakeKey 'custom-model'
    Assert-Bytes $backup $original
    $result = Get-Content -LiteralPath $existing -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($result.theme -ceq 'dark' -and $result.model -ceq 'kept-model') 'Non-env settings changed.'
    Assert-True ($result.hooks.PreToolUse[0].hooks[0].command -ceq 'echo test') 'Hooks changed.'
    Assert-True ($result.permissions.allow[0] -ceq 'Read') 'Permissions changed.'
    Assert-True ($null -eq $result.env.old -and $result.env.ANTHROPIC_MODEL -ceq 'custom-model') 'Env replacement failed.'
    Assert-PrivateFileSecurity (Get-Acl -LiteralPath $backup)
    Assert-PrivateFileSecurity (Get-Acl -LiteralPath $existing)
    Assert-True ((Get-Acl -LiteralPath $fixture).Sddl -ceq $parentAclBefore) 'Parent directory ACL changed.'
    $passed++

    # Repeated runs cannot overwrite an earlier backup.
    $backupAgain = Update-ConfigFile $existing $baseUrl 'another-test-only-key' 'step-5-preview'
    Assert-True ($backup -cne $backupAgain) 'Backup names collided.'
    Assert-Bytes $backup $original
    $passed++

    # Exclusive creation cannot truncate or delete an existing file.
    $collision = Join-Path $fixture 'collision.json'
    $collisionBytes = $encoding.GetBytes('keep-this-fixture')
    Write-PrivateFile $collision $collisionBytes
    Assert-Throws { Write-PrivateFile $collision $encoding.GetBytes('replacement') } 'CreateNew unexpectedly overwrote a file.'
    Assert-Bytes $collision $collisionBytes
    $passed++

    # Invalid JSON and invalid root types leave the original and sidecars untouched.
    foreach ($invalid in @('{"env":', '[{"env":{}}]', 'null', '')) {
        $path = Join-Path $fixture ('invalid-' + [Guid]::NewGuid().ToString('N') + '.json')
        $bytes = $encoding.GetBytes($invalid)
        Write-PrivateFile $path $bytes
        Assert-Throws { Update-ConfigFile $path $baseUrl $fakeKey 'step-5-preview' } 'Invalid config was accepted.'
        Assert-Bytes $path $bytes
        Assert-True (@(Get-ChildItem -LiteralPath $fixture -Filter ((Split-Path $path -Leaf) + '.*')).Count -eq 0) 'Invalid config created sidecars.'
    }
    $passed++

    # A locked original forces replacement failure without truncation or leftover temp files.
    $locked = Join-Path $fixture 'locked.json'
    $lockedBytes = $encoding.GetBytes('{"theme":"keep-on-failure"}')
    Write-PrivateFile $locked $lockedBytes
    $lock = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        Assert-Throws { Update-ConfigFile $locked $baseUrl $fakeKey 'step-5-preview' } 'Locked replacement unexpectedly succeeded.'
        Assert-Bytes $locked $lockedBytes
    } finally { $lock.Dispose() }
    Assert-True (@(Get-ChildItem -LiteralPath $fixture -Filter 'locked.json.tmp.*').Count -eq 0) 'Failed update left a temp file.'
    $passed++

    # Simulate the documented ReplaceFile failure that can leave its target absent.
    $recoveryTarget = Join-Path $fixture 'recovery.json'
    $recoveryBytes = $encoding.GetBytes('{"theme":"recover-after-publish-failure"}')
    Write-PrivateFile $recoveryTarget $recoveryBytes
    $savedPublish = ${function:Publish-ConfigFile}
    $failureBackup = $null
    try {
        function Publish-ConfigFile {
            param([string]$TempFile, [string]$ConfigFile, [bool]$ReplaceExisting)
            Remove-Item -LiteralPath $ConfigFile -Force
            throw 'Injected publication failure after original disappears.'
        }
        try { Update-ConfigFile $recoveryTarget $baseUrl $fakeKey 'step-5-preview' } catch {
            $failureBackup = $_.Exception.Data['BackupFile']
        }
    } finally { Set-Item -Path Function:Publish-ConfigFile -Value $savedPublish }
    Assert-True (-not [string]::IsNullOrWhiteSpace($failureBackup)) 'Failure did not expose the retained backup path.'
    Assert-Bytes $recoveryTarget $recoveryBytes
    Assert-Bytes $failureBackup $recoveryBytes
    Assert-PrivateFileSecurity (Get-Acl -LiteralPath $recoveryTarget)
    Assert-True (@(Get-ChildItem -LiteralPath $fixture -Filter 'recovery.json.tmp.*').Count -eq 0) 'Recovery left a temp file.'
    Assert-True (@(Get-ChildItem -LiteralPath $fixture -Filter 'recovery.json.restore.*').Count -eq 0) 'Recovery left a restore file.'
    $passed++

    # Directories are rejected before any backup/temp file is written.
    $directory = Join-Path $fixture 'directory.json'
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    Assert-Throws { Update-ConfigFile $directory $baseUrl $fakeKey 'step-5-preview' } 'Directory was accepted as a config.'
    Assert-True (@(Get-ChildItem -LiteralPath $fixture -Filter 'directory.json.*').Count -eq 0) 'Directory rejection created sidecars.'
    $passed++

    # ACL verification failure must happen before payload writes and remove only its own file.
    $savedAssert = ${function:Assert-PrivateFileSecurity}
    $aclFailure = Join-Path $fixture 'acl-failure.json'
    try {
        function Assert-PrivateFileSecurity { param($Security) throw 'Injected ACL verification failure.' }
        Assert-Throws { Write-PrivateFile $aclFailure $encoding.GetBytes('fake-secret') } 'ACL failure was ignored.'
    } finally { Set-Item -Path Function:Assert-PrivateFileSecurity -Value $savedAssert }
    Assert-True (-not (Test-Path -LiteralPath $aclFailure)) 'ACL failure left an output file.'
    $passed++

    Write-Host "PASS: $passed Windows regression groups ($Language; PowerShell $($PSVersionTable.PSVersion))."
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
