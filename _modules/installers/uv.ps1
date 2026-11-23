param([string]$RootDir, [string]$ToolKey = "uv", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
$modRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $modRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $modRoot "core.psm1") -Global }

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$arch      = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$assetName = if ($arch -eq "ARM64") { "uv-aarch64-pc-windows-msvc.zip" } else { "uv-x86_64-pc-windows-msvc.zip" }

$tag = Get-GitHubLatestTag -Repo "astral-sh/uv"
$ver = $tag.TrimStart('v')
$url = "https://github.com/astral-sh/uv/releases/download/$tag/$assetName"

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "uv-$ver-$arch.zip" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"
$tmpDir    = Join-Path $RootDir "apps\_cache\tmp_uv"

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $pkgFile -DestinationPath $tmpDir -Force

Clear-ToolDirectory -TargetDir $targetDir
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

Get-ChildItem -Path $tmpDir -Filter "*.exe" -Recurse | Move-Item -Destination $targetDir -Force
Remove-Item $tmpDir -Recurse -Force

Set-SandboxEnvironment -RootDir $RootDir
$env:UV_PYTHON_INSTALL_DIR = Join-Path $RootDir "data\.uv\python"
$env:UV_PYTHON_BIN_DIR     = Join-Path $RootDir "data\.local\bin"
$env:UV_CACHE_DIR          = Join-Path $RootDir "data\.uv\cache"
$uvExe = Join-Path $targetDir "uv.exe"

Write-Status -Level "INFO" -Message "正在透過 uv 檢查並安裝受管 Python 環境至沙盒..."
& $uvExe python install --default

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver