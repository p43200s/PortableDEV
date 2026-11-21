param([string]$RootDir, [string]$ToolKey = "vscode", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
$modRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $modRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $modRoot "core.psm1") -Global }

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$api = Invoke-RestMethod "https://update.code.visualstudio.com/api/update/win32-x64-archive/stable/latest"
$ver = $api.productVersion
$url = $api.url

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "vscode-$ver.zip" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"

Clear-ToolDirectory -TargetDir $targetDir
Write-Status -Level "INFO" -Message "正在解壓縮 $($meta.Name)..."
Expand-Archive -Path $pkgFile -DestinationPath $targetDir -Force

Set-SandboxEnvironment -RootDir $RootDir
$vsPaths = Initialize-VSCodeConfig -RootDir $RootDir

$env:VSCODE_PORTABLE = $vsPaths.DataDir
$codeCmd = Join-Path $targetDir "bin\code.cmd"

# 暫時放寬錯誤中止層級，避免 CLI 輸出非致命訊息到 stderr 時觸發 Stop
$prevErrPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$installedExts = & $codeCmd --user-data-dir "$($vsPaths.UserDataDir)" --extensions-dir "$($vsPaths.ExtensionsDir)" --list-extensions 2>&1 | Out-String

$extensions = @(
    "MS-CEINTL.vscode-language-pack-zh-hant",
    "ms-python.python"
)

foreach ($ext in $extensions) {
    if ($installedExts -match [regex]::Escape($ext)) {
        Write-Status -Level "SKIP" -Message "擴充套件已存在: $ext"
    } else {
        Write-Status -Level "INFO" -Message "正在安裝擴充套件: $ext ..."
        & $codeCmd --user-data-dir "$($vsPaths.UserDataDir)" --extensions-dir "$($vsPaths.ExtensionsDir)" --install-extension $ext --force
    }
}

$ErrorActionPreference = $prevErrPref

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver