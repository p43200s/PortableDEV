param([string]$RootDir, [string]$ToolKey = "android", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "core.psm1") -Force

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$html = (Invoke-WebRequest "https://developer.android.com/studio#command-line-tools-only" -UseBasicParsing).Content
if ($html -match 'commandlinetools-win-(\d+)_latest\.zip') {
    $ver = $Matches[1]
    $url = "https://dl.google.com/android/repository/commandlinetools-win-${ver}_latest.zip"
} else {
    throw "無法從 Android 官網解析 Command-line Tools 版本"
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

# 若本機已安裝過 SDK 平台套件，呼叫官方 sdkmanager 同步升級 platform-tools / platforms / build-tools
$sdkManager = Join-Path $latestDir "bin\sdkmanager.bat"
if ((Test-Path (Join-Path $targetDir "platform-tools")) -and (Test-Path $sdkManager)) {
    Write-Host "[INFO] 偵測到已安裝 Android 平台套件，正在透過 sdkmanager 檢查並更新..." -ForegroundColor Cyan
    Set-SandboxEnvironment -RootDir $RootDir
    $env:ANDROID_HOME = $targetDir
    $jdk17Meta = Get-ToolMeta -RootDir $RootDir -ToolKey "jdk17"
    $jdk17Dir  = Join-Path $RootDir "apps\$($jdk17Meta.Dir)"
    if (Test-Path $jdk17Dir) {
        $env:JAVA_HOME = $jdk17Dir
        $env:PATH = "$(Join-Path $jdk17Dir 'bin');$env:PATH"
    }
    cmd /c "echo y| `"$sdkManager`" --update"
}

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver
Write-Host "[TIP] 進入 Android 除錯環境後，可執行 'sdkmanager platform-tools' 安裝 ADB！" -ForegroundColor Cyan