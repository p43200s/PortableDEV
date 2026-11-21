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

# 透過 sdkmanager 自動接受所有授權並安裝/更新 platform-tools (ADB / Fastboot)
$sdkManager = Join-Path $latestDir "bin\sdkmanager.bat"
if (Test-Path $sdkManager) {
    $jdk17Meta = Get-ToolMeta -RootDir $RootDir -ToolKey "jdk17"
    if (-not (Confirm-ToolReady -RootDir $RootDir -ToolKey "jdk17" -ToolMeta $jdk17Meta)) {
        throw "Android SDK 依賴 OpenJDK 17，但自動安裝失敗。"
    }

    Set-SandboxEnvironment -RootDir $RootDir
    $env:ANDROID_HOME      = $targetDir
    $env:ANDROID_USER_HOME = Join-Path $RootDir "data\.android"
    $jdk17Dir              = Join-Path $RootDir "apps\$($jdk17Meta.Dir)"
    $env:JAVA_HOME         = $jdk17Dir
    $env:PATH              = "$(Join-Path $jdk17Dir 'bin');$env:PATH"

    Write-Status -Level "INFO" -Message "正在自動接受授權並安裝/更新 platform-tools (ADB)..."
    # 連續送出 15 個 y 以自動同意所有 SDK 授權條款
    cmd /c "(for /l %i in (1,1,15) do @echo y) | `"$sdkManager`" --licenses >nul 2>&1"
    cmd /c "(for /l %i in (1,1,15) do @echo y) | `"$sdkManager`" `"platform-tools`" --update"
}

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver
Write-Status -Level "TIP" -Message "已內建 platform-tools，進入環境後可直接使用 adb 與 fastboot！"