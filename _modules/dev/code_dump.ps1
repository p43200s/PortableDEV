param([string]$RootDir)
$ErrorActionPreference = "Stop"

$appCfg  = Get-AppConfig -RootDir $RootDir
$verTag  = $appCfg.AppVer

$outputFile = "PortableDEV_${verTag}.txt"
$outputPath = Join-Path $RootDir $outputFile

$tee  = "$([char]0x251C)$([char]0x2500)$([char]0x2500) "
$last = "$([char]0x2514)$([char]0x2500)$([char]0x2500) "
$pipe = "$([char]0x2502)   "

$excludeDirs = @("apps", "data", "workspace", ".git")
$includeExts = @(".bat", ".ps1", ".psm1", ".psd1", ".md")

function Get-ProjectFiles {
    param([string]$Dir)
    foreach ($item in (Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
        if ($item.PSIsContainer) {
            if ($item.Name -notin $excludeDirs) {
                Get-ProjectFiles -Dir $item.FullName
            }
        } else {
            if (($item.Extension -in $includeExts) -and ($item.Name -notlike "PortableDEV_*")) {
                $item
            }
        }
    }
}

$targetFiles = @(Get-ProjectFiles -Dir $RootDir | Sort-Object FullName)

function Get-TreeLines {
    param([string]$CurrentPath, [string]$Prefix = "")

    $items = @(Get-ChildItem -LiteralPath $CurrentPath -Force | Where-Object {
        $currItem = $_
        if ($currItem.PSIsContainer) {
            if ($currItem.Name -in $excludeDirs) { return $false }
            $dirPrefix = $currItem.FullName + "\"
            return ($targetFiles | Where-Object { $_.FullName.StartsWith($dirPrefix) }).Count -gt 0
        } else {
            return $targetFiles.FullName -contains $currItem.FullName
        }
    } | Sort-Object { -not $_.PSIsContainer }, Name)

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item      = $items[$i]
        $isLast    = ($i -eq ($items.Count - 1))
        $connector = if ($isLast) { $last } else { $tee }

        "$Prefix$connector$($item.Name)"

        if ($item.PSIsContainer) {
            $nextPrefix = $Prefix + $(if ($isLast) { "    " } else { $pipe })
            Get-TreeLines -CurrentPath $item.FullName -Prefix $nextPrefix
        }
    }
}

$outputLines = @(
    "=== PROJECT DIRECTORY TREE ==="
    (Split-Path $RootDir -Leaf)
    Get-TreeLines -CurrentPath $RootDir
    ""
    "=== SOURCE CODE DUMP ==="
    foreach ($file in $targetFiles) {
        $relPath = $file.FullName.Substring($RootDir.Length + 1)
        "=== $relPath ==="
        Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        ""
    }
)

[System.IO.File]::WriteAllLines($outputPath, $outputLines, (New-Object System.Text.UTF8Encoding $false))
Write-Host ""
Write-Status -Level "OK" -Message "已將目錄樹與程式碼匯出至 $outputFile"