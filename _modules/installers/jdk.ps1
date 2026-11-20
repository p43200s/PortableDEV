param([string]$RootDir, [string]$ToolKey, [string]$Mode = "install")
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "core.psm1") -Force

$meta  = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey
$major = $meta.MajorVersion

$api = Invoke-RestMethod "https://api.adoptium.net/v3/assets/latest/$major/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"
$ver = $api[0].version.semver
$url = $api[0].binary.package.link

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$safeVer   = $ver -replace '\+', '_'
$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "jdk$major-$safeVer.zip" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"
$tmpDir    = Join-Path $RootDir "apps\_cache\tmp_jdk$major"

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $pkgFile -DestinationPath $tmpDir -Force

Clear-ToolDirectory -TargetDir $targetDir
$innerDir = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
Move-Item -Path $innerDir.FullName -Destination $targetDir
Remove-Item $tmpDir -Recurse -Force

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver