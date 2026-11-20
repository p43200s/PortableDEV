# PortableDEV — Windows 零污染可攜式開發環境整合器

**PortableDEV** 是一套專為 Windows 設計的輕量級、免安裝、沙盒隔離式開發環境整合工具。不需要系統管理員權限，也不會修改宿主機的環境變數或登錄檔，只需將資料夾（甚至單一 `.bat` 執行檔）放入隨身碟或雲端硬碟，插上任何一台 Windows 電腦即可立刻開始開發。

---

## ✨ 核心特色

* **🛡️ 完整沙盒隔離（Zero-Pollution Sandbox）**
  啟動時動態覆寫 Process 層級的 `USERPROFILE`、`HOME`、`APPDATA`、`LOCALAPPDATA`、`NPM_CONFIG_PREFIX`、`PYTHONUSERBASE`、`ANDROID_USER_HOME` 等環境變數，將所有設定檔、套件快取與擴充套件完全鎖定在本地 `data/` 目錄內，不留任何痕跡於宿主機。
* **🔄 跨電腦移動路徑自動修復（Relocation Self-Healing）**
  解決隨身碟在不同電腦之間切換磁碟代號（如 `D:\` 變成 `E:\`）導致工具壞掉的痛點：
  * 自動掃描並二進位覆寫 Python `Scripts\*.exe` 內嵌的 `#!` Shebang 絕對路徑。
  * 自動偵測根目錄路徑變更，清理寫死舊路徑的 VS Code 快取並重新注入最新路徑。
* **⚡ 平行版本檢查與斷點續傳更新中心**
  內建多執行緒（`RunspacePool`）版本檢查器，可同時向各工具官方 API 查詢最新版本；下載過程呼叫 Windows 內建 `curl.exe` 支援斷點續傳與本地 `_cache` 快取機制。
* **📦 Polyglot 雙語混合單一執行檔打包**
  內建建置腳本可將所有 PowerShell 模組、安裝器與設定檔封裝為單一 `.bat` 檔案，方便在 GitHub Releases 分發或部署至全新空資料夾。
* **🔀 多版本環境一鍵切換**
  支援環境隔離與乾淨還原（`Restore-BaseEnvironment`），可在一般開發環境（OpenJDK 25）與 Android 除錯環境（OpenJDK 17）之間自由切換而不互相干擾。

---

## 🧰 內建整合工具清單

所有工具皆直接從官方 API 或 GitHub Releases 動態取得最新版本：

| 工具鍵值 | 工具名稱 | 官方來源 | 隔離與整合細節 |
| :--- | :--- | :--- | :--- |
| `git` | **Portable Git** | Git for Windows Releases | 自動執行 `post-install.bat` 初始化 |
| `jdk17` | **OpenJDK 17** | Eclipse Adoptium API | 專供 Android 除錯環境掛載 `JAVA_HOME` |
| `jdk25` | **OpenJDK 25** | Eclipse Adoptium API | 主力開發環境預設 `JAVA_HOME` |
| `winpython` | **WinPython slim** | WinPython Releases | 支援移動後自動修復 `Scripts\*.exe` 路徑 |
| `nodejs` | **Node.js LTS** | Node.js 官方 Dist Index | 全域套件與快取隔離至 `data\.npm-global` |
| `android` | **Android SDK** | Android Command-line Tools | 升級時保留已安裝的 `platform-tools` 並自動同步更新 |
| `vscode` | **VS Code** | VS Code Update API | 啟用 `VSCODE_PORTABLE`，自動預裝繁中語系與 Python 套件並同步 JDK/Python 路徑 |
| `agy` | **Antigravity CLI** | Antigravity Manifest API | 支援 `amd64` / `arm64` 架構偵測，設定檔隔離至 `data\agy-home` |

---

## 🚀 快速開始

### 方式一：下載單一封裝檔（推薦一般使用者）
1. 前往本專案的 [Releases](../../releases) 頁面，下載最新版的 `PortableDEV_x.x.x.bat`。
2. 將該檔案放入任意空白資料夾（例如 `D:\PortableDEV\`）。
3. 雙擊執行 `PortableDEV_x.x.x.bat`，選擇 **[U] 版本檢查與更新中心** 並按 **[A]** 即可自動下載並建置完整環境。

### 方式二：使用原始碼執行（推薦開發者）
1. Clone 本儲存庫：
   ```bash
   git clone https://github.com/你的帳號/PortableDEV.git
   cd PortableDEV
   ```
2. 執行根目錄下的 `start.bat` 即可開啟啟動器主選單。

---

## 📁 目錄結構說明

```text
PortableDEV/
├── _modules/
│   ├── dev/
│   │   ├── build.ps1         # 打包腳本：將專案組裝為 Polyglot 單一 .bat 執行檔
│   │   └── code_dump.ps1     # 開發輔助：匯出目錄樹與完整原始碼快照
│   ├── installers/           # 各工具獨立安裝與版本查詢模組
│   │   ├── agy.ps1
│   │   ├── android.ps1
│   │   ├── git.ps1
│   │   ├── jdk.ps1
│   │   ├── nodejs.ps1
│   │   ├── vscode.ps1
│   │   └── winpython.ps1
│   ├── core.psm1             # 核心函式庫（沙盒隔離、快取下載、路徑修復、環境自檢）
│   ├── launcher.ps1          # 主選單與環境掛載進入點
│   ├── tools.psd1            # 工具清單、環境變數與 PATH 宣告設定檔
│   └── updater.ps1           # 多執行緒版本檢查、更新與快取清理中心
├── start.bat                 # 開發模式啟動入口
│
├── apps/                     # [執行期自動產生] 各工具解壓縮安裝目錄與 _cache
├── data/                     # [執行期自動產生] 沙盒家目錄（AppData、VS Code 設定、npm 全域套件等）
└── workspace/                # [執行期自動產生] 預設開發專案工作區
```

---

## 🛠️ 如何擴充自訂工具？

本專案採用「設定檔驅動 + 模組化安裝器」架構，新增工具只需兩個步驟：

1. **在 `_modules/tools.psd1` 註冊工具資訊**：
   ```powershell
   mytool = @{
       Order     = 90
       Name      = "My Custom Tool"
       Dir       = "MyTool"
       Paths     = @("bin")
       Env       = @{ MYTOOL_HOME = "{APP}" }
       VerifyCmd = "mytool --version"
   }
   ```
2. **在 `_modules/installers/mytool.ps1` 實作 `query` 與 `install` 模式**：
   ```powershell
   param([string]$RootDir, [string]$ToolKey = "mytool", [string]$Mode = "install")
   $ErrorActionPreference = "Stop"
   Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "core.psm1") -Force

   # 1. 取得最新版本號 $ver 與下載連結 $url
   if ($Mode -eq "query") { return @{ Version = $ver; Url = $url } }

   # 2. 呼叫 Get-CachedPackage 下載、解壓縮至 apps\MyTool，最後呼叫 Complete-ToolInstall
   ```

---

## 👨‍💻 開發者隱藏指令

在 **[U] 版本檢查與更新中心** 畫面中（僅限原始碼開發模式），支援以下隱藏快捷鍵：
* **`[B]`**：執行 `_modules/dev/build.ps1`，將目前程式碼打包為可獨立分發的 `PortableDEV_<版本號>.bat`。
* **`[O]`**：執行 `_modules/dev/code_dump.ps1`，將目錄樹與所有腳本匯出為 `code_dump.txt` 以便檢閱或進行 AI Code Review。

---

## 📋 系統需求

* **作業系統**：Windows 10 / Windows 11（內建 PowerShell 5.1 與 `curl.exe`）
* **架構**：x64（Antigravity CLI 額外支援 ARM64）
* **權限需求**：無需系統管理員權限（Standard User 即可完整運作）

---

## 📄 授權條款

本專案採用 [MIT License](LICENSE) 授權。整合之第三方工具（Git、OpenJDK、WinPython、Node.js、Android SDK、VS Code、Antigravity CLI）各自受其原始授權條款規範。