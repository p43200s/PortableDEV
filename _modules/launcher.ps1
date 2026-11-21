$ErrorActionPreference = "Stop"
$RootDir = if ($env:PORTABLE_DEV_ROOT) { $env:PORTABLE_DEV_ROOT } else { Split-Path -Parent $PSScriptRoot }
$env:PORTABLE_DEV_ROOT = $RootDir

if (-not (Get-Module -Name "ui"))   { Import-Module (Join-Path $PSScriptRoot "ui.psm1") -Global }
if (-not (Get-Module -Name "core")) { Import-Module (Join-Path $PSScriptRoot "core.psm1") -Global }

Initialize-PortableDirs -RootDir $RootDir

function Sync-VSCodeSettings {
    param(
        [string]$RootDir,
        [string]$UserConfigDir,
        [string]$WorkspaceDir
    )
    $settingsFile  = Join-Path $UserConfigDir "settings.json"
    $uvPyRoot      = Join-Path $RootDir "data\.uv\python"
    $uvPyExe       = Get-UvPythonExe -RootDir $RootDir
    $pythonExePath = if ($uvPyExe) { [System.IO.Path]::GetFullPath($uvPyExe.FullName) } else { "python" }
    $javaHomePath  = [System.IO.Path]::GetFullPath($env:JAVA_HOME)

    $cfg = if (Test-Path $settingsFile) {
        try { Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [PSCustomObject]@{} }
    } else {
        [PSCustomObject]@{}
    }

    $cfg | Add-Member -MemberType NoteProperty -Name "java.jdt.ls.java.home" -Value $javaHomePath -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "java.configuration.runtimes" -Value @(
        [PSCustomObject]@{ name = "JavaSE-25"; path = $javaHomePath; default = $true }
    ) -Force

    if (Test-Path $uvPyRoot) {
        $cfg | Add-Member -MemberType NoteProperty -Name "python-envs.globalSearchPaths" -Value @([System.IO.Path]::GetFullPath($uvPyRoot)) -Force
    }
    $cfg | Add-Member -MemberType NoteProperty -Name "python-envs.defaultEnvManager" -Value "ms-python.python:system" -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "python.defaultInterpreterPath" -Value $pythonExePath -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "python.terminal.activateEnvironment" -Value $true -Force

    $cfg | Add-Member -MemberType NoteProperty -Name "terminal.integrated.inheritEnv" -Value $true -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "terminal.integrated.cwd" -Value $WorkspaceDir -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "powershell.enableProfileLoading" -Value $false -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "update.mode" -Value "none" -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "telemetry.telemetryLevel" -Value "off" -Force

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($settingsFile, ($cfg | ConvertTo-Json -Depth 5), $utf8NoBom)
}

function Start-PortableVSCode {
    param(
        [string]$RootDir,
        [string]$WorkspaceDir
    )
    $vscodeMeta = Get-ToolMeta -RootDir $RootDir -ToolKey "vscode"
    $codeExe    = Join-Path $RootDir "apps\$($vscodeMeta.Dir)\Code.exe"
    $vsPaths    = Initialize-VSCodeConfig -RootDir $RootDir

    Sync-VSCodeSettings -RootDir $RootDir -UserConfigDir $vsPaths.UserConfigDir -WorkspaceDir $WorkspaceDir

    # 偵測初次啟動或資料夾移動/更名：清除寫死舊路徑的快取並預熱重建 languagepacks.json
    $pathMarker    = Join-Path $vsPaths.DataDir "last_root.txt"
    $lastRoot      = if (Test-Path $pathMarker) { (Get-Content $pathMarker -First 1).Trim() } else { "" }
    $langPackCache = Join-Path $vsPaths.UserDataDir "languagepacks.json"

    if ($lastRoot -ne $RootDir) {
        Write-Status -Level "INFO" -Message "偵測到首次啟動或路徑變更，正在初始化 VS Code 語系快取..."
        Remove-Item (Join-Path $vsPaths.UserDataDir "clp") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $langPackCache -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $vsPaths.UserConfigDir "globalStorage\state.vscdb*") -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $vsPaths.UserConfigDir "workspaceStorage") -Recurse -Force -ErrorAction SilentlyContinue

        if (Test-Path $codeExe) {
            $proc = Start-Process -FilePath $codeExe -ArgumentList "--user-data-dir `"$($vsPaths.UserDataDir)`"", "--extensions-dir `"$($vsPaths.ExtensionsDir)`"", "--locale zh-tw" -PassThru -WindowStyle Minimized
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Milliseconds 500
                if (Test-Path $langPackCache) {
                    Start-Sleep -Seconds 1
                    break
                }
            }
            if ($proc -and -not $proc.HasExited) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Get-Process -Name "Code" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $codeExe } | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }

        Set-Content -Path $pathMarker -Value $RootDir -Encoding UTF8
    }

    Write-Status -Level "INFO" -Message "2 秒後自動啟動 VS Code..."
    Start-Sleep -Seconds 2

    $argStr = "/c start `"`" `"$codeExe`" `"$WorkspaceDir`" --user-data-dir `"$($vsPaths.UserDataDir)`" --extensions-dir `"$($vsPaths.ExtensionsDir)`" --locale zh-tw"
    Start-Process -FilePath "cmd.exe" -ArgumentList $argStr -WorkingDirectory $WorkspaceDir -WindowStyle Hidden
}

$isSingleFileMode = [bool]$global:PortableCoreSourceB64

while ($true) {
    $appCfg = Get-AppConfig -RootDir $RootDir
    $appVer = Get-AppVersion -RootDir $RootDir
    $Host.UI.RawUI.WindowTitle = "$($appCfg.AppName) v$appVer (Portable Dev)"

    Show-Header -Subtitle "主選單" -RootDir $RootDir
    Write-Host "  [1] VS Code       (JDK 25 + uv Python + Node + Git + Agy + VSCode)"
    Write-Host "  [2] CMD 控制台    (JDK 25 + uv Python + Node + Git + Agy)"
    Write-Host "  [3] PowerShell    (JDK 25 + uv Python + Node + Git + Agy)"
    Write-Host "  [4] Android 除錯  (JDK 17 + uv Python + Android SDK)"
    Write-Host ""
    Write-Host "  [U] 工具更新中心" -ForegroundColor Yellow

    if (-not $isSingleFileMode) {
        Write-Host ""
        Write-Host "  [B] 單檔封裝打包 (PortableDEV_$appVer.bat)" -ForegroundColor DarkCyan
        Write-Host "  [O] 匯出專案原始碼快照 (PortableDEV_$appVer.txt)" -ForegroundColor DarkCyan
        Show-Footer -HintText " [0] 離開系統"
        $choice = (Read-Host "請選擇啟動項目 [0-4 / U / B / O]").Trim()
    } else {
        Show-Footer -HintText " [0] 離開系統"
        $choice = (Read-Host "請選擇啟動項目 [0-4 / U]").Trim()
    }

    if ($choice -eq "0") { exit }
    if ($choice -ieq "U") {
        & (Join-Path $PSScriptRoot "updater.ps1")
        continue
    }
    if ($choice -ieq "B" -and -not $isSingleFileMode) {
        try {
            & (Join-Path $PSScriptRoot "dev\build.ps1") -RootDir $RootDir
        } catch {
            Write-Status -Level "ERR" -Message $_.Exception.Message
        }
        Wait-UserPause
        continue
    }
    if ($choice -ieq "O" -and -not $isSingleFileMode) {
        try {
            & (Join-Path $PSScriptRoot "dev\code_dump.ps1") -RootDir $RootDir
        } catch {
            Write-Status -Level "ERR" -Message $_.Exception.Message
        }
        Wait-UserPause
        continue
    }

    try {
        $profileMap = @{
            "1" = @{ Title = "Portable VS Code [JDK 25]";      Tools = @("git", "jdk25", "uv", "nodejs", "agy", "vscode") }
            "2" = @{ Title = "Portable Dev CMD [JDK 25]";      Tools = @("git", "jdk25", "uv", "nodejs", "agy") }
            "3" = @{ Title = "Portable Dev PS [JDK 25]";       Tools = @("git", "jdk25", "uv", "nodejs", "agy") }
            "4" = @{ Title = "Portable Android Debug [JDK 17]";     Tools = @("git", "jdk17", "uv", "nodejs", "android") }
        }

        if (-not $profileMap.ContainsKey($choice)) { continue }

        $selected = $profileMap[$choice]
        Write-Host ""
        Write-Status -Level "INFO" -Message "正在掛載 $($selected.Title)..."
        Mount-PortableProfile -RootDir $RootDir -ToolKeys $selected.Tools
        Test-PortableEnvironment -RootDir $RootDir -ToolKeys $selected.Tools

        $wsDir = Join-Path $RootDir "workspace"
        Set-Location $wsDir

        switch ($choice) {
            "1" {
                Start-PortableVSCode -RootDir $RootDir -WorkspaceDir $wsDir
                exit
            }
            "2" {
                Write-Status -Level "INFO" -Message "已進入 CMD 控制台（輸入 exit 可返回主選單）`n"
                cmd.exe /k "title $($selected.Title)"
            }
            { $_ -in "3", "4" } {
                Write-Status -Level "OK" -Message "已進入 PowerShell 環境（輸入 exit 可返回主選單）`n"
                powershell.exe -NoLogo -NoProfile -NoExit -Command "`$Host.UI.RawUI.WindowTitle = '$($selected.Title)'"
            }
        }
    } catch {
        Write-Host ""
        Write-Status -Level "ERR" -Message $_.Exception.Message
        Wait-UserPause
    }
}