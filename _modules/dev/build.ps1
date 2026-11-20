param([string]$RootDir)
$ErrorActionPreference = "Stop"

$modulesDir = Join-Path $RootDir "_modules"
if (-not (Test-Path $modulesDir)) {
    Write-Host "`n[ERROR] 找不到 _modules 目錄，無法執行打包。" -ForegroundColor Red
    return
}

# 自動從資料夾名稱擷取版本號，或手動輸入
$folderName = Split-Path $RootDir -Leaf
$defaultVer = if ($folderName -match '([\d\.]+)$') { $Matches[1] } else { "bundle" }
$verInput   = (Read-Host "`n請輸入打包版本號 (直接按 Enter 預設為 $defaultVer)").Trim()
$verTag     = if ($verInput) { $verInput } else { $defaultVer }

$outName = "PortableDEV_$verTag.bat"
$outPath = Join-Path $RootDir $outName

Write-Host "[INFO] 正在組裝 Polyglot 雙語混合單一執行檔 ($outName)..." -ForegroundColor Cyan

# 1. 讀取 tools.psd1
$toolsRaw = Get-Content (Join-Path $modulesDir "tools.psd1") -Raw -Encoding UTF8

# 2. 讀取並處理 core.psm1（移除 Export-ModuleMember，並轉為 Base64 供主執行緒與 RunspacePool 動態載入）
$coreRaw = Get-Content (Join-Path $modulesDir "core.psm1") -Raw -Encoding UTF8
$coreRaw = $coreRaw -replace '(?m)^\s*Export-ModuleMember.*$', ''
$coreB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($coreRaw))

# 3. 讀取所有 installers/*.ps1 並封裝為記憶體函式 Invoke-Installer_<name>
$installerFuncs = New-Object System.Text.StringBuilder
$installerFiles = Get-ChildItem -Path (Join-Path $modulesDir "installers") -Filter "*.ps1" | Sort-Object Name
foreach ($file in $installerFiles) {
    $baseName = $file.BaseName
    $code = Get-Content $file.FullName -Raw -Encoding UTF8
    $code = $code -replace '(?m)^\s*Import-Module\s+.*core\.psm1.*$', ''
    [void]$installerFuncs.AppendLine("function global:Invoke-Installer_$baseName {")
    [void]$installerFuncs.AppendLine($code)
    [void]$installerFuncs.AppendLine("}")
    [void]$installerFuncs.AppendLine("")
}

# 4. 讀取並適配 updater.ps1
$updaterRaw = Get-Content (Join-Path $modulesDir "updater.ps1") -Raw -Encoding UTF8
$updaterRaw = $updaterRaw -replace '(?m)^\s*Import-Module\s+.*core\.psm1.*$', ''

# 5. 讀取並適配 launcher.ps1
$launcherRaw = Get-Content (Join-Path $modulesDir "launcher.ps1") -Raw -Encoding UTF8
$launcherRaw = $launcherRaw -replace '\$RootDir\s*=\s*Split-Path\s+-Parent\s+\$PSScriptRoot', '$RootDir = $env:PORTABLE_DEV_ROOT'
$launcherRaw = $launcherRaw -replace '(?m)^\s*Import-Module\s+.*core\.psm1.*$', ''
$launcherRaw = $launcherRaw -replace '&\s*\(Join-Path\s+\$PSScriptRoot\s+"updater\.ps1"\)', 'Invoke-PortableUpdater'

# 6. 使用 StringBuilder 安全組合 Polyglot 雙語腳本（完全避免字串內插與壓縮解壓延遲）
$sb = New-Object System.Text.StringBuilder

# --- Polyglot 雙語檔頭（Batch 透過 Get-Content -Raw 讀取自身並轉為 ScriptBlock 執行，繞過 -File 副檔名限制） ---
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

# --- 以下為原生 PowerShell 執行主體 ---
[void]$sb.AppendLine('$ErrorActionPreference = "Stop"')
[void]$sb.AppendLine('$RootDir = $env:PORTABLE_DEV_ROOT')
[void]$sb.AppendLine('[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 載入工具設定檔至全域記憶體')
[void]$sb.AppendLine('$global:PortableToolsConfig = ' + $toolsRaw)
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 儲存 core.psm1 Base64 原始碼供主工作階段與 RunspacePool 動態載入')
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

# 7. 以 UTF-8 with BOM 寫出檔案，確保 Windows PowerShell 5.1 使用 -File 讀取時中文絕不亂碼
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8WithBom)

$sizeKB = [Math]::Round((Get-Item $outPath).Length / 1KB, 1)
Write-Host "[SUCCESS] 已成功打包 Polyglot 單一執行檔：$outName ($sizeKB KB)" -ForegroundColor Green
Write-Host "[TIP] 此單一 .bat 可秒開啟動，並可獨立複製至任何空資料夾執行。" -ForegroundColor Cyan