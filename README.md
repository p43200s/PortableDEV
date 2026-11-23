# PortableDEV — 可攜式開發環境啟動器

**PortableDEV** 是專為 Windows 設計的輕量、免安裝、沙盒隔離式開發環境整合工具。無需系統管理員權限，也不會寫入系統環境變數或登錄檔；只需將資料夾放入隨身碟或雲端硬碟，就能在任意 Windows 電腦上隨插即用。

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

## 📱 簡易 Android 手機最佳化範例

以下是通用版 Android ADB 優化 Prompt，不限手機品牌（三星、小米、OPPO、Pixel、ASUS、Motorola 皆適用）。

只要把下方整段文字複製貼到 AI 對話中，依照步驟，附上自己手機匯出的 enabled_packages.txt 檔案即可：

```
你是一位精通 Android 系統底層與 ADB（Android Debug Bridge）優化的技術專家。我現在要透過電腦端的 `platform-tools`（ADB 環境），在不 Root 的情況下安全地停用手機內多餘的系統服務、遙測回報（Telemetry）、廣告追蹤與預載推廣軟體，以達到省電與減少背景喚醒的目的。

請嚴格依照以下 **四階段互動流程** 協助我操作，並確保所有給我的指令都能直接複製貼上到終端機（CMD / PowerShell / Terminal）執行：

### 第一階段：引導匯出清單
當我貼上這段指令給你時，請先給我檢查連線（`adb devices`）以及匯出目前所有已啟用套件清單（`adb shell pm list packages -e > enabled_packages.txt`）的指令，並提醒我開啟 USB 偵錯。接著等待我上傳或貼上 `enabled_packages.txt` 的內容。

### 第二階段：品牌識別與分類篩選指令
當我提供 `enabled_packages.txt` 後，請先從套件名稱判斷我的手機品牌與晶片平台（例如 Samsung、Xiaomi、OPPO/Realme、Pixel、ASUS、Motorola 等），並將可停用的項目分為兩類輸出給我：
1. **高安全性建議停用（可直接全選貼上執行）**：專門針對系統日誌回報、使用習慣分析、廣告追蹤 API、廠商推廣安裝器、Meta/第三方預載背景服務等。指令格式統一使用 `adb shell pm disable-user --user 0 <套件名稱>`。
2. **視個人習慣決定（選用省電項目）**：列出耗電但影響特定功能的套件（例如：數位健康、Google 助理語音喚醒、Android Auto、廠商桌面投影模式、內建瀏覽器或影音 App），讓我自行決定是否執行。
3. **核心防呆保護**：絕對不可列入會導致無法開機（Bootloop）、系統介面崩潰、通話簡訊異常、Google Play 服務（GMS）失效、WebView 閃退，或該品牌特有的核心實用功能（例如相機、指紋/臉部辨識、品牌經典快捷手勢）。

### 第三階段：錯誤排除與深度背景限制（Fallback 機制）
當我回報執行結果時，若部分套件出現 `Failure: package is non-disable` 或權限錯誤而無法停用，請依序提供以下替代方案：
1. 先嘗試改用 `adb shell pm uninstall -k --user 0 <套件名稱>` 移除。
2. 若系統韌體層依然阻擋移除，請改用 **AppOps 權限封鎖 + 休眠限制** 指令，剝奪其在背景執行與喚醒 CPU 的能力：
   - `adb shell cmd appops set <套件名稱> RUN_IN_BACKGROUND ignore`
   - `adb shell cmd appops set <套件名稱> RUN_ANY_IN_BACKGROUND ignore`
   - `adb shell cmd appops set <套件名稱> WAKE_LOCK ignore`
   - `adb shell am set-standby-bucket <套件名稱> restricted`
   - `adb shell am force-stop <套件名稱>`
   並告訴我如何透過 `cmd appops get <套件名稱>` 驗證設定是否成功寫入。

### 第四階段：收尾與一鍵還原備份
確認所有調整皆順利完成後，提醒我執行 `adb reboot` 重開機套用變更，並主動幫我把這次所有「已停用的套件（`pm enable`）」與「修改過權限的套件（`cmd appops reset`）」整理成一份**完整的一鍵還原指令備份**，方便我日後存檔。

現在，請先回覆我第一階段的準備與匯出指令。
```

## 📋 系統需求

* 作業系統：Windows 10 / Windows 11（需要 PowerShell 5.1 與 curl.exe）
* 架構：x64
* 權限需求：無需系統管理員權限

## 🤖 AI 輔助開發聲明

* 本專案的架構設計、程式碼撰寫與文件維護，絕大部分皆透過 AI 輔助生成，並經由人工審查與實際環境測試。
* 若在使用過程中發現任何非預期行為或潛在問題，歡迎透過 [Issues](../../issues) 回報與交流。

## 📄 授權條款

* 本專案採用 MIT License 授權。整合之第三方工具（Git、OpenJDK、uv、Node.js、Android SDK、VS Code、Antigravity CLI）各自受其原始授權條款規範。
