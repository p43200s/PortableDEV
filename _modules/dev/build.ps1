param([string]$RootDir)
$ErrorActionPreference = "Stop"

$modulesDir = Join-Path $RootDir "_modules"
if (-not (Test-Path $modulesDir)) {
    Write-Status -Level "ERR" -Message "找不到 _modules 目錄，無法打包。"
    return
}

# 讀取 tools.psd1 內的版本編號
$appCfg  = Get-AppConfig -RootDir $RootDir
$verTag  = $appCfg.AppVer
$outName = "PortableDEV_$verTag.bat"
$outPath = Join-Path $RootDir $outName

Write-Host ""
Write-Status -Level "INFO" -Message "正在組裝 Polyglot 雙語混合單一執行檔 ($outName)..."

# 1. 讀取 tools.psd1
$toolsRaw = Get-Content (Join-Path $modulesDir "tools.psd1") -Raw -Encoding UTF8

# 2. 讀取並處理 ui.psm1（轉為 Base64 供主執行緒與 RunspacePool 動態載入）
$uiRaw = Get-Content (Join-Path $modulesDir "ui.psm1") -Raw -Encoding UTF8
$uiRaw = $uiRaw -replace '(?m)^\s*Export-ModuleMember.*$', ''
$uiB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($uiRaw))

# 3. 讀取並處理 core.psm1
$coreRaw = Get-Content (Join-Path $modulesDir "core.psm1") -Raw -Encoding UTF8
$coreRaw = $coreRaw -replace '(?m)^\s*Export-ModuleMember.*$', ''
$coreB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($coreRaw))

# 4. 讀取所有 installers/*.ps1 並封裝為記憶體函式 Invoke-Installer_<name>
$installerFuncs = New-Object System.Text.StringBuilder
$installerFiles = Get-ChildItem -Path (Join-Path $modulesDir "installers") -Filter "*.ps1" | Sort-Object Name
foreach ($file in $installerFiles) {
    $baseName = $file.BaseName
    $code = Get-Content $file.FullName -Raw -Encoding UTF8
    $code = $code -replace '(?m)^\s*\$modRoot\s*=.*$', ''
    $code = $code -replace '(?m)^.*Import-Module\s+.*(core|ui)\.psm1.*$', ''
    [void]$installerFuncs.AppendLine("function global:Invoke-Installer_$baseName {")
    [void]$installerFuncs.AppendLine($code)
    [void]$installerFuncs.AppendLine("}")
    [void]$installerFuncs.AppendLine("")
}

# 5. 讀取並適配 updater.ps1
$updaterRaw = Get-Content (Join-Path $modulesDir "updater.ps1") -Raw -Encoding UTF8
$updaterRaw = $updaterRaw -replace '(?m)^.*Import-Module\s+.*(core|ui)\.psm1.*$', ''

# 6. 讀取並適配 launcher.ps1
$launcherRaw = Get-Content (Join-Path $modulesDir "launcher.ps1") -Raw -Encoding UTF8
$launcherRaw = $launcherRaw -replace '(?m)^.*Import-Module\s+.*(core|ui)\.psm1.*$', ''
$launcherRaw = $launcherRaw -replace '&\s*\(Join-Path\s+\$PSScriptRoot\s+"updater\.ps1"\)', 'Invoke-PortableUpdater'

# 7. 使用 StringBuilder 安全組合 Polyglot 雙語腳本
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('<# :')
[void]$sb.AppendLine('@echo off')
[void]$sb.AppendLine('chcp 65001 >nul')
[void]$sb.AppendLine('set "PORTABLE_DEV_ROOT=%~dp0"')
[void]$sb.AppendLine('if "%PORTABLE_DEV_ROOT:~-1%"=="\" set "PORTABLE_DEV_ROOT=%PORTABLE_DEV_ROOT:~0,-1%"')
[void]$sb.AppendLine('set "PORTABLE_DEV_FILE=%~f0"')
[void]$sb.AppendLine('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((Get-Content -LiteralPath $env:PORTABLE_DEV_FILE -Raw -Encoding UTF8)))"')
[void]$sb.AppendLine('exit /b %ERRORLEVEL%')
[void]$sb.AppendLine('#>')
[void]$sb.AppendLine('')

[void]$sb.AppendLine('$ErrorActionPreference = "Stop"')
[void]$sb.AppendLine('$RootDir = $env:PORTABLE_DEV_ROOT')
[void]$sb.AppendLine('[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 載入工具設定檔至全域記憶體')
[void]$sb.AppendLine('$global:PortableAppConfig = ' + $toolsRaw)
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 載入 ui.psm1 與 core.psm1 Base64 原始碼供主工作階段與 RunspacePool 動態載入')
[void]$sb.AppendLine('$global:PortableUISourceB64 = "' + $uiB64 + '"')
[void]$sb.AppendLine('$uiSrc = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($global:PortableUISourceB64))')
[void]$sb.AppendLine('New-Module -Name "PortableUI" -ScriptBlock ([ScriptBlock]::Create($uiSrc)) | Import-Module -Force')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('$global:PortableCoreSourceB64 = "' + $coreB64 + '"')
[void]$sb.AppendLine('$coreSrc = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($global:PortableCoreSourceB64))')
[void]$sb.AppendLine('New-Module -Name "PortableCore" -ScriptBlock ([ScriptBlock]::Create($coreSrc)) | Import-Module -Force')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 註冊所有安裝器函式')
[void]$sb.AppendLine($installerFuncs.ToString())
[void]$sb.AppendLine('# 註冊更新中心函式')
[void]$sb.AppendLine('function global:Invoke-PortableUpdater {')
[void]$sb.AppendLine($updaterRaw)
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 啟動主選單')
[void]$sb.AppendLine($launcherRaw)

# 8. 以 UTF-8 with BOM 寫出檔案
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8WithBom)

$sizeKB = [Math]::Round((Get-Item $outPath).Length / 1KB, 1)
Write-Status -Level "OK" -Message "成功打包成單一執行檔：$outName ($sizeKB KB)"
Write-Status -Level "TIP" -Message "這個 .bat 可獨立啟動，建議放到空資料夾內執行。"