$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "core.psm1") -Force
Initialize-PortableDirs -RootDir $RootDir

function Sync-VSCodeSettings {
    param(
        [string]$RootDir,
        [string]$UserConfigDir,
        [string]$WorkspaceDir
    )
    $settingsFile    = Join-Path $UserConfigDir "settings.json"
    $wpyExe          = Get-WinPythonExe -RootDir $RootDir
    $pythonExePath   = if ($wpyExe) { [System.IO.Path]::GetFullPath($wpyExe.FullName) } else { "python" }
    $pythonParentDir = if ($wpyExe) { [System.IO.Path]::GetFullPath($wpyExe.Directory.Parent.FullName) } else { $null }
    $javaHomePath    = [System.IO.Path]::GetFullPath($env:JAVA_HOME)

    $cfg = if (Test-Path $settingsFile) {
        try { Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [PSCustomObject]@{} }
    } else {
        [PSCustomObject]@{}
    }

    $cfg | Add-Member -MemberType NoteProperty -Name "java.jdt.ls.java.home" -Value $javaHomePath -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "java.configuration.runtimes" -Value @(
        [PSCustomObject]@{ name = "JavaSE-25"; path = $javaHomePath; default = $true }
    ) -Force

    if ($pythonParentDir) {
        $cfg | Add-Member -MemberType NoteProperty -Name "python-envs.globalSearchPaths" -Value @($pythonParentDir) -Force
    }
    $cfg | Add-Member -MemberType NoteProperty -Name "python-envs.defaultEnvManager" -Value "ms-python.python:system" -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "python.defaultInterpreterPath" -Value $pythonExePath -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "python.terminal.activateEnvironment" -Value $false -Force

	$cfg | Add-Member -MemberType NoteProperty -Name "terminal.integrated.inheritEnv" -Value $true -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "terminal.integrated.cwd" -Value $WorkspaceDir -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "powershell.enableProfileLoading" -Value $false -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "update.mode" -Value "none" -Force
    $cfg | Add-Member -MemberType NoteProperty -Name "telemetry.telemetryLevel" -Value "off" -Force

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($settingsFile, ($cfg | ConvertTo-Json -Depth 5), $utf8NoBom)
}

while ($true) {
    $Host.UI.RawUI.WindowTitle = "可攜式開發環境啟動器 (Portable Dev)"
    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "            可攜式開發環境啟動器 (Portable Dev)" -ForegroundColor White
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  [1] VS Code       (JDK 25 + WinPython slim + Node + Git + VSCode + Agy)"
    Write-Host "  [2] CMD 控制台    (JDK 25 + WinPython slim + Node + Git + Agy)"
    Write-Host "  [3] PowerShell    (JDK 25 + WinPython slim + Node + Git + Agy)"
    Write-Host "  [4] Android 除錯  (JDK 17 + WinPython slim + Android SDK)"
    Write-Host "  [U] 版本檢查與更新中心" -ForegroundColor Yellow
    Write-Host "  [0] 離開"
    Write-Host "========================================================" -ForegroundColor Cyan
    $choice = (Read-Host "請選擇啟動項目 [0-4 / U]").Trim()

    if ($choice -eq "0") { exit }
    if ($choice -ieq "U") {
        & (Join-Path $PSScriptRoot "updater.ps1")
        continue
    }

    try {
        $profileMap = @{
            "1" = @{ Title = "VS Code 開發環境"; Tools = @("git", "jdk25", "winpython", "nodejs", "vscode", "agy") }
            "2" = @{ Title = "主要開發環境 (CMD)"; Tools = @("git", "jdk25", "winpython", "nodejs", "agy") }
            "3" = @{ Title = "主要開發環境 (PowerShell)"; Tools = @("git", "jdk25", "winpython", "nodejs", "agy") }
            "4" = @{ Title = "Android 除錯環境 (JDK 17)"; Tools = @("git", "jdk17", "winpython", "nodejs", "android") }
        }

        if (-not $profileMap.ContainsKey($choice)) { continue }

        $selected = $profileMap[$choice]
        Write-Host "`n[INFO] 正在掛載 $($selected.Title)..." -ForegroundColor Cyan
        Mount-PortableProfile -RootDir $RootDir -ToolKeys $selected.Tools
        Test-PortableEnvironment -RootDir $RootDir -ToolKeys $selected.Tools

        $wsDir = Join-Path $RootDir "workspace"
        Set-Location $wsDir

        switch ($choice) {
            "1" {
                $vscodeMeta = Get-ToolMeta -RootDir $RootDir -ToolKey "vscode"
                $codeExe    = Join-Path $RootDir "apps\$($vscodeMeta.Dir)\Code.exe"
                $vsPaths    = Initialize-VSCodeConfig -RootDir $RootDir

                Sync-VSCodeSettings -RootDir $RootDir -UserConfigDir $vsPaths.UserConfigDir -WorkspaceDir $wsDir

                # 偵測資料夾是否被移動或更名，若有變動則清除寫死舊路徑的快取
                $pathMarker = Join-Path $vsPaths.DataDir "last_root.txt"
                $lastRoot   = if (Test-Path $pathMarker) { (Get-Content $pathMarker -First 1).Trim() } else { "" }
                if ($lastRoot -ne $RootDir) {
                    Remove-Item (Join-Path $vsPaths.UserDataDir "clp") -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item (Join-Path $vsPaths.UserConfigDir "globalStorage\state.vscdb*") -Force -ErrorAction SilentlyContinue
                    Remove-Item (Join-Path $vsPaths.UserConfigDir "workspaceStorage") -Recurse -Force -ErrorAction SilentlyContinue
                    Set-Content -Path $pathMarker -Value $RootDir -Encoding UTF8
                }

                Write-Host "[INFO] 2 秒後自動啟動 VS Code..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2

                $argStr = "/c start `"`" `"$codeExe`" `"$wsDir`" --user-data-dir `"$($vsPaths.UserDataDir)`" --extensions-dir `"$($vsPaths.ExtensionsDir)`" --locale zh-tw"
                Start-Process -FilePath "cmd.exe" -ArgumentList $argStr -WorkingDirectory $wsDir -WindowStyle Hidden
                exit
            }
            "2" {
                Write-Host "[INFO] 已進入 CMD 控制台（輸入 exit 可返回主選單）`n" -ForegroundColor Yellow
                cmd.exe /k "title Portable Dev [JDK 25 / WinPython]"
            }
            "3" {
                Write-Host "[INFO] 已進入 PowerShell 環境（輸入 exit 可返回主選單）`n" -ForegroundColor Green
                powershell.exe -NoLogo -NoProfile -NoExit -Command "`$Host.UI.RawUI.WindowTitle = 'Portable Dev PS [JDK 25 / WinPython]'"
            }
            "4" {
                Write-Host "[INFO] 已進入 Android 除錯環境（輸入 exit 可返回主選單）`n" -ForegroundColor Green
                powershell.exe -NoLogo -NoProfile -NoExit -Command "`$Host.UI.RawUI.WindowTitle = 'Portable Android Debug [JDK 17 / WinPython]'"
            }
        }
    } catch {
        Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Read-Host "按 Enter 鍵返回選單"
    }
}