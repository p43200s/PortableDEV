param([string]$RootDir, [string]$ToolKey = "git", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "core.psm1") -Force

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$rel   = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
$asset = $rel.assets | Where-Object { $_.name -match '^PortableGit-.*-64-bit\.7z\.exe$' } | Select-Object -First 1
$ver   = ($rel.tag_name -replace '^v','' -replace '\.windows\.\d+$','')

if ($Mode -eq "query") { return @{ Version = $ver; Url = $asset.browser_download_url } }

$sevenZip  = Get-7ZipPath -RootDir $RootDir
$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $asset.browser_download_url -FileName "git-$ver.7z.exe" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"

Clear-ToolDirectory -TargetDir $targetDir
Write-Host "[INFO] 正在解壓縮 $($meta.Name)..." -ForegroundColor Cyan
& $sevenZip x $pkgFile "-o$targetDir" -y | Out-Null

Write-Host "[INFO] 執行 Git 首次初始化..." -ForegroundColor Cyan
$gitBash = Join-Path $targetDir "git-bash.exe"
Start-Process -FilePath $gitBash -ArgumentList "--no-needs-console", "--hide", "--no-cd", "--command=post-install.bat" -Wait

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver