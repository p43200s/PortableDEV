param([string]$RootDir, [string]$ToolKey = "agy", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
$modRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $modRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $modRoot "core.psm1") -Global }

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$arch     = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$platform = if ($arch -eq "ARM64") { "windows_arm64" } else { "windows_amd64" }

$manifest = Invoke-RestMethod "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/$platform.json"
$ver = $manifest.version
$url = $manifest.url

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "agy-$ver-$platform.exe" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"
$binPath   = Join-Path $targetDir "agy.exe"

Clear-ToolDirectory -TargetDir $targetDir
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
Copy-Item -Path $pkgFile -Destination $binPath -Force
Unblock-File -Path $binPath -ErrorAction SilentlyContinue

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver