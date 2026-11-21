@{
    AppName = "可攜式開發環境啟動器"
    AppVer  = "0.2.1"

    Tools = @{
        git = @{
            Order     = 10
            Name      = "Portable Git"
            Dir       = "PortableGit"
            Paths     = @("cmd", "usr\bin")
            VerifyCmd = "git --version"
        }
        jdk17 = @{
            Order        = 20
            Name         = "OpenJDK 17 (Adoptium)"
            Installer    = "jdk"
            Dir          = "OpenJDK17"
            MajorVersion = 17
            Paths        = @("bin")
            Env          = @{ JAVA_HOME = "{APP}" }
            VerifyCmd    = "java -version"
        }
        jdk25 = @{
            Order        = 30
            Name         = "OpenJDK 25 (Adoptium)"
            Installer    = "jdk"
            Dir          = "OpenJDK25"
            MajorVersion = 25
            Paths        = @("bin")
            Env          = @{ JAVA_HOME = "{APP}" }
            VerifyCmd    = "java -version"
        }
        uv = @{
            Order     = 40
            Name      = "uv (Python Manager)"
            Dir       = "UV"
            Paths     = @("", "{DATA}\.uv\bin")
            Env       = @{
                UV_CACHE_DIR          = "{DATA}\.uv\cache"
                UV_PYTHON_INSTALL_DIR = "{DATA}\.uv\python"
                UV_TOOL_DIR           = "{DATA}\.uv\tools"
                UV_TOOL_BIN_DIR       = "{DATA}\.uv\bin"
            }
            VerifyCmd = "uv --version"
        }
        nodejs = @{
            Order     = 50
            Name      = "Node.js LTS"
            Dir       = "NodeJS"
            Paths     = @("", "{DATA}\.npm-global")
            Env       = @{
                NPM_CONFIG_PREFIX = "{DATA}\.npm-global"
                NPM_CONFIG_CACHE  = "{DATA}\.npm-cache"
                XDG_CONFIG_HOME   = "{DATA}\.config"
            }
            VerifyCmd = "node -v"
        }
        android = @{
            Order     = 60
            Name      = "Android SDK"
            Dir       = "AndroidSDK"
            Paths     = @("cmdline-tools\latest\bin", "emulator", "platform-tools")
            Env       = @{
                ANDROID_HOME      = "{APP}"
                ANDROID_USER_HOME = "{DATA}\.android"
            }
            VerifyCmd = "sdkmanager --version"
        }
        vscode = @{
            Order     = 70
            Name      = "VS Code"
            Dir       = "VSCode"
            Paths     = @("bin")
            Env       = @{ VSCODE_PORTABLE = "{DATA}\vscode" }
            VerifyCmd = "code --version"
        }
        agy = @{
            Order     = 80
            Name      = "Antigravity CLI"
            Dir       = "Antigravity"
            Paths     = @("")
            Env       = @{ GEMINI_CLI_HOME = "{DATA}\agy-home" }
            VerifyCmd = "agy --version"
        }
    }
}