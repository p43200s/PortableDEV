param([string]$RootDir, [string]$ToolKey = "nodejs", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
$modRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $modRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $modRoot "core.psm1") -Global }

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$index = Invoke-RestMethod "https://nodejs.org/dist/index.json"
$lts   = $index | Where-Object { $_.lts -ne $false } | Select-Object -First 1
$ver   = $lts.version.TrimStart('v')
$url   = "https://nodejs.org/dist/v$ver/node-v$ver-win-x64.zip"

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "nodejs-$ver.zip" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"
$tmpDir    = Join-Path $RootDir "apps\_cache\tmp_node"

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $pkgFile -DestinationPath $tmpDir -Force

Clear-ToolDirectory -TargetDir $targetDir
$innerDir = Get-ChildItem -Path $tmpDir -Directory -Filter "node-*" | Select-Object -First 1
Move-Item -Path $innerDir.FullName -Destination $targetDir
Remove-Item $tmpDir -Recurse -Force

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver