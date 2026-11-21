<#
super远程桌面 一键部署脚本（在需要被远程的公司电脑上，以管理员身份运行）

  安装员工助手版（推荐，只能被控）并设置固定密码：
    powershell -ExecutionPolicy Bypass -File deploy-superdesk.ps1 -Password "公司统一密码"
  安装完整版：
    ... -Flavor full -Password "..."
  也可以直接从服务器下载并运行（管理员 PowerShell）：
    iwr __SUPERDESK_SERVER__/download/deploy-superdesk.ps1 -OutFile $env:TEMP\d.ps1; & $env:TEMP\d.ps1 -Password "..."

完成后：电脑作为系统服务开机自启，IT 可用 ID + 固定密码无人值守连接；
本机 ID / 电脑名会上报到管理后台（super控制台 → 设备）。
#>
param(
    [ValidateSet('helper', 'full')]
    [string]$Flavor = 'helper',
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [string]$Server = '__SUPERDESK_SERVER__',
    [string]$Note = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '请以管理员身份运行此脚本。'
}
if ($Password.Length -lt 8) { throw '固定密码至少 8 位。' }
$Server = $Server.TrimEnd('/')

Write-Host "==> 获取最新版本信息 ($Server)"
$latest = Invoke-RestMethod "$Server/download/latest.json" -TimeoutSec 30
$entry = $latest.clients."windows-$Flavor"
if (-not $entry) { throw "服务器上没有 windows-$Flavor 版本。" }
$app = $entry.app_name
$url = if ($entry.url.StartsWith('/')) { "$Server$($entry.url)" } else { $entry.url }

Write-Host "==> 下载 $($entry.file)"
$exe = Join-Path $env:TEMP $entry.file
Invoke-WebRequest $url -OutFile $exe -TimeoutSec 1800
# .NET instead of Get-FileHash: that one lives in a script module which fails to load when
# Windows PowerShell is started from PowerShell 7 (inherited PSModulePath).
$fs = [IO.File]::OpenRead($exe)
try { $hash = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($fs) | ForEach-Object { $_.ToString('X2') }) }
finally { $fs.Dispose() }
if ($entry.sha256 -and $hash -ne $entry.sha256.ToUpper()) {
    throw '安装包校验失败（SHA256 不匹配），已中止。'
}

$pf = if ($env:ProgramFiles) { $env:ProgramFiles } else { 'C:\Program Files' }
$installDir = Join-Path $pf $app
$installed = Join-Path $installDir "$app.exe"

# Re-deploy / upgrade: remove the old installation first. Installing over it races with the
# still-running service (a locked librustdesk.dll is silently skipped by the copy).
if ((Get-Service -Name $app -ErrorAction SilentlyContinue) -or (Test-Path $installed)) {
    Write-Host '==> 检测到已安装的旧版本，先卸载'
    Stop-Service -Name $app -Force -ErrorAction SilentlyContinue
    Get-Process | Where-Object { $_.Path -like "$installDir\*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    # Uninstall with the NEW package: the installed copy may be broken.
    $u = Start-Process -FilePath $exe -ArgumentList '--uninstall' -PassThru
    $u.WaitForExit()
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Service -Name $app -ErrorAction SilentlyContinue) -or (Test-Path $installed)) {
        if ((Get-Date) -gt $deadline) { throw '卸载旧版本超时，请手动卸载后重试。' }
        Start-Sleep -Seconds 3
    }
}

Write-Host "==> 静默安装 $app"
# Not `Start-Process -Wait`: that waits for the whole process tree, and a successful install leaves
# the service/tray processes running forever. Wait for the launcher only, then poll for the result.
$p = Start-Process -FilePath $exe -ArgumentList '--silent-install' -PassThru
$p.WaitForExit()
# The packer starts the real installer asynchronously: wait for the installed exe + service.
$deadline = (Get-Date).AddMinutes(5)
while (-not ((Test-Path $installed) -and (Get-Service -Name $app -ErrorAction SilentlyContinue))) {
    if ((Get-Date) -gt $deadline) { throw "安装超时：未找到 $installed 或服务 $app。" }
    Start-Sleep -Seconds 3
}
Start-Sleep -Seconds 5

Write-Host '==> 设置固定密码'
$r = (& $installed --password $Password | Out-String).Trim()
if ($r -notmatch 'Done') { Write-Warning "设置密码返回：$r" }

Write-Host '==> 读取本机 ID'
$id = ''
for ($i = 0; $i -lt 20 -and -not $id; $i++) {
    $id = (& $installed --get-id | Out-String).Trim()
    if (-not $id) { Start-Sleep -Seconds 3 }
}

$body = @{
    id = $id; hostname = $env:COMPUTERNAME; user = $env:USERNAME
    flavor = $Flavor; build = $entry.build; note = $Note
} | ConvertTo-Json
try {
    Invoke-RestMethod "$Server/api/superdesk/deploy" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec 20 | Out-Null
} catch { Write-Warning "上报管理后台失败（不影响使用）：$_" }

Write-Host ''
Write-Host "部署完成：$env:COMPUTERNAME  ID = $id" -ForegroundColor Green
Remove-Item $exe -ErrorAction SilentlyContinue
