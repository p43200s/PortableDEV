$global:ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 模組首次載入時記錄宿主機原始環境變數快照，供切換環境時還原使用
if (-not $script:BaseEnvSnapshot) {
    $script:BaseEnvSnapshot = @{}
    foreach ($entry in [Environment]::GetEnvironmentVariables("Process").GetEnumerator()) {
        $script:BaseEnvSnapshot[$entry.Key] = $entry.Value
    }
}

function Restore-BaseEnvironment {
    if (-not $script:BaseEnvSnapshot) { return }
    $currentVars = [Environment]::GetEnvironmentVariables("Process")
    foreach ($key in @($currentVars.Keys)) {
        if (-not $script:BaseEnvSnapshot.ContainsKey($key)) {
            [Environment]::SetEnvironmentVariable($key, $null, "Process")
        }
    }
    foreach ($key in $script:BaseEnvSnapshot.Keys) {
        [Environment]::SetEnvironmentVariable($key, $script:BaseEnvSnapshot[$key], "Process")
    }
}

function Get-AppConfig {
    param([string]$RootDir = $env:PORTABLE_DEV_ROOT)
    if ($global:PortableAppConfig) {
        return $global:PortableAppConfig
    }
    $psdPath = Join-Path $RootDir "_modules\tools.psd1"
    if (Test-Path $psdPath) {
        $global:PortableAppConfig = Import-PowerShellDataFile $psdPath
        return $global:PortableAppConfig
    }
    throw "找不到設定檔: $psdPath"
}

function Get-AppVersion {
    param([string]$RootDir = $env:PORTABLE_DEV_ROOT)
    return (Get-AppConfig -RootDir $RootDir).AppVer
}

function Get-ToolsConfig {
    param([string]$RootDir = $env:PORTABLE_DEV_ROOT)
    return (Get-AppConfig -RootDir $RootDir).Tools
}

function Get-ToolMeta {
    param(
        [string]$RootDir,
        [string]$ToolKey
    )
    $toolsCfg = Get-ToolsConfig -RootDir $RootDir
    if (-not $toolsCfg.ContainsKey($ToolKey)) {
        throw "在 tools.psd1 中找不到工具定義: [$ToolKey]"
    }
    return $toolsCfg[$ToolKey]
}

function Set-SandboxEnvironment {
    param([string]$RootDir)
    $dataDir = Join-Path $RootDir "data"
    [Environment]::SetEnvironmentVariable("USERPROFILE",  $dataDir, "Process")
    [Environment]::SetEnvironmentVariable("HOME",         $dataDir, "Process")
    [Environment]::SetEnvironmentVariable("APPDATA",      (Join-Path $dataDir "AppData\Roaming"), "Process")
    [Environment]::SetEnvironmentVariable("LOCALAPPDATA", (Join-Path $dataDir "AppData\Local"), "Process")
}

function Initialize-PortableDirs {
    param([string]$RootDir)
    $dirs = @(
        "workspace", "data", "apps", "apps\_cache",
        "data\Documents", "data\Documents\WindowsPowerShell",
        "data\AppData\Roaming", "data\AppData\Local",
        "data\agy-home", "data\.npm-global", "data\.npm-cache",
        "data\.config", "data\.uv", "data\.uv\bin", "data\.uv\python",
        "data\vscode\user-data\User", "data\vscode\extensions"
    )
    foreach ($d in $dirs) {
        $fullPath = Join-Path $RootDir $d
        if (-not (Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        }
    }
}

function Get-UvPythonExe {
    param([string]$RootDir)
    $uvPyRoot = Join-Path $RootDir "data\.uv\python"
    if (-not (Test-Path $uvPyRoot)) { return $null }
    return Get-ChildItem -Path $uvPyRoot -Filter "python.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
}

function Initialize-VSCodeConfig {
    param([string]$RootDir)
    $vsDataDir     = Join-Path $RootDir "data\vscode"
    $vsUserDataDir = Join-Path $vsDataDir "user-data"
    $vsExtDir      = Join-Path $vsDataDir "extensions"
    $userConfigDir = Join-Path $vsUserDataDir "User"

    foreach ($d in @($vsDataDir, $vsUserDataDir, $vsExtDir, $userConfigDir)) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $argvFile  = Join-Path $userConfigDir "argv.json"
    if (-not (Test-Path $argvFile)) {
        $defaultArgv = @"
{
    "enable-crash-reporter": false,
    "locale": "zh-tw"
}
"@
        [System.IO.File]::WriteAllText($argvFile, $defaultArgv, $utf8NoBom)
    }

    return @{
        DataDir       = $vsDataDir
        UserDataDir   = $vsUserDataDir
        ExtensionsDir = $vsExtDir
        UserConfigDir = $userConfigDir
    }
}

function Get-CachedPackage {
    param(
        [string]$RootDir,
        [string]$Url,
        [string]$FileName,
        [string]$DisplayName
    )
    $cacheDir = Join-Path $RootDir "apps\_cache"
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $pkgFile = Join-Path $cacheDir $FileName
    $tmpFile = "$pkgFile.tmp"

    if ((Test-Path $pkgFile) -and ((Get-Item $pkgFile).Length -gt 0)) {
        Write-Status -Level "CACHE" -Message "找到本地快取 ($FileName)，跳過下載！"
        return $pkgFile
    }

    if ((Test-Path $tmpFile) -and ((Get-Item $tmpFile).Length -gt 0)) {
        $resumeMB = [Math]::Round((Get-Item $tmpFile).Length / 1MB, 2)
        Write-Status -Level "INFO" -Message "偵測到未完成暫存檔 ($resumeMB MB)，接續下載 $DisplayName..."
    } else {
        Write-Status -Level "INFO" -Message "正在下載 $DisplayName..."
    }

    & curl.exe -L -f -C - --progress-bar "$Url" -o "$tmpFile"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpFile) -or ((Get-Item $tmpFile).Length -eq 0)) {
        throw "下載 $DisplayName 失敗或中斷（暫存檔已保留，下次執行可接續下載）。"
    }

    if (Test-Path $pkgFile) { Remove-Item $pkgFile -Force -ErrorAction SilentlyContinue }
    Move-Item -Path $tmpFile -Destination $pkgFile -Force
    return $pkgFile
}

function Clear-ToolDirectory {
    param([string]$TargetDir)
    if (-not (Test-Path $TargetDir)) { return }

    $item = Get-Item -LiteralPath $TargetDir -Force
    if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        cmd /c rmdir "`"$TargetDir`"" 2>$null
        return
    }

    try {
        # 先移除內部檔案的唯讀/系統/隱藏屬性，避免 PortableGit 等工具重裝時刪除失敗
        cmd /c "attrib -r -s -h `"$TargetDir\*`" /s /d" 2>$null
        Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction Stop
    } catch {
        throw "無法清除目標資料夾 [$TargetDir]，請確認該工具的相關視窗或背景程式已完全關閉後再試。"
    }
}

function Get-7ZipPath {
    param([string]$RootDir)
    $cacheDir = Join-Path $RootDir "apps\_cache"
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $exe = Join-Path $cacheDir "7zr.exe"
    if (-not (Test-Path $exe) -or ((Get-Item $exe).Length -eq 0)) {
        $tmpExe = "$exe.tmp"
        Write-Status -Level "INFO" -Message "正在下載解壓縮工具 7zr.exe..."
        & curl.exe -L -f -C - --progress-bar "https://www.7-zip.org/a/7zr.exe" -o "$tmpExe"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpExe) -or ((Get-Item $tmpExe).Length -eq 0)) {
            throw "下載 7zr.exe 失敗。"
        }
        if (Test-Path $exe) { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
        Move-Item -Path $tmpExe -Destination $exe -Force
    }
    return $exe
}

function Complete-ToolInstall {
    param(
        [string]$RootDir,
        [string]$DirName,
        [string]$Version
    )
    $targetDir = Join-Path $RootDir "apps\$DirName"
    Set-Content -Path (Join-Path $targetDir "version.txt") -Value $Version -Encoding ASCII
    Write-Status -Level "OK" -Message "$DirName ($Version) 安裝完成！"
}

function Confirm-ToolReady {
    param(
        [string]$RootDir,
        [string]$ToolKey,
        [hashtable]$ToolMeta
    )
    $targetDir = Join-Path $RootDir "apps\$($ToolMeta.Dir)"

    if ((Test-Path $targetDir) -and (Get-ChildItem $targetDir -ErrorAction SilentlyContinue)) {
        return $true
    }

    Write-Status -Level "WARN" -Message "尚未安裝 $($ToolMeta.Name)，正在啟動自動安裝..."
    $scriptName = if ($ToolMeta.Installer) { $ToolMeta.Installer } else { $ToolKey }
    $memFunc    = "Invoke-Installer_$scriptName"
    $installer  = Join-Path $RootDir "_modules\installers\$scriptName.ps1"

    if (Get-Command $memFunc -ErrorAction SilentlyContinue) {
        & $memFunc -RootDir $RootDir -ToolKey $ToolKey -Mode "install"
        return (Test-Path $targetDir)
    } elseif (Test-Path $installer) {
        & $installer -RootDir $RootDir -ToolKey $ToolKey -Mode "install"
        return (Test-Path $targetDir)
    } else {
        Write-Status -Level "ERR" -Message "找不到安裝腳本或內建模組: $scriptName"
        return $false
    }
}

function Mount-PortableProfile {
    param(
        [string]$RootDir,
        [string[]]$ToolKeys
    )
    Restore-BaseEnvironment

    $toolsCfg = Get-ToolsConfig -RootDir $RootDir
    $wsDir    = Join-Path $RootDir "workspace"
    $dataDir  = Join-Path $RootDir "data"

    Set-SandboxEnvironment -RootDir $RootDir

    $addedPaths = @()

    foreach ($key in $ToolKeys) {
        $meta = $toolsCfg[$key]
        if (-not (Confirm-ToolReady -RootDir $RootDir -ToolKey $key -ToolMeta $meta)) {
            throw "模組 [$key] 初始化失敗，中止啟動。"
        }

        $appDir = Join-Path $RootDir "apps\$($meta.Dir)"

        foreach ($rel in $meta.Paths) {
            if ($rel -like "{DATA}*") {
                $addedPaths += $rel.Replace("{DATA}", $dataDir)
            } elseif ($rel -like "{WORKSPACE}*") {
                $addedPaths += $rel.Replace("{WORKSPACE}", $wsDir)
            } elseif ([string]::IsNullOrEmpty($rel)) {
                $addedPaths += $appDir
            } else {
                $addedPaths += (Join-Path $appDir $rel)
            }
        }

        if ($meta.Env) {
            foreach ($envKey in $meta.Env.Keys) {
                $val = $meta.Env[$envKey].Replace("{APP}", $appDir).Replace("{WORKSPACE}", $wsDir).Replace("{DATA}", $dataDir)
                [Environment]::SetEnvironmentVariable($envKey, $val, "Process")
            }
        }
    }

    $env:PATH = ($addedPaths -join ";") + ";" + $env:PATH
}

function Test-PortableEnvironment {
    param(
        [string]$RootDir,
        [string[]]$ToolKeys
    )
    $div = Get-LineDivider
    Write-Host "`n$div" -ForegroundColor DarkCyan
    Write-Host " 環境自我檢測報告" -ForegroundColor Cyan
    Write-Host $div -ForegroundColor DarkCyan

    $toolsCfg = Get-ToolsConfig -RootDir $RootDir
    $hasError = $false

    foreach ($key in $ToolKeys) {
        $meta = $toolsCfg[$key]
        if (-not $meta -or -not $meta.VerifyCmd) { continue }

        $parts   = $meta.VerifyCmd -split '\s+', 2
        $cmdName = $parts[0]
        $cmdArgs = if ($parts.Count -gt 1) { $parts[1] } else { "" }

        $cmdInfo = Get-Command $cmdName -ErrorAction SilentlyContinue
        if ($cmdInfo -and ($cmdInfo.Source -like "*$RootDir*")) {
            $rawOut = cmd /c "`"$($cmdInfo.Source)`" $cmdArgs 2>&1"
            $lines  = @($rawOut | Where-Object { $_ -and $_.ToString().Trim() -ne "" })
            $verOut = if ($key -eq "android") {
                ($lines | Select-Object -Last 1).ToString().Trim()
            } else {
                ($lines | Select-Object -First 1).ToString().Trim()
            }
            Write-Host ("  [OK] {0,-10} -> {1}" -f $key.ToUpper(), $verOut) -ForegroundColor Green
        } else {
            $actual = if ($cmdInfo) { $cmdInfo.Source } else { "找不到執行檔" }
            Write-Host ("  [FAIL] {0,-8} -> 路徑異常 ($actual)" -f $key.ToUpper()) -ForegroundColor Red
            $hasError = $true
        }
    }

    Write-Host $div -ForegroundColor DarkGray
    Write-Host "  沙盒家目錄    : $env:USERPROFILE" -ForegroundColor Gray
    Write-Host "  NPM 全域目錄  : $env:NPM_CONFIG_PREFIX" -ForegroundColor Gray
    if ($env:UV_PYTHON_INSTALL_DIR) {
        Write-Host "  UV Python目錄 : $env:UV_PYTHON_INSTALL_DIR" -ForegroundColor Gray
    }
    if ($env:GEMINI_CLI_HOME) {
        Write-Host "  Agy 設定目錄  : $env:GEMINI_CLI_HOME" -ForegroundColor Gray
    }
    Write-Host "$div`n" -ForegroundColor DarkCyan

    if ($hasError) {
        Write-Status -Level "WARN" -Message "偵測到部分工具路徑異常，請檢查上方 [FAIL] 訊息。"
        Wait-UserPause -Message "<< 按 Enter 鍵繼續啟動（或按 Ctrl+C 中止） >>"
    }
}

function Get-GitHubLatestTag {
    param([string]$Repo)
    $latestUrl = "https://github.com/$Repo/releases/latest"
    # 利用 curl.exe 僅抓取標頭並追蹤重導向 (-sIL)，從最終有效網址 (%{url_effective}) 擷取版號
    $effectiveUrl = & curl.exe -sIL -o NUL -w "%{url_effective}" "$latestUrl"
    if ($LASTEXITCODE -eq 0 -and $effectiveUrl -match '/releases/tag/([^/\s]+)$') {
        return $Matches[1]
    }
    throw "無法從 GitHub 取得 $Repo 最新版本資訊"
}

Export-ModuleMember -Function Restore-BaseEnvironment, Get-AppConfig, Get-AppVersion, Get-ToolsConfig, Get-ToolMeta, Set-SandboxEnvironment, Initialize-PortableDirs, Get-UvPythonExe, Initialize-VSCodeConfig, Get-CachedPackage, Clear-ToolDirectory, Get-7ZipPath, Complete-ToolInstall, Confirm-ToolReady, Mount-PortableProfile, Test-PortableEnvironment, Get-GitHubLatestTag