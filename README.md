# PortableDEV — 可攜式開發環境啟動器

**PortableDEV** 是一套專為 Windows 設計的輕量、免安裝、沙盒隔離式開發環境整合工具。無需系統管理員權限，也不會寫入系統環境變數或登錄檔；只需將資料夾放入隨身碟或雲端硬碟，就能在任意 Windows 電腦上隨插即用。

## 🎯 開發動機與應用場景

由於個人不希望偶爾使用的開發工具散落並污染 Windows 系統環境，因此將常用工具整合進單一沙盒啟動器中。目前主要應用於**輕量級工具開發**、**AI 輔助程式碼生成**以及 **Android ADB 系統調校**。

例如搭配近期流行的 [Clean Your TV](https://github.com/Gathin23/cleanyourtv)，即使不依賴 AI 工具，也能直接啟動本專案的 Android 除錯環境，透過 `adb` 指令手動為 Android TV 進行系統精簡與最佳化。

## 🧰 整合工具清單

所有工具皆直接從官方 API 或 GitHub Releases 取得最新版本：

| 名稱 | 官方來源 | 說明與整合應用 |
| :--- | :--- | :--- |
| **Portable Git** | [Git for Windows](https://gitforwindows.org/) | 提供完整的 Git 版本控制與 Bash 指令列環境；整合後自動執行初始化並設定沙盒家目錄，避免 `.gitconfig` 殘留於宿主機。 |
| **OpenJDK 17** | [Eclipse Adoptium](https://adoptium.net/) | 長期支援版（LTS）Java 開發套件；專供 **Android 除錯環境**掛載為 `JAVA_HOME`，確保 `sdkmanager` 與相關工具穩定相容。 |
| **OpenJDK 25** | [Eclipse Adoptium](https://adoptium.net/) | 最新版 Java 開發套件；作為**開發環境（VS Code / CMD / PowerShell）**的預設 `JAVA_HOME`，供日常編譯與語言伺服器使用。 |
| **uv** | [astral-sh/uv](https://github.com/astral-sh/uv) | Rust 編寫的高速 Python 版本與套件管理器；取代傳統肥大的發行版，自動將受管 Python 與虛擬環境快取隔離於 `data\.uv` 目錄中。 |
| **Node.js LTS** | [Node.js](https://nodejs.org/) | 長期支援版 JavaScript 執行環境；將全域套件（`npm -g`）與快取路徑導向 `data\.npm-global`，支援各類前端工具與 CLI 套件運作。 |
| **Android SDK** | [Android Developers](https://developer.android.com/) | Android 官方命令列工具組；安裝時自動簽署授權並預裝 `platform-tools`（內含 `adb` 與 `fastboot`），免裝龐大的 Android Studio 即可連接手機或 Android TV 除錯。 |
| **VS Code** | [Visual Studio Code](https://code.visualstudio.com/) | 輕量級跨平台程式碼編輯器；自動啟用可攜模式（`VSCODE_PORTABLE`），預裝繁體中文語系與 Python 擴充套件，並於每次啟動時自動同步沙盒內的 JDK 與 Python 路徑。 |
| **Antigravity CLI** | [Antigravity](https://antigravity.google/) | AI 輔助開發與自動化命令列工具；支援自動偵測系統架構，並將認證與設定檔隔離儲存於 `data\agy-home` 目錄內。 |

## 🚀 快速開始

### 方式一：下載封裝檔（推薦一般使用者）

1. 前往本專案的 [Releases](../../releases) 頁面，下載最新版的 `PortableDEV_x.x.x.bat`。
2. 將該檔案放入任意空白資料夾中（例如 `D:\PortableDEV\`）。
3. 雙擊執行 `PortableDEV_x.x.x.bat`，於主選單直接選擇欲使用的環境項目（或進入 `[U] 工具更新中心`），系統便會自動下載並建置所需工具。

### 方式二：原始碼執行（推薦開發者）

1. Clone 本儲存庫：

```
git clone https://github.com/p43200s/PortableDEV
cd PortableDEV
```

2. 執行根目錄下的 start.bat 即可開啟啟動器主選單。

## 📁 目錄結構說明

```
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
│   │   ├── uv.ps1
│   │   └── vscode.ps1
│   ├── core.psm1             # 核心函式庫
│   ├── launcher.ps1          # 主選單與環境掛載進入點
│   ├── tools.psd1            # 工具清單與環境變數設定檔
│   ├── ui.psm1               # 終端機介面元件
│   └── updater.ps1           # 工具更新中心
├── start.bat                 # 開發模式啟動入口
│
├── apps/                     # [執行期自動產生] 各工具解壓縮安裝目錄與快取
├── data/                     # [執行期自動產生] 沙盒家目錄
└── workspace/                # [執行期自動產生] 預設開發專案工作區
```

## 📋 系統需求

* 作業系統：Windows 10 / Windows 11（需要 PowerShell 5.1 與 curl.exe）
* 架構：x64
* 權限需求：無需系統管理員權限

## 📄 授權條款

* 本專案採用 MIT License 授權。整合之第三方工具（Git、OpenJDK、uv、Node.js、Android SDK、VS Code、Antigravity CLI）各自受其原始授權條款規範。
