$ErrorActionPreference = "Stop"
$RootDir = if ($env:PORTABLE_DEV_ROOT) { $env:PORTABLE_DEV_ROOT } else { Split-Path -Parent $PSScriptRoot }

if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $PSScriptRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $PSScriptRoot "core.psm1") -Global }

Initialize-PortableDirs -RootDir $RootDir

$toolsCfg    = Get-ToolsConfig -RootDir $RootDir
$orderedKeys = @($toolsCfg.Keys | Sort-Object { if ($toolsCfg[$_].Order) { $toolsCfg[$_].Order } else { 999 } })

function Invoke-PortableCleanup {
    $div = Get-LineDivider
    Write-Host ""
    Write-Host $div -ForegroundColor DarkCyan
    Write-Host " 清理暫存與舊版殘留資料夾（自動保留 7zr.exe）" -ForegroundColor Cyan
    Write-Host $div -ForegroundColor DarkCyan

    $cacheDir = Join-Path $RootDir "apps\_cache"
    $cacheSizeMB = 0
    $cleanableCacheItems = @()
    if (Test-Path $cacheDir) {
        $cleanableCacheItems = @(Get-ChildItem -Path $cacheDir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "7zr.exe" })
        $cacheFiles = @($cleanableCacheItems | Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue)
        $directFiles = @($cleanableCacheItems | Where-Object { -not $_.PSIsContainer })
        $allFiles = $cacheFiles + $directFiles
        if ($allFiles.Count -gt 0) {
            $cacheSizeMB = [Math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        }
    }
    Write-Status -Level "INFO" -Message "快取目錄 (apps\_cache) 可清理空間約 $cacheSizeMB MB（7zr.exe 將保留）"

    $appsDir = Join-Path $RootDir "apps"
    $validDirs = @("_cache") + ($orderedKeys | ForEach-Object { $toolsCfg[$_].Dir })
    $obsoleteDirs = @()
    if (Test-Path $appsDir) {
        $obsoleteDirs = @(Get-ChildItem -Path $appsDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $validDirs })
    }

    if ($obsoleteDirs.Count -gt 0) {
        Write-Status -Level "WARN" -Message "發現已不在目前架構清單中的舊版資料夾（可安全移除）："
        foreach ($od in $obsoleteDirs) {
            Write-Status -Level "WARN" -Message "  - $($od.Name)"
        }
    }

    if ($cacheSizeMB -eq 0 -and $obsoleteDirs.Count -eq 0) {
        Write-Host ""
        Write-Status -Level "OK" -Message "環境非常乾淨，無需清理！"
        return
    }

    Write-Host ""
    $confirm = (Read-Host "確定要清理快取並移除上述舊版資料夾嗎？(Y/N)").Trim()
    if ($confirm -ine "Y") {
        Write-Status -Level "WARN" -Message "已取消清理動作。"
        return
    }

    if ($cleanableCacheItems.Count -gt 0) {
        $cleanableCacheItems | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Status -Level "OK" -Message "已清理 apps\_cache 暫存檔（已保留 7zr.exe）。"
    }

    foreach ($od in $obsoleteDirs) {
        Clear-ToolDirectory -TargetDir $od.FullName
        Write-Status -Level "OK" -Message "已移除舊版資料夾: $($od.Name)"
    }

    Write-Host $div -ForegroundColor DarkCyan
}

while ($true) {
    Show-Header -Subtitle "工具更新中心" -RootDir $RootDir
    Write-Status -Level "INFO" -Message "正在查詢線上最新版本，請稍候..."

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    try {
        $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
    } catch {}

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
                param($UiB64, $CoreB64, $AppCfg, $FuncBody, $Root, $Key)
                $ErrorActionPreference = "Stop"
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
                if (-not $FuncBody) { return "找不到腳本" }
                try {
                    $global:PortableAppConfig = $AppCfg
                    $uiSrc = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($UiB64))
                    New-Module -Name "PortableUI" -ScriptBlock ([ScriptBlock]::Create($uiSrc)) | Import-Module -Force
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
            }).AddArgument($global:PortableUISourceB64).AddArgument($global:PortableCoreSourceB64).AddArgument($global:PortableAppConfig).AddArgument($funcBody).AddArgument($RootDir).AddArgument($key)
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

    Show-Header -Subtitle "工具更新中心" -RootDir $RootDir
    $div = Get-LineDivider

    $hId     = Format-PadRight "ID" 5
    $hName   = Format-PadRight "工具名稱" 25
    $hLocal  = Format-PadRight "本地版本" 16
    $hOnline = Format-PadRight "線上最新版本" 16
    Write-Host " $hId │ $hName │ $hLocal │ $hOnline │ 狀態" -ForegroundColor White
    Write-Host $div -ForegroundColor DarkGray

    foreach ($r in $records) {
        $isErrRow = ($r.Status -in @("查詢失敗", "API達上限", "找不到腳本")) -or ($r.Status -like "錯誤:*")
        $color = if ($r.Status -eq "可更新!") { "Green" } elseif ($r.Status -eq "未安裝") { "Yellow" } elseif ($isErrRow) { "Red" } else { "Gray" }
        $cId     = Format-PadRight ("[{0,2}]" -f $r.ID) 5
        $cName   = Format-PadRight $r.Name 25 -Truncate
        $cLocal  = Format-PadRight $r.LocalVer 16 -Truncate
        $cOnline = Format-PadRight $r.OnlineVer 16 -Truncate
        Write-Host " $cId │ $cName │ $cLocal │ $cOnline │ $($r.Status)" -ForegroundColor $color
    }

    $maxId = $records.Count
    Show-Footer -HintText " [1-$maxId] 安裝或重裝   [A] 全部更新   [C] 清理快取/舊版   [R] 重整   [0] 返回主選單"

    $sel = (Read-Host "請輸入指令").Trim()
    if ($sel -eq "0") { return }
    if ($sel -ieq "R") { continue }
    if ($sel -ieq "C") {
        Invoke-PortableCleanup
        Wait-UserPause
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
            Write-Host ""
            Write-Status -Level "STEP" -Message "正在處理: $($t.Name)"
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
                Write-Status -Level "ERR" -Message "$($t.Name) 處理失敗: $($_.Exception.Message)"
            }
        }
        Write-Host ""
        Write-Status -Level "OK" -Message "作業結束！"
        Wait-UserPause
    }
}