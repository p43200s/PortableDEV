param([string]$RootDir, [string]$ToolKey = "android", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
$modRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $modRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $modRoot "core.psm1") -Global }

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$html = (Invoke-WebRequest "https://developer.android.com/studio#command-line-tools-only" -UseBasicParsing).Content
if ($html -match 'commandlinetools-win-(\d+)_latest\.zip') {
    $ver = $Matches[1]
    $url = "https://dl.google.com/android/repository/commandlinetools-win-${ver}_latest.zip"
} else {
    throw "無法從 Android 官方網站解析 Command-line Tools 版本"
}

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "android-cmdtools-$ver.zip" -DisplayName "$($meta.Name) (Build $ver)"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"
$tmpDir    = Join-Path $RootDir "apps\_cache\tmp_android"

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $pkgFile -DestinationPath $tmpDir -Force

# 僅替換 cmdline-tools\latest，完整保留同層級既有的 platform-tools、platforms、build-tools
$latestDir = Join-Path $targetDir "cmdline-tools\latest"
Clear-ToolDirectory -TargetDir $latestDir
New-Item -ItemType Directory -Path (Split-Path -Parent $latestDir) -Force | Out-Null
Move-Item -Path (Join-Path $tmpDir "cmdline-tools") -Destination $latestDir
Remove-Item $tmpDir -Recurse -Force

# 自動在解壓縮目錄中尋找新版 Android CLI (android.exe 或 android.bat)
$androidCliItem = Get-ChildItem -Path $latestDir -Include "android.exe", "android.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $androidCliItem) {
    throw "在解壓縮目錄中找不到新版 Android CLI ($latestDir)"
}
$androidCli = $androidCliItem.FullName

$jdk17Meta = Get-ToolMeta -RootDir $RootDir -ToolKey "jdk17"
if (-not (Confirm-ToolReady -RootDir $RootDir -ToolKey "jdk17" -ToolMeta $jdk17Meta)) {
    throw "Android CLI 依賴 OpenJDK 17，但自動安裝失敗。"
}

Set-SandboxEnvironment -RootDir $RootDir
$env:ANDROID_HOME      = $targetDir
$env:ANDROID_USER_HOME = Join-Path $RootDir "data\.android"
$jdk17Dir              = Join-Path $RootDir "apps\$($jdk17Meta.Dir)"
$env:JAVA_HOME         = $jdk17Dir
$env:PATH              = "$(Join-Path $jdk17Dir 'bin');$env:PATH"

Write-Status -Level "INFO" -Message "正在透過新版 Android CLI 安裝/更新 platform-tools (ADB / Fastboot)..."

$prevErrPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"

try {
    # 使用新版 android CLI 安裝 platform-tools（自動傳入 y 確認授權提示）
    "y" | & $androidCli sdk install platform-tools
    if ($LASTEXITCODE -ne 0) {
        throw "platform-tools 安裝失敗 (結束代碼: $LASTEXITCODE)"
    }
} finally {
    $ErrorActionPreference = $prevErrPref
}

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver
Write-Status -Level "TIP" -Message "已內建 platform-tools，進入環境後可直接使用 android、adb 與 fastboot！"