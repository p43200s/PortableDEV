$ErrorActionPreference = "Stop"
$RootDir = if ($env:PORTABLE_DEV_ROOT) { $env:PORTABLE_DEV_ROOT } else { Split-Path -Parent $PSScriptRoot }
if (-not (Get-Module -Name "PortableCore")) {
    Import-Module (Join-Path $PSScriptRoot "core.psm1") -Force
}
Initialize-PortableDirs -RootDir $RootDir

$toolsCfg    = Get-ToolsConfig -RootDir $RootDir
$orderedKeys = @($toolsCfg.Keys | Sort-Object { if ($toolsCfg[$_].Order) { $toolsCfg[$_].Order } else { 999 } })

function Format-PadRight {
    param([string]$Text, [int]$Width)
    $visWidth = 0
    foreach ($char in $Text.ToCharArray()) {
        if ([int]$char -gt 255) { $visWidth += 2 } else { $visWidth += 1 }
    }
    $pad = [Math]::Max(0, $Width - $visWidth)
    return $Text + (" " * $pad)
}

function Invoke-PortableCleanup {
    Write-Host "`n================ 清理暫存與舊版殘留資料夾 ================" -ForegroundColor Cyan

    $cacheDir = Join-Path $RootDir "apps\_cache"
    $cacheSizeMB = 0
    if (Test-Path $cacheDir) {
        $cacheItems = Get-ChildItem -Path $cacheDir -Recurse -File -ErrorAction SilentlyContinue
        if ($cacheItems) {
            $cacheSizeMB = [Math]::Round(($cacheItems | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        }
    }
    Write-Host "  [快取目錄] apps\_cache 目前佔用約 $cacheSizeMB MB" -ForegroundColor Gray

    $appsDir = Join-Path $RootDir "apps"
    $validDirs = @("_cache", "_bin") + ($orderedKeys | ForEach-Object { $toolsCfg[$_].Dir })
    $obsoleteDirs = @(Get-ChildItem -Path $appsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $validDirs })

    if ($obsoleteDirs.Count -gt 0) {
        Write-Host "  [發現舊版] 以下資料夾已不在目前架構清單中，可安全移除：" -ForegroundColor Yellow
        foreach ($od in $obsoleteDirs) {
            Write-Host "    - $($od.Name)" -ForegroundColor Yellow
        }
    }

    if ($cacheSizeMB -eq 0 -and $obsoleteDirs.Count -eq 0) {
        Write-Host "`n[INFO] 環境非常乾淨，無需清理！" -ForegroundColor Green
        return
    }

    $confirm = (Read-Host "`n確定要清空 _cache 並移除上述舊版資料夾嗎？(Y/N)").Trim()
    if ($confirm -ine "Y") {
        Write-Host "[INFO] 已取消清理動作。" -ForegroundColor Yellow
        return
    }

    if (Test-Path $cacheDir) {
        Get-ChildItem -Path $cacheDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] 已清空 apps\_cache 暫存檔。" -ForegroundColor Green
    }

    foreach ($od in $obsoleteDirs) {
        Clear-ToolDirectory -TargetDir $od.FullName
        Write-Host "  [OK] 已移除舊版資料夾: $($od.Name)" -ForegroundColor Green
    }

    Write-Host "========================================================" -ForegroundColor Cyan
}

while ($true) {
    Clear-Host
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host "                   可攜式開發環境 - 版本檢查與更新中心" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host " 正在平行查詢線上最新版本，請稍候..." -ForegroundColor Yellow

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    try {
        $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
    } catch {
        # 若受群組原則限制無法覆寫，則沿用父進程既有的 Bypass 權限
    }

    $pool = [RunspaceFactory]::CreateRunspacePool(1, 8, $iss, $Host)
    $pool.Open()
    $jobs = @()

    $isSingleFileMode = [bool]$global:PortableCoreSourceB64

    foreach ($key in $orderedKeys) {
        $meta       = $toolsCfg[$key]
        $scriptName = if ($meta.Installer) { $meta.Installer } else { $key }

        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool

        if ($isSingleFileMode) {
            $funcCmd  = Get-Command "Invoke-Installer_$scriptName" -ErrorAction SilentlyContinue
            $funcBody = if ($funcCmd) { $funcCmd.Definition } else { "" }

            [void]$ps.AddScript({
                param($CoreB64, $ToolsCfg, $FuncBody, $Root, $Key)
                $ErrorActionPreference = "Stop"
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                if (-not $FuncBody) { return "找不到腳本" }
                try {
                    $global:PortableToolsConfig = $ToolsCfg
                    $coreSrc = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($CoreB64))
                    New-Module -Name "PortableCore" -ScriptBlock ([ScriptBlock]::Create($coreSrc)) | Import-Module -Force
                    $sb = [ScriptBlock]::Create($FuncBody)
                    $info = & $sb -RootDir $Root -ToolKey $Key -Mode "query"
                    if ($info -and $info.Version) { return $info.Version }
                    return "查詢失敗"
                } catch {
                    $msg = $_.Exception.Message
                    if ($msg -match "403|rate limit") { return "API達上限" }
                    return "錯誤: $msg"
                }
            }).AddArgument($global:PortableCoreSourceB64).AddArgument($toolsCfg).AddArgument($funcBody).AddArgument($RootDir).AddArgument($key)
        } else {
            $installer = Join-Path $PSScriptRoot "installers\$scriptName.ps1"
            [void]$ps.AddScript({
                param($InstallerPath, $Root, $Key)
                $ErrorActionPreference = "Stop"
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                if (-not (Test-Path $InstallerPath)) { return "找不到腳本" }
                try {
                    $info = & $InstallerPath -RootDir $Root -ToolKey $Key -Mode "query"
                    if ($info -and $info.Version) { return $info.Version }
                    return "查詢失敗"
                } catch {
                    $msg = $_.Exception.Message
                    if ($msg -match "403|rate limit") { return "API達上限" }
                    return "錯誤: $msg"
                }
            }).AddArgument($installer).AddArgument($RootDir).AddArgument($key)
        }

        $jobs += [PSCustomObject]@{ Key = $key; PS = $ps; Handle = $ps.BeginInvoke() }
    }

    $onlineResults = @{}
    foreach ($j in $jobs) {
        $onlineResults[$j.Key] = $j.PS.EndInvoke($j.Handle) | Select-Object -First 1
        $j.PS.Dispose()
    }
    $pool.Close()
    $pool.Dispose()

    $records = @()
    $idx = 1
    foreach ($key in $orderedKeys) {
        $meta      = $toolsCfg[$key]
        $verFile   = Join-Path $RootDir "apps\$($meta.Dir)\version.txt"
        $localVer  = if (Test-Path $verFile) { (Get-Content $verFile -First 1).Trim() } else { "未安裝" }
        $onlineVer = [string]$onlineResults[$key]

        $status     = "已是最新"
        $needUpdate = $false
        $isError    = ($onlineVer -in @("查詢失敗", "API達上限", "找不到腳本")) -or ($onlineVer -like "錯誤:*")

        if ($localVer -eq "未安裝") {
            $status     = "未安裝"
            $needUpdate = $true
        } elseif (-not $isError -and $localVer -ne $onlineVer) {
            $status     = "可更新!"
            $needUpdate = $true
        } elseif ($isError) {
            $status = $onlineVer
        }

        $records += [PSCustomObject]@{
            ID         = $idx
            Key        = $key
            Name       = $meta.Name
            LocalVer   = $localVer
            OnlineVer  = if ($onlineVer -like "錯誤:*") { "查詢異常" } else { $onlineVer }
            Status     = $status
            NeedUpdate = $needUpdate
        }
        $idx++
    }

    Clear-Host
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host "                   可攜式開發環境 - 版本檢查與更新中心" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor Cyan

    $hId     = Format-PadRight "ID" 4
    $hName   = Format-PadRight "工具名稱" 23
    $hLocal  = Format-PadRight "本地版本" 16
    $hOnline = Format-PadRight "線上最新版本" 16
    Write-Host " $hId | $hName | $hLocal | $hOnline | 狀態" -ForegroundColor White
    Write-Host "----------------------------------------------------------------------------"

    foreach ($r in $records) {
        $isErrRow = ($r.Status -in @("查詢失敗", "API達上限", "找不到腳本")) -or ($r.Status -like "錯誤:*")
        $color = if ($r.Status -eq "可更新!") { "Green" } elseif ($r.Status -eq "未安裝") { "Yellow" } elseif ($isErrRow) { "Red" } else { "Gray" }
        $cId     = Format-PadRight "[$($r.ID)]" 4
        $cName   = Format-PadRight $r.Name 23
        $cLocal  = Format-PadRight $r.LocalVer 16
        $cOnline = Format-PadRight $r.OnlineVer 16
        Write-Host " $cId | $cName | $cLocal | $cOnline | $($r.Status)" -ForegroundColor $color
    }

    $maxId = $records.Count
    Write-Host "----------------------------------------------------------------------------"
    Write-Host " [1-$maxId] 安裝或重裝   [A] 全部更新   [C] 清理快取/舊版   [R] 重整   [0] 返回主選單"
    Write-Host "============================================================================" -ForegroundColor Cyan

    $sel = (Read-Host "請輸入指令").Trim()
    if ($sel -eq "0") { return }
    if ($sel -ieq "R") { continue }
    if ($sel -ieq "O") {
        $dumpScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot "dev\code_dump.ps1" } else { "" }
        if ($dumpScript -and (Test-Path $dumpScript)) {
            & $dumpScript -RootDir $RootDir
        } else {
            Write-Host "`n[WARN] 目前為單一封裝模式，不支援匯出原始碼。" -ForegroundColor Yellow
        }
        Read-Host "`n按 Enter 鍵返回列表"
        continue
    }
    if ($sel -ieq "B") {
        $buildScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot "dev\build.ps1" } else { "" }
        if ($buildScript -and (Test-Path $buildScript)) {
            & $buildScript -RootDir $RootDir
        } else {
            Write-Host "`n[WARN] 目前已是單一封裝執行檔，無需再次打包。" -ForegroundColor Yellow
        }
        Read-Host "`n按 Enter 鍵返回列表"
        continue
    }
    if ($sel -ieq "C") {
        Invoke-PortableCleanup
        Read-Host "`n按 Enter 鍵返回列表"
        continue
    }

    $targets = @()
    if ($sel -ieq "A") {
        $targets = @($records | Where-Object { $_.NeedUpdate })
    } elseif ($sel -match "^\d+$" -and [int]$sel -ge 1 -and [int]$sel -le $maxId) {
        $targets = @($records | Where-Object { $_.ID -eq [int]$sel })
    }

    if ($targets.Count -gt 0) {
        foreach ($t in $targets) {
            Write-Host "`n>>> 正在處理: $($t.Name) <<<" -ForegroundColor Cyan
            try {
                $meta       = $toolsCfg[$t.Key]
                $scriptName = if ($meta.Installer) { $meta.Installer } else { $t.Key }
                $memFunc    = "Invoke-Installer_$scriptName"
                if (Get-Command $memFunc -ErrorAction SilentlyContinue) {
                    & $memFunc -RootDir $RootDir -ToolKey $t.Key -Mode "install"
                } else {
                    $installer = Join-Path $PSScriptRoot "installers\$scriptName.ps1"
                    & $installer -RootDir $RootDir -ToolKey $t.Key -Mode "install"
                }
            } catch {
                Write-Host "[ERROR] $($t.Name) 處理失敗: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host "`n[INFO] 作業結束！" -ForegroundColor Green
        Read-Host "按 Enter 鍵返回列表"
    }
}