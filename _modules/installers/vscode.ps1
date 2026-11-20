param([string]$RootDir, [string]$ToolKey = "vscode", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "core.psm1") -Force

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$api = Invoke-RestMethod "https://update.code.visualstudio.com/api/update/win32-x64-archive/stable/latest"
$ver = $api.productVersion
$url = $api.url

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "vscode-$ver.zip" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"

Clear-ToolDirectory -TargetDir $targetDir
Write-Host "[INFO] 正在解壓縮 $($meta.Name)..." -ForegroundColor Cyan
Expand-Archive -Path $pkgFile -DestinationPath $targetDir -Force

# 確保獨立安裝擴充套件時同樣隔離於 data 沙盒內
Set-SandboxEnvironment -RootDir $RootDir
$vsPaths = Initialize-VSCodeConfig -RootDir $RootDir

$env:VSCODE_PORTABLE = $vsPaths.DataDir
$codeCmd = Join-Path $targetDir "bin\code.cmd"
$installedExts = cmd /c "`"`"$codeCmd`" --user-data-dir `"$($vsPaths.UserDataDir)`" --extensions-dir `"$($vsPaths.ExtensionsDir)`" --list-extensions`"" 2>$null

$extensions = @(
    "MS-CEINTL.vscode-language-pack-zh-hant",
    "ms-python.python"
)

foreach ($ext in $extensions) {
    if ($installedExts -and ($installedExts -match [regex]::Escape($ext))) {
        Write-Host "[SKIP] 擴充套件已存在: $ext" -ForegroundColor Gray
    } else {
        Write-Host "[INFO] 正在安裝擴充套件: $ext ..." -ForegroundColor Cyan
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"`"$codeCmd`" --user-data-dir `"$($vsPaths.UserDataDir)`" --extensions-dir `"$($vsPaths.ExtensionsDir)`" --install-extension $ext --force`"" -NoNewWindow -Wait
    }
}

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver