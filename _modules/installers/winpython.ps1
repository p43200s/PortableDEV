param([string]$RootDir, [string]$ToolKey = "winpython", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "core.psm1") -Force

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$rel   = Invoke-RestMethod "https://api.github.com/repos/winpython/winpython/releases/latest"
$asset = $rel.assets | Where-Object { $_.name -match 'WinPython64-.*slim.*\.(exe|7z)$' } | Select-Object -First 1
$ver   = ($asset.name -replace '^WinPython64-','' -replace 'slim.*$','')

if ($Mode -eq "query") { return @{ Version = $ver; Url = $asset.browser_download_url } }

$sevenZip  = Get-7ZipPath -RootDir $RootDir
$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $asset.browser_download_url -FileName $asset.name -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"
$tmpDir    = Join-Path $RootDir "apps\_cache\tmp_wpy"

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Write-Host "[INFO] 正在解壓縮 $($meta.Name)..." -ForegroundColor Cyan
& $sevenZip x $pkgFile "-o$tmpDir" -y | Out-Null

Clear-ToolDirectory -TargetDir $targetDir
$innerDir = Get-ChildItem -Path $tmpDir -Directory -Filter "WPy*" | Select-Object -First 1
Move-Item -Path $innerDir.FullName -Destination $targetDir
Remove-Item $tmpDir -Recurse -Force

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver