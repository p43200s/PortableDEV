$global:PortableUIWidth = 84

function Get-LineDivider {
    param([string]$Char = "─")
    return ($Char * $global:PortableUIWidth)
}

function Get-VisualWidth {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $visWidth = 0
    foreach ($char in $Text.ToCharArray()) {
        $code = [int]$char
        # 排除 Box Drawing (0x2500-0x257F) 與單寬符號 (如 › 0x203A)；CJK 與全形符號視為 2 格
        if (($code -ge 0x1100 -and $code -le 0xFFEF -and -not ($code -ge 0x2500 -and $code -le 0x257F)) -or ($code -ge 0x2E80 -and $code -le 0x9FFF)) {
            $visWidth += 2
        } else {
            $visWidth += 1
        }
    }
    return $visWidth
}

function Format-PadRight {
    param(
        [string]$Text,
        [int]$Width,
        [switch]$Truncate
    )
    if ([string]::IsNullOrEmpty($Text)) { return (" " * $Width) }

    $currentText = $Text
    if ($Truncate -and (Get-VisualWidth -Text $currentText) -gt $Width) {
        $acc = ""
        $accW = 0
        $limit = [Math]::Max(0, $Width - 2)
        foreach ($char in $currentText.ToCharArray()) {
            $cw = Get-VisualWidth -Text ([string]$char)
            if (($accW + $cw) -gt $limit) { break }
            $acc += $char
            $accW += $cw
        }
        $currentText = $acc + ".."
    }

    $visWidth = Get-VisualWidth -Text $currentText
    $pad = [Math]::Max(0, $Width - $visWidth)
    return $currentText + (" " * $pad)
}

function Write-Status {
    param(
        [ValidateSet("INFO", "OK", "WARN", "ERR", "STEP", "CACHE", "SKIP", "TIP")]
        [string]$Level = "INFO",
        [string]$Message
    )
    $colorMap = @{
        "INFO"  = "Cyan"
        "OK"    = "Green"
        "WARN"  = "Yellow"
        "ERR"   = "Red"
        "STEP"  = "Magenta"
        "CACHE" = "Green"
        "SKIP"  = "Gray"
        "TIP"   = "Cyan"
    }
    Write-Host "[$Level] " -NoNewline -ForegroundColor $colorMap[$Level]
    Write-Host $Message
}

function Show-Header {
    param(
        [string]$Subtitle = "",
        [string]$RootDir = $env:PORTABLE_DEV_ROOT
    )
    Clear-Host
    $cfg = Get-AppConfig -RootDir $RootDir
    $ver = Get-AppVersion -RootDir $RootDir
    $div = Get-LineDivider

    Write-Host $div -ForegroundColor DarkCyan
    $baseTitle = " $($cfg.AppName) v$ver"
    $title = if ($Subtitle) { "$baseTitle  ›  $Subtitle" } else { $baseTitle }
    Write-Host $title -ForegroundColor Cyan
    Write-Host $div -ForegroundColor DarkCyan
}

function Show-Footer {
    param([string]$HintText = " [ 0] 返回主選單")
    $div = Get-LineDivider
    if ($HintText) {
        Write-Host $div -ForegroundColor DarkCyan
        Write-Host $HintText
    }
    Write-Host $div -ForegroundColor DarkCyan
}

function Wait-UserPause {
    param([string]$Message = "<< 按 Enter 繼續 >>")
    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) { break }
    }
}

Export-ModuleMember -Function Get-LineDivider, Get-VisualWidth, Format-PadRight, Write-Status, Show-Header, Show-Footer, Wait-UserPause