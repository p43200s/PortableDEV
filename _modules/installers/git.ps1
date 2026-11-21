param([string]$RootDir, [string]$ToolKey = "git", [string]$Mode = "install")
$ErrorActionPreference = "Stop"
$modRoot = Split-Path -Parent $PSScriptRoot
if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $modRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $modRoot "core.psm1") -Global }

$meta = Get-ToolMeta -RootDir $RootDir -ToolKey $ToolKey

$tag = Get-GitHubLatestTag -Repo "git-for-windows/git"
$ver = ($tag -replace '^v', '' -replace '\.windows\.\d+$', '')
$url = "https://github.com/git-for-windows/git/releases/download/$tag/PortableGit-$ver-64-bit.7z.exe"

if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

$sevenZip  = Get-7ZipPath -RootDir $RootDir
$pkgFile   = Get-CachedPackage -RootDir $RootDir -Url $url -FileName "git-$ver.7z.exe" -DisplayName "$($meta.Name) $ver"
$targetDir = Join-Path $RootDir "apps\$($meta.Dir)"

Clear-ToolDirectory -TargetDir $targetDir
Write-Status -Level "INFO" -Message "正在解壓縮 $($meta.Name)..."
& $sevenZip x $pkgFile "-o$targetDir" -y | Out-Null

Write-Status -Level "INFO" -Message "執行 Git 初始化..."
$gitBash = Join-Path $targetDir "git-bash.exe"
Start-Process -FilePath $gitBash -ArgumentList "--no-needs-console", "--hide", "--no-cd", "--command=post-install.bat" -Wait

Complete-ToolInstall -RootDir $RootDir -DirName $meta.Dir -Version $ver