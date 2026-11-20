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

function Get-ToolsConfig {
    param([string]$RootDir)
    if ($global:PortableToolsConfig) {
        return $global:PortableToolsConfig
    }
    return Import-PowerShellDataFile (Join-Path $RootDir "_modules\tools.psd1")
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
        "workspace", "data", "apps", "apps\_cache", "apps\_bin",
        "data\Documents", "data\Documents\WindowsPowerShell",
        "data\AppData\Roaming", "data\AppData\Local",
        "data\agy-home", "data\.npm-global", "data\.npm-cache",
        "data\.config", "data\.python-user",
        "data\vscode\user-data\User", "data\vscode\extensions"
    )
    foreach ($d in $dirs) {
        $fullPath = Join-Path $RootDir $d
        if (-not (Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        }
    }
}

function Get-WinPythonExe {
    param([string]$RootDir)
    $wpyMeta   = Get-ToolMeta -RootDir $RootDir -ToolKey "winpython"
    $wpyAppDir = Join-Path $RootDir "apps\$($wpyMeta.Dir)"
    if (-not (Test-Path $wpyAppDir)) { return $null }
    return Get-ChildItem -Path $wpyAppDir -Filter "python.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
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
        Write-Host "[CACHE] 命中本地快取 ($FileName)，跳過下載！" -ForegroundColor Green
        return $pkgFile
    }

    if ((Test-Path $tmpFile) -and ((Get-Item $tmpFile).Length -gt 0)) {
        $resumeMB = [Math]::Round((Get-Item $tmpFile).Length / 1MB, 2)
        Write-Host "[INFO] 偵測到未完成暫存檔 ($resumeMB MB)，接續下載 $DisplayName..." -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] 正在下載 $DisplayName..." -ForegroundColor Cyan
    }

    # 使用 Windows 內建 curl.exe 支援斷點續傳 (-C -) 與自動重導向 (-L)
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
        Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction Stop
    } catch {
        throw "無法清除目標資料夾 [$TargetDir]，請確認該工具的相關視窗或背景程式已完全關閉後再試。"
    }
}

function Get-7ZipPath {
    param([string]$RootDir)
    $exe = Join-Path $RootDir "apps\_bin\7zr.exe"
    if (-not (Test-Path $exe) -or ((Get-Item $exe).Length -eq 0)) {
        $tmpExe = "$exe.tmp"
        Write-Host "[INFO] 正在下載獨立版解壓工具 7zr.exe..." -ForegroundColor Cyan
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
    Write-Host "[SUCCESS] $DirName ($Version) 安裝完成！" -ForegroundColor Green
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

    Write-Host "[WARN] 尚未安裝 $($ToolMeta.Name)，正在啟動自動安裝..." -ForegroundColor Yellow
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
        Write-Host "[ERROR] 找不到安裝腳本或內建模組: $scriptName" -ForegroundColor Red
        return $false
    }
}

function Mount-PortableProfile {
    param(
        [string]$RootDir,
        [string[]]$ToolKeys
    )
    # 每次掛載前先還原至乾淨的基礎環境，避免多次切換選單導致變數殘留或 PATH 重複疊加
    Restore-BaseEnvironment

    $toolsCfg = Get-ToolsConfig -RootDir $RootDir
    $wsDir    = Join-Path $RootDir "workspace"
    $dataDir  = Join-Path $RootDir "data"

    # 統一設定 data 為沙盒家目錄
    Set-SandboxEnvironment -RootDir $RootDir

    $addedPaths = @()

    foreach ($key in $ToolKeys) {
        $meta = $toolsCfg[$key]
        if (-not (Confirm-ToolReady -RootDir $RootDir -ToolKey $key -ToolMeta $meta)) {
            throw "模組 [$key] 初始化失敗，中止啟動。"
        }

        $appDir = Join-Path $RootDir "apps\$($meta.Dir)"

        if ($key -eq "winpython") {
            $pyExe = Get-WinPythonExe -RootDir $RootDir
            if ($pyExe) {
                $pyDir = $pyExe.DirectoryName
                Repair-PythonPathsIfMoved -PyDir $pyDir
                $addedPaths += $pyDir
                $addedPaths += (Join-Path $pyDir "Scripts")

                # 預先掛載 PYTHONUSERBASE 的 Scripts 目錄，確保新安裝的 CLI 工具立即可用
                [Environment]::SetEnvironmentVariable("PYTHONUSERBASE", (Join-Path $dataDir ".python-user"), "Process")
                $userScripts = & $pyExe.FullName -c "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))" 2>$null
                if ($userScripts) {
                    $addedPaths += $userScripts.Trim()
                }
            }
        }

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

function Repair-PythonPathsIfMoved {
    param([string]$PyDir)
    $realPyDir = [System.IO.Path]::GetFullPath($PyDir)
    $pyExe = Join-Path $realPyDir "python.exe"
    if (-not (Test-Path $pyExe)) { return }

    $markerFile = Join-Path $realPyDir "last_path.txt"
    $lastPath = if (Test-Path $markerFile) { (Get-Content $markerFile -First 1).Trim() } else { "" }

    if ($lastPath -eq $realPyDir) { return }

    Write-Host "[INFO] 偵測到 Python 路徑變更 ($realPyDir)，正在自動修正啟動器路徑..." -ForegroundColor Yellow

    $fixCode = @"
import os, sys, glob
scripts_dir = os.path.join(sys.prefix, 'Scripts')
target_exe = sys.executable.encode('mbcs')
if os.path.exists(scripts_dir):
    for exe in glob.glob(os.path.join(scripts_dir, '*.exe')):
        try:
            with open(exe, 'rb') as f:
                data = f.read()
            idx = data.rfind(b'#!')
            if idx != -1 and b'python.exe' in data[idx:]:
                end = data.find(b'\r\n', idx)
                if end != -1:
                    new_shebang = b'#!' + target_exe + b'\r\n'
                    if data[idx:end+2] != new_shebang:
                        with open(exe, 'wb') as f:
                            f.write(data[:idx] + new_shebang + data[end+2:])
        except Exception:
            pass
"@
    & $pyExe -c $fixCode

    Set-Content -Path $markerFile -Value $realPyDir -Encoding UTF8
    Write-Host "[OK] Python 啟動器路徑已同步更新！" -ForegroundColor Green
}

function Test-PortableEnvironment {
    param(
        [string]$RootDir,
        [string[]]$ToolKeys
    )
    Write-Host "`n=================== 環境自我檢測報告 ===================" -ForegroundColor Cyan
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
            # sdkmanager 會在版本號前印出多行棄用警告，故取最後一行真正的版本資訊
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

    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  沙盒家目錄   : $env:USERPROFILE" -ForegroundColor Gray
    Write-Host "  NPM 全域目錄 : $env:NPM_CONFIG_PREFIX" -ForegroundColor Gray
    if ($env:GEMINI_CLI_HOME) {
        Write-Host "  Agy 設定目錄 : $env:GEMINI_CLI_HOME" -ForegroundColor Gray
    }
    Write-Host "========================================================`n" -ForegroundColor Cyan

    if ($hasError) {
        Write-Host "[WARN] 偵測到部分工具路徑異常，請檢查上方 [FAIL] 訊息。" -ForegroundColor Yellow
        Read-Host "按 Enter 鍵繼續啟動（或按 Ctrl+C 中止）"
    }
}

Export-ModuleMember -Function Restore-BaseEnvironment, Get-ToolsConfig, Get-ToolMeta, Set-SandboxEnvironment, Initialize-PortableDirs, Get-WinPythonExe, Initialize-VSCodeConfig, Get-CachedPackage, Clear-ToolDirectory, Get-7ZipPath, Complete-ToolInstall, Confirm-ToolReady, Mount-PortableProfile, Repair-PythonPathsIfMoved, Test-PortableEnvironment