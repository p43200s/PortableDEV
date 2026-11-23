# 更新日誌

## [0.3.0] - 2026-11-23

### 新增

- **無版號 python 全域執行支援**：在 `uv.ps1` 安裝受管 Python 時啟用 `--default --preview-features python-install-default`，自動建立無版號 `python.exe` 與 `python3.exe` 跳板執行檔，進入環境後可直接執行 python 指令。
- **ADB 金鑰可攜式目錄聯接**：啟動 `[4] Android 除錯` 時自動將宿主機 `%USERPROFILE%\.android` 透過 `mklink /J` 映射至沙盒 `data\.android`，包括非 NTFS 隨身碟實體檔案同步容錯，確保裝置授權憑證隨身攜帶。
- **沙盒預設系統目錄初始化**：在 `core.psm1` 的 `Initialize-PortableDirs` 新增 `data\Desktop`、`data\Downloads` 與 `data\.local\bin` 目錄建立。

### 調整

- **遷移至新版 Android CLI**：將 `android.ps1` 與 `tools.psd1` 從已棄用的 `sdkmanager.bat` 全面切換為新版 `android CLI` 執行檔，並將工具名稱與安裝目錄統一調整為 Android CLI（apps\Android）。
- **統一 uv 執行檔與驗證路徑**：將 `tools.psd1` 與 `core.psm1` 中的 uv 執行檔路徑從 `data\.uv\bin` 統一對齊至 `data\.local\bin`，並將自我檢測指令更新為 `python --version`。

### 修復

- **Android CLI 執行檔偵測與錯誤攔截**：改用遞迴檔案搜尋動態定位新版 `android.exe` 或 `android.bat`，並暫時放寬 `$ErrorActionPreference` 避免非致命 `stderr` 輸出中斷安裝；同時移除 `sdkmanager` 衝突參數並補齊 `$LASTEXITCODE` 檢查。
- **VS Code 開啟檔案對話框路徑錯誤**：預先建立沙盒 `data\Desktop` 資料夾，解決更改 `USERPROFILE` 後 Windows 原生檔案對話框找不到桌面節點而跳出「位置無法使用」警告的問題。
- **PowerShell >nul 重新導向裝置錯誤**：將 `launcher.ps1` 中 `cmd /c` 的輸出丟棄改用原生管線 `| Out-Null`，修正觸發 `FileStream` 非檔案裝置例外的問題。

## [0.2.1] - 2026-11-21

### 新增

- **輕量化 Python 環境管理 (`uv`)**：以高性能的 `uv`（`uv.ps1`）全面取代體積龐大的 WinPython，自動將受管 Python 與套件快取隔離於 `data\.uv` 沙盒中。
- **統一介面模組 (`ui.psm1`)**：建立獨立介面元件庫，統一全系統狀態標籤（`Write-Status`）、分隔線、頁首頁尾與互動式暫停提示。
- **單一設定來源 (`tools.psd1`)**：新增 `AppName` 與 `AppVer` 全域設定，讓視窗標題、打包檔名與原始碼匯出檔名自動同步，免除手動維護。
- **GitHub 無限流版本查詢 (`Get-GitHubLatestTag`)**：改用 `releases/latest` HTTP 重導向標頭解析 `git` 與 `uv` 最新版本，徹底繞過 GitHub API 每小時 60 次未認證限流。
- **Android SDK 自動裝配**：安裝 `android` 工具時，自動確保 JDK 17 就緒、自動簽署所有授權條款並預裝 `platform-tools`（ADB 與 Fastboot）。

### 調整

- **主選單架構精簡**：將 `[U]` 更名為「工具更新中心」，並將開發者專用功能 `[B] 單檔封裝打包` 與 `[O] 匯出專案原始碼快照` 移至主選單（僅在原始碼模式下顯示，單檔執行模式自動隱藏）。
- **環境啟動與設定整合**：精簡 `launcher.ps1` 環境設定表（`$profileMap`），統一使用英文標題（`Title`）同步終端機掛載日誌與視窗標題列。
- **暫存與工具集中管理**：將解壓縮工具 `7zr.exe` 移至 `apps\_cache` 集中存放，執行 `[C] 清理快取` 時自動保留不誤刪。
- **快照匯出防呆 (`code_dump.ps1`)**：自動排除所有 `PortableDEV_*` 打包檔與歷史快照檔，避免重複包入原始碼輸出中。

### 修復

- **表格欄位溢位排版**：在 `ui.psm1` 新增全形字寬計算（`Get-VisualWidth`）與超長字串自動截斷（`-Truncate`），解決工具更新中心內 OpenJDK 完整版本號過長導致表格跑版的問題。
- **VS Code 首次啟動英文介面問題**：將繁體中文語系快取（`languagepacks.json`）預熱機制整合至啟動層，首次啟動或資料夾移動／更名時自動重建索引，開啟即為完整繁體中文介面。
- **模組全域載入衝突**：統一所有子腳本採用條件式全域匯入（`Import-Module ... -Global`），修正子腳本重載模組時洗掉主程式 `Write-Status` 函式參照的錯誤。
- **單檔打包（Polyglot `.bat`）相容性**：修正 `build.ps1` 正則替換規則，完整清除記憶體函式內的 `$modRoot` 與 `Import-Module` 語句，解決單檔模式下 `$PSScriptRoot` 為空字串導致更新中心查詢失敗的問題。