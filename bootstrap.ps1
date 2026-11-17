#Requires -Version 5.1
<#
.SYNOPSIS
    自包含的开发环境搭建脚本：单文件，拷到任意目录都能跑。
.DESCRIPTION
    清单 / 插件 / Git 配置 / 校验逻辑全部内联，不读取同目录任何文件。
    不修改 PATH、不往全局 Git 写 include.path、不硬编码脚本所在路径。
    winget 不指定版本号 = 最新稳定版；已安装则升级。可重复执行。
    强制遵循「软件安装位置规则」：所有软件默认装 D 盘，非必要绝不装 C 盘。
.EXAMPLE
    bootstrap.ps1 -List
    bootstrap.ps1 -Only 1,2,3
    bootstrap.ps1 -All
    bootstrap.ps1
.NOTES
    裸命令需要先在本机执行一次：Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
    并在 $PROFILE 注册别名（内容为 Set-Alias bootstrap.ps1 <脚本路径>）。
    若未注册别名，在脚本所在目录用 .\bootstrap.ps1 -List 同样可用。
    -All 执行全部步骤；不带参数等价 -All；
    始终记住：清单在 $Steps，插件在 $Extensions，Git 配置在 $GitSettings。
#>
[CmdletBinding()]
param(
    # 工具链 / 仓库 / 数据根目录，默认 D:\Dev；换机无 D 盘用 -WorkspaceRoot 覆盖
    [string]$WorkspaceRoot = 'D:\Dev',
    # 软件本体的唯一安装根，默认 D:\Program Files；所有 winget 包都带 --location 落到它下面
    [string]$InstallRoot = 'D:\Program Files',
    # Qt 下载镜像：国内镜像可避免 download.qt.io 连接失败 / IncompleteRead
    [string]$QtMirror = 'https://mirrors.aliyun.com/qt/',
    # Qt 版本：留空 = 自动从高到低 dry-run 探测镜像上真正可装的版本；也可显式钉版本（如 6.10.3）
    [string]$QtVersion = '',
    [object]$Only = '',
    [switch]$All,
    [switch]$List,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

# ============================================================
# 安装规则（用户强制约定，2026-11-14 起，后续所有安装/配置一律遵循）
#   1. 软件本体 → $InstallRoot（D:\Program Files）；工具链/仓库/数据 → $WorkspaceRoot（D:\Dev）
#   2. 每个 winget install 都必须带 --location；Qt/aqt 用 -O，EIM 用 -p，Qt 官方用 --root
#   3. 不得出现不带目标路径的安装命令，也不接受安装器默认的 C 盘位置
#   4. 仅 MSIX/Appx（PowerShell 7、Windows Terminal）无法改位置，属必要例外，
#      清单里标 noRelocate 并在执行时明确打印，绝不假装装到了 D 盘
#   5. 换机无 D 盘时由 -InstallRoot / -WorkspaceRoot 显式覆盖，不静默回退到 C 盘
# ============================================================
$QtRoot = Join-Path $WorkspaceRoot 'tools\Qt'

# ============================================================
# 一、安装清单（唯一需要维护的地方：往后追加一项即可）
#    kind: winget / vscode-extensions / git-config / dirs / manual / check
# ============================================================
$Steps = @(
    @{ no = 1; title = '安装最新版 VSCode'; kind = 'winget'; id = 'Microsoft.VisualStudioCode'; dir = 'Microsoft VS Code';
       detail = 'winget 不写版本号 = 最新稳定版；--location 装到 D 盘，install + upgrade 成对执行。';
       check = 'code --version'; enabled = $true },
    @{ no = 2; title = '安装 VSCode 插件'; kind = 'vscode-extensions';
       detail = '按下方 $Extensions 逐个安装（含中文语言包、CodeBuddy），--force 保证升到最新。';
       check = 'code --list-extensions'; enabled = $true },
    @{ no = 3; title = '安装最新版 Git'; kind = 'winget'; id = 'Git.Git'; dir = 'Git';
       detail = '最新稳定版 Git for Windows，自带 Git Bash 与凭据管理器；--location 装到 D 盘。';
       check = 'git --version'; enabled = $true },
    @{ no = 4; title = '安装最新版 PowerShell 7'; kind = 'winget'; id = 'Microsoft.PowerShell'; noRelocate = $true;
       detail = 'pwsh，脚本运行环境；系统自带 5.1 保留不动。【必要例外】MSIX 包固定 C 盘 WindowsApps，winget 无法改位置。';
       check = 'pwsh --version'; enabled = $true },
    @{ no = 5; title = '安装最新版 Windows Terminal'; kind = 'winget'; id = 'Microsoft.WindowsTerminal'; noRelocate = $true;
       detail = '统一管理 PowerShell / Git Bash / ESP-IDF 命令行窗口。【必要例外】MSIX 包固定 C 盘 WindowsApps，winget 无法改位置。';
       check = 'wt --version'; enabled = $true },
    @{ no = 6; title = '安装最新版 7-Zip'; kind = 'winget'; id = '7zip.7zip'; dir = '7-Zip';
       detail = '解压 ESP-IDF 离线包、固件包、SDK 归档；--location 装到 D 盘。';
       check = 'winget list --id 7zip.7zip'; enabled = $true },
    @{ no = 7; title = '安装最新版 Python 3.12'; kind = 'winget'; id = 'Python.Python.3.12'; dir = 'Python312';
       detail = '通用脚本用；ESP-IDF 自带独立 Python，互不干扰；--location 装到 D 盘。';
       check = 'python --version'; enabled = $true },
    @{ no = 8; title = '安装 PuTTY（串口调试）'; kind = 'winget'; id = 'PuTTY.PuTTY'; dir = 'PuTTY';
       detail = '查看主板串口日志，烧录调试备用终端；--location 装到 D 盘。';
       check = 'winget list --id PuTTY.PuTTY'; enabled = $true },
    @{ no = 9; title = '配置 Git 全局项'; kind = 'git-config';
       detail = '逐项写入下方 $GitSettings，不生成任何文件、不写 include.path。';
       check = 'git config --global --list'; enabled = $true },
    @{ no = 10; title = '创建统一工作目录'; kind = 'dirs'; dirs = @('repos', 'tools', 'esp', 'tmp');
       detail = '根目录由 -WorkspaceRoot 指定，默认 D:\Dev；换机没有 D 盘时用 -WorkspaceRoot 覆盖。';
       check = 'dir <工作目录根>'; enabled = $true },
    @{ no = 11; title = '安装 ESP-IDF v6.0 工具链'; kind = 'manual';
       detail = '官方安装器自带 Python/编译器/OpenOCD，winget 无可靠包，必须人工装。';
       howto = @(
           '到 Espressif 官网下载 ESP-IDF Windows Installer（离线版），选择 v6.0',
           "安装到 $WorkspaceRoot\esp\v6.0，工具链放 $WorkspaceRoot\esp\tools，路径不要有空格和中文",
           '设置系统环境变量 IDF_PATH 与 IDF_TOOLS_PATH 指向上述目录',
           'VSCode 装 espressif.esp-idf-extension，用向导关联已装好的 IDF_PATH',
           '验证：运行 IDF_PATH\export.ps1 后执行 idf.py --version'
       ); enabled = $true },
    @{ no = 12; title = '安装 Qt6 + MinGW（官方完整 IDE）'; kind = 'manual';
       detail = "官方在线安装器，需 Qt 账号、含 Qt Creator；安装路径必须改成 $QtRoot，不要用默认 C:\Qt。免账号的自动装法见步骤 18。";
       howto = @(
           '下载 Qt Online Installer 并登录 Qt 账号',
           '组件勾选：Qt 6.x → MinGW 64-bit 工具链、Qt Core/Widgets/Network、Qt Creator',
           "安装向导里把路径改为 $QtRoot；--root 即安装根，不要留默认 C:\Qt",
           "无人值守：qt-unified-windows-x64-online.exe --root $QtRoot --accept-licenses --default-answer --confirm-command install <组件名>",
           '组件名先用 installer.exe search 查；登录用 --email/--pw 或已缓存的 qtaccount.ini',
           "把 $QtRoot\Tools\mingw*\bin 与 $QtRoot\<版本>\mingw_64\bin 加入 PATH",
           '验证：qmake --version 与 mingw32-make --version'
       ); enabled = $true },
    @{ no = 13; title = '安装 USB 串口 / JTAG 驱动'; kind = 'manual';
       detail = '跟硬件走，无法跨机器自动化；烧录与串口日志必需。';
       howto = @(
           '按主板实际芯片安装 CP210x / CH340 / FTDI 驱动',
           '若用 JTAG 调试，另装对应调试器驱动与 OpenOCD 规则',
           '设备管理器确认 COM 口出现，PuTTY 能读到日志'
       ); enabled = $true },
    @{ no = 14; title = '恢复 SSH 密钥并验证 GitLab'; kind = 'manual';
       detail = '凭据绝不写进脚本或仓库，用加密载体单独迁移。';
       howto = @(
           '从加密载体恢复 id_ed25519_new 到 %USERPROFILE%\.ssh\，权限仅当前用户可读',
           '在 %USERPROFILE%\.ssh\config 里为 GitLab 主机指定 IdentityFile',
           '验证：ssh -T git@liberlive-gitlab.liberlive-music.com'
       ); enabled = $true },
    @{ no = 15; title = '克隆项目仓库并切换分支'; kind = 'manual';
       detail = '代码仓库按分支策略 checkout，不写死在脚本里。';
       howto = @(
           "git clone 到 $WorkspaceRoot\repos 下对应目录",
           'checkout 当前开发分支，按需合并其他分支',
           '确认 git status 干净，submodule 已初始化'
       ); enabled = $true },
    @{ no = 16; title = '冒烟校验'; kind = 'check';
       detail = '按目录实扫 ESP-IDF 框架/工具链、Qt qmake/MinGW，检查工具、Git 身份、SSH 私钥、插件数量、C 盘残留。';
       check = '重跑 -Only 16 即可单独校验'; enabled = $true },
    @{ no = 17; title = '安装最新版 ESP-IDF（ESP32 工具链）'; kind = 'winget'; id = 'Espressif.EIM-CLI'; dir = 'EIM';
       detail = "winget 装官方 EIM CLI（不钉版本），再用官方 TOML 配置执行 eim install：框架 / 工具链 / 下载缓存 / Python 虚拟环境全部显式落到 $WorkspaceRoot\esp。与步骤 11 的项目专用 v6.0 并存。首次下载数 GB，建议单跑 -Only 17。";
       postTool = 'eim'; eimConfig = $true;
       check = 'eim list 查看已装版本；装完重跑 -Only 16 复核校验表'; enabled = $true },
    @{ no = 18; title = '安装最新版 Qt6 + MinGW（自动，D 盘）'; kind = 'qt-aqt'; id = 'miurahr.aqtinstall'; dir = 'aqtinstall';
       detail = "winget 装 aqtinstall；按 --dry-run 逐个探测镜像上真正可装的 Qt 6.x（跳过无 Updates.xml 的版本），自动匹配配套 MinGW，走国内镜像、失败重试 3 次，全部 -O 装到 $QtRoot；以 qmake.exe 真实存在为成功判据。";
       check = "重跑 -Only 16 看 Qt qmake / Qt MinGW 是否 PASS"; enabled = $true }
    @{ no = 19; title = '配置 VSCode ESP-IDF 集成路径'; kind = 'vscode-idf-config';
       detail = '扩展 2.3.0 改用 EIM + idf.customExtraVars 取路径：用 idf.customExtraVars 只钉共享的 IDF_TOOLS_PATH=容器根（这是让 idf_tools.py export 成功的主开关；为空会报 cmake no installed versions），刻意不钉 IDF_PATH / IDF_PYTHON_ENV_PATH，交由 eim_idf.json 的选中版本决定，否则多版本会被锁死在同一版；同时修复 D:\Dev\esp\tools\eim_idf.json 残留的 C:\Espressif 路径 + 钉死 idf.eimIdfJsonPath + 加「ESP-IDF」终端 profile。需先跑步骤 17。';
       check = '打开 ESP 项目用 ESP-IDF 扩展 Build 按钮或「ESP-IDF」终端'; enabled = $true }
    @{ no = 20; title = '安装 ESP-IDF 多版本 6.0.2 / 5.4.3（与最新版共存）'; kind = 'eim-multi';
       detail = "复用步骤 17 的 EIM TOML，把 v6.0.2 与 v5.4.3 装进 $WorkspaceRoot\esp 的各自版本目录（v<版本>\esp-idf），与最新版共享同一个工具根 $WorkspaceRoot\esp\tools——工具按「名称\版本号」子目录并存，互不覆盖；每个版本各自生成 Microsoft.v<版本>.PowerShell_profile.ps1 与独立 venv。首次下载数 GB，建议单跑 -Only 20。";
       idfVersions = @('v6.0.2', 'v5.4.3');
       check = 'idf-use -List 应看到三个版本；装完重跑 -Only 16 复核'; enabled = $true }
    @{ no = 21; title = '安装 IDF 版本切换器（idf-use）'; kind = 'idf-switch';
       detail = '把 idf-use.ps1 部署到用户目录并在 PowerShell $PROFILE 注册裸命令 idf-use：切换当前会话的 IDF_PATH / IDF_PYTHON_ENV_PATH / PATH，同步 eim_idf.json 选中版本供 IDE 使用，并按需持久化用户级环境变量。需先跑步骤 17（或 20）。';
       check = 'idf-use -List；idf-use 5.4.3 后 idf.py --version'; enabled = $true }
    @{ no = 22; title = '安装 Node.js LTS（npm 全局目录落 D 盘）'; kind = 'winget'; id = 'OpenJS.NodeJS.LTS'; dir = 'nodejs';
       detail = "winget 装 Node.js LTS；实测该包是 wix 安装器，--location 生效，本体落 $InstallRoot\nodejs（C:\Program Files\nodejs 不产生目录）。装完把 npm 的 prefix / cache 改到 $WorkspaceRoot\tools 下——默认是 %APPDATA%\npm 与 %LOCALAPPDATA%\npm-cache，全局包一多就把 C 盘吃掉。脚本不改 PATH，全局命令目录需手动加入（见 README 5.9）。";
       postNode = $true;
       check = 'node --version；npm config get prefix 应指向 D 盘'; enabled = $true }
)

# ============================================================
# 二、VSCode 插件清单（加减插件只改这里）
# ============================================================
$Extensions = @(
    'ms-vscode.cpptools'
    'ms-vscode.cmake-tools'
    'espressif.esp-idf-extension'
    'ms-vscode.hexeditor'
    'eamodio.gitlens'
    'mhutchie.git-graph'                       # Git 提交图谱（SCM 增强）
    'donjayamanne.githistory'                  # Git 文件/提交历史查看（SCM 增强）
    'github.vscode-pull-request-github'        # GitHub PR / Issue 管理（SCM 增强）
    'ms-vscode.powershell'
    'ms-python.python'
    'redhat.vscode-yaml'
    'EditorConfig.EditorConfig'
    'yzhang.markdown-all-in-one'
    'PKief.material-icon-theme'
    'ms-ceintl.vscode-language-pack-zh-hans'   # VSCode 中文（简体）语言包
    'tencent-cloud.coding-copilot'             # 腾讯云代码助手 CodeBuddy（WorkBuddy 是独立客户端，无 VSCode 插件）
)
# 注：不含 twxs.cmake —— 官方已弃用（deprecated），CMake Tools 已内置 CMake 语言服务，装了会弹「建议卸载」。

# 插件用途对照：只用于 -List 展示，安装仍按 $Extensions 顺序执行
$ExtensionLabels = @{
    'ms-vscode.cpptools'                     = 'C/C++ 智能提示与调试'
    'ms-vscode.cmake-tools'                  = 'CMake 构建集成（含 CMake 语言服务）'
    'espressif.esp-idf-extension'            = 'ESP-IDF 开发（编译/烧录/监视）'
    'ms-vscode.hexeditor'                    = '二进制 / 固件十六进制查看'
    'eamodio.gitlens'                        = 'Git 行级溯源与提交对比'
    'mhutchie.git-graph'                     = 'Git 提交图谱（分支/合并可视化）'
    'donjayamanne.githistory'                = 'Git 文件 / 提交历史查看'
    'github.vscode-pull-request-github'      = 'GitHub PR / Issue 管理'
    'ms-vscode.powershell'                   = 'PowerShell 语言与调试支持'
    'ms-python.python'                       = 'Python 语言支持'
    'redhat.vscode-yaml'                     = 'YAML 语法校验'
    'EditorConfig.EditorConfig'              = '统一缩进 / 换行风格'
    'yzhang.markdown-all-in-one'             = 'Markdown 编辑增强'
    'PKief.material-icon-theme'              = '文件图标主题'
    'ms-ceintl.vscode-language-pack-zh-hans' = '中文（简体）界面语言包'
    'tencent-cloud.coding-copilot'           = '腾讯云代码助手 CodeBuddy'
}

# ============================================================
# 三、Git 全局配置（逐项写入，值里不含任何路径）
# ============================================================
$GitSettings = @(
    @{ Key = 'user.name';            Value = 'licong' }
    @{ Key = 'user.email';           Value = 'licong@liberlive-music.com' }
    @{ Key = 'core.longpaths';       Value = 'true' }
    @{ Key = 'core.autocrlf';        Value = 'false' }
    @{ Key = 'core.editor';          Value = 'code --wait' }
    @{ Key = 'init.defaultBranch';   Value = 'main' }
    @{ Key = 'pull.rebase';          Value = 'true' }
    @{ Key = 'push.autoSetupRemote'; Value = 'true' }
    @{ Key = 'merge.conflictStyle';  Value = 'zdiff3' }
    @{ Key = 'credential.helper';    Value = 'manager' }
    @{ Key = 'alias.st';             Value = 'status -sb' }
    @{ Key = 'alias.lg';             Value = 'log --oneline --graph --decorate --all' }
)

# ============================================================
# 四、工具定位：只返回可执行文件完整路径，绝不修改 $env:PATH
# ============================================================
# 先查 D 盘安装根，再兼容旧机器可能留在 C 盘的默认位置
$codeFallback = @(
    (Join-Path $InstallRoot 'Microsoft VS Code\bin\code.cmd')
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd')
    (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd')
)
$pf86 = ${env:ProgramFiles(x86)}
$gitFallback = @(
    (Join-Path $InstallRoot 'Git\cmd\git.exe')
    (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
)
if ($pf86) { $gitFallback += (Join-Path $pf86 'Git\cmd\git.exe') }
# portable 包 --location 到 D 盘后优先在目标目录找，再退回 WindowsApps shim
$eimFallback = @(
    (Join-Path $InstallRoot 'EIM\eim.exe')
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\eim.exe')
    (Join-Path $env:LOCALAPPDATA 'Programs\eim\eim.exe')
)
$aqtFallback = @(
    (Join-Path $InstallRoot 'aqtinstall\aqt_x64.exe')
    (Join-Path $InstallRoot 'aqtinstall\aqt.exe')
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\aqt_x64.exe')
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\aqt.exe')
)
function Resolve-Tool([string]$Name, [string[]]$Fallback) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in $Fallback) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Write-Title($s) { Write-Host "`n[步骤 $($s.no)] $($s.title)" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "    完成 $m" -ForegroundColor Green }
function Write-Hint([string]$m) { Write-Host "    验证 $m" -ForegroundColor DarkGray }

# EIM 官方 TOML 配置生成器。
# 背景（实测）：只给 `eim install -p D:\Dev\esp` 时，EIM 仅把 ESP-IDF 框架源码放 D 盘；
# 工具链、下载缓存、Python venv、激活脚本仍按默认落到 C:\Espressif（实测 10.42 GB），
# 违反「非必要绝不装 C 盘」。必须用官方配置文件把 6 个路径字段全部显式钉到 D 盘。
# 字段依据：https://docs.espressif.com/projects/idf-im-ui/en/latest/configuration.html
function New-EimConfig([string]$EspRoot) {
    $cfg = Join-Path $EspRoot 'eim-config.toml'
    # TOML 字符串里反斜杠需转义，统一用正斜杠；Windows 的 Rust PathBuf 接受正斜杠
    $p = $EspRoot -replace '\\', '/'
    $lines = @(
        '# Generated by bootstrap.ps1: force ALL ESP-IDF artifacts onto D drive'
        # 不写 idf_path：EIM 会按「path + 版本」自动派生，钉死反而装不了下一个最新版
        # 不写 python_env_folder_name：它默认落在 tool_install_folder_name 下，自动跟到 D 盘
        "path = `"$p`""
        "tool_download_folder_name = `"$p/dist`""
        "tool_install_folder_name = `"$p/tools`""
        "activation_script_path_override = `"$p/tools`""
        "config_file_save_path = `"$p/eim-config-saved.toml`""
        'non_interactive = true'
        'cleanup = true'
    )
    [System.IO.File]::WriteAllLines($cfg, $lines, (New-Object System.Text.UTF8Encoding($false)))
    return $cfg
}

# 指令速查：全部是裸命令，不含脚本路径，任意目录可敲
function Show-Commands {
    $total = @($Steps | Where-Object { $_.enabled }).Count
    # 整块字符串一次输出：避免逐行 Write-Host 在重定向时把空行吞掉、说明行粘连
    $guide = @"
  [可用指令] 裸命令，任意目录可敲
    bootstrap.ps1 -List                 查看安装清单 + 插件明细
    bootstrap.ps1 -Only 1,2,3           只跑指定步骤（单个写 -Only 17）
    bootstrap.ps1 -All                  安装所有：执行全部 $total 步
    bootstrap.ps1                       同 -All（不带参数即全部执行）
    bootstrap.ps1 -Only 16              单独跑冒烟校验
    bootstrap.ps1 -Help                 只看这段指令表
    bootstrap.ps1 -WorkspaceRoot <目录> -All    换机改工作根目录（默认 D:\Dev）
    bootstrap.ps1 -InstallRoot <目录> -All      换机改软件安装根（默认 D:\Program Files）
    bootstrap.ps1 -QtVersion 6.10.3 -Only 18    钉 Qt 版本（留空则自动探测可装版本）
    bootstrap.ps1 -QtMirror <镜像> -Only 18     换 Qt 下载镜像
  安装规则：软件本体 → $InstallRoot；工具链 / 仓库 → $WorkspaceRoot；非必要绝不装 C 盘。
  必要例外：步骤 4/5 为 MSIX 固定 C 盘；已装软件 --location 不迁移；EIM 索引 JSON 仍在 C 盘。
  说明：-All 会联网装/升级软件，可能弹 UAC；人工步骤只打印；校验最后执行。
        -All 与 -Only 不能同时使用。
"@
    Write-Host $guide -ForegroundColor Cyan
}

# ============================================================
# 五、冒烟校验（原 verify.ps1 的逻辑，已内联）
# ============================================================
function Invoke-Verify {
    $r = New-Object System.Collections.ArrayList
    foreach ($name in @('winget', 'git', 'code', 'pwsh', 'python', 'ssh')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        [void]$r.Add([pscustomobject]@{ Item = $name; Status = $(if ($c) { 'PASS' } else { 'FAIL' }); Detail = $(if ($c) { $c.Source } else { '未找到命令' }) })
    }
    $git = Resolve-Tool 'git' $gitFallback
    $mail = ''
    if ($git) { $mail = & $git config --global user.email 2>$null }
    [void]$r.Add([pscustomobject]@{ Item = 'Git 用户邮箱'; Status = $(if ($mail) { 'PASS' } else { 'FAIL' }); Detail = "user.email = $mail" })
    $key = Join-Path $env:USERPROFILE '.ssh\id_ed25519_new'
    [void]$r.Add([pscustomobject]@{ Item = 'SSH 私钥'; Status = $(if (Test-Path -LiteralPath $key) { 'PASS' } else { 'FAIL' }); Detail = $key })
    [void]$r.Add([pscustomobject]@{ Item = '工作目录'; Status = $(if (Test-Path -LiteralPath $WorkspaceRoot) { 'PASS' } else { 'FAIL' }); Detail = $WorkspaceRoot })
    $dirs = 0
    if (Test-Path -LiteralPath $InstallRoot) {
        $dirs = @(Get-ChildItem -LiteralPath $InstallRoot -Directory -ErrorAction SilentlyContinue).Count
    }
    [void]$r.Add([pscustomobject]@{ Item = '安装根（D 盘）'; Status = $(if (Test-Path -LiteralPath $InstallRoot) { 'PASS' } else { 'FAIL' }); Detail = "$InstallRoot（子目录 $dirs 个）" })

    # ESP-IDF：EIM 只在激活脚本 / 桌面快捷方式里注入 IDF_PATH，不会写系统环境变量，
    # 所以只读 $env:IDF_PATH 必然误报 FAIL。改为按目录扫已安装的框架。
    # 多版本下要列全：只显示第一个版本会让人误以为「只装了那一版」，也看不出 eim 当前选中谁。
    $espRoot = Join-Path $WorkspaceRoot 'esp'
    $idfDirs = @(Get-ChildItem -LiteralPath $espRoot -Directory -ErrorAction SilentlyContinue |
                 Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'esp-idf\tools\idf_tools.py') } |
                 Sort-Object Name)
    $idfSelName = ''
    $eimJsonChk = Join-Path $espRoot 'tools\eim_idf.json'
    if (Test-Path -LiteralPath $eimJsonChk) {
        try {
            $jChk = Get-Content -LiteralPath $eimJsonChk -Raw -Encoding UTF8 | ConvertFrom-Json
            $selRec = @($jChk.idfInstalled) | Where-Object { $_.id -eq $jChk.idfSelectedId } | Select-Object -First 1
            if ($selRec) { $idfSelName = $selRec.name }
        } catch { }
    }
    $idfDetail = if ($idfDirs.Count -gt 0) {
        $names = @($idfDirs | ForEach-Object { if ($_.Name -eq $idfSelName) { "$($_.Name)（选中）" } else { $_.Name } })
        "$espRoot 已装 $($idfDirs.Count) 个：$($names -join ' / ')"
    } else { "$espRoot 下未找到已装版本（步骤 17）" }
    $idfTools = Get-ChildItem -LiteralPath (Join-Path $espRoot 'tools') -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'xtensa|riscv|cmake|ninja' } | Select-Object -First 1
    [void]$r.Add([pscustomobject]@{ Item = 'ESP-IDF 框架'; Status = $(if ($idfDirs.Count -gt 0) { 'PASS' } else { 'FAIL' }); Detail = $idfDetail })
    [void]$r.Add([pscustomobject]@{ Item = 'ESP-IDF 工具链'; Status = $(if ($idfTools) { 'PASS' } else { 'FAIL' }); Detail = $(if ($idfTools) { "$espRoot\tools 已落地" } else { "$espRoot\tools 未找到（旧版脚本会误落 C:\Espressif）" }) })

    # Qt：装到 D 盘但未必加了 PATH，按目录扫 qmake.exe / mingw32-make.exe，不只看 Get-Command
    $qtQmake = $null; $qtMake = $null
    if (Test-Path -LiteralPath $QtRoot) {
        $qtQmake = Get-ChildItem -LiteralPath $QtRoot -Filter 'qmake.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $qtMake  = Get-ChildItem -LiteralPath $QtRoot -Filter 'mingw32-make.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    [void]$r.Add([pscustomobject]@{ Item = 'Qt qmake'; Status = $(if ($qtQmake) { 'PASS' } else { 'FAIL' }); Detail = $(if ($qtQmake) { $qtQmake.FullName } else { "$QtRoot 下未找到 qmake.exe（步骤 18 未成功）" }) })
    [void]$r.Add([pscustomobject]@{ Item = 'Qt MinGW'; Status = $(if ($qtMake) { 'PASS' } else { 'FAIL' }); Detail = $(if ($qtMake) { $qtMake.FullName } else { "$QtRoot 下未找到 mingw32-make.exe" }) })

    # Node.js：PATH 里的 node 可能是 WorkBuddy / nvm / 其它版本，只看 Get-Command 会误判。
    # 按「安装根目录实扫」判断本方案是否装到位，并顺带核对 npm 全局目录是否落在 D 盘。
    $nodeExe = Join-Path $InstallRoot 'nodejs\node.exe'
    $npmCmdChk = Join-Path $InstallRoot 'nodejs\npm.cmd'
    $nodeOk = Test-Path -LiteralPath $nodeExe
    $nodeVer = ''
    $npmPrefix = ''
    if ($nodeOk) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $nodeVer = (& $nodeExe --version 2>&1 | Select-Object -First 1)
            if (Test-Path -LiteralPath $npmCmdChk) {
                $npmPrefix = (& $npmCmdChk config get prefix 2>&1 | Select-Object -Last 1)
            }
        } catch { } finally { $ErrorActionPreference = $prevEap }
    }
    $nodeDetail = $null
    if (-not $nodeOk) {
        $nodeDetail = "$InstallRoot\nodejs 下未找到 node.exe（步骤 22）"
    } elseif ($npmPrefix -and $npmPrefix.ToLower().StartsWith($WorkspaceRoot.ToLower())) {
        $nodeDetail = "$nodeVer；npm prefix 在 D 盘"
    } else {
        $nodeDetail = "$nodeVer；npm prefix 仍在 C 盘：$npmPrefix"
    }
    [void]$r.Add([pscustomobject]@{ Item = 'Node.js'; Status = $(if ($nodeOk) { 'PASS' } else { 'FAIL' }); Detail = $nodeDetail })

    $codeExe = Resolve-Tool 'code' $codeFallback
    $n = 0
    if ($codeExe) { $n = @(& $codeExe --list-extensions 2>$null | Where-Object { $_ -and $_.Trim() }).Count }
    [void]$r.Add([pscustomobject]@{ Item = 'VSCode 扩展'; Status = $(if ($n -ge $Extensions.Count) { 'PASS' } else { 'FAIL' }); Detail = "已装 $n 个 / 清单 $($Extensions.Count) 个" })

    # D 盘规则体检：如实报告 C 盘残留，不假装全在 D 盘
    $cEspressif = 'C:\Espressif'
    $leak = Test-Path -LiteralPath $cEspressif
    [void]$r.Add([pscustomobject]@{ Item = 'C 盘残留'; Status = $(if ($leak) { 'WARN' } else { 'PASS' }); Detail = $(if ($leak) { "$cEspressif 仍存在（旧脚本遗留，见文档迁移章节）" } else { '未发现 C:\Espressif' }) })

    Write-Host ''
    $r | Format-Table @{ L = '项目'; E = 'Item' }, @{ L = '结果'; E = 'Status' }, @{ L = '说明'; E = 'Detail' } -AutoSize | Out-Host
    $fail = @($r | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warn = @($r | Where-Object { $_.Status -eq 'WARN' }).Count
    Write-Host "校验结果：PASS $(@($r).Count - $fail - $warn) 项，WARN $warn 项，FAIL $fail 项"
    if ($fail -gt 0) {
        Write-Host '说明：人工步骤（11–15）与首次未安装的工具链会 FAIL，属预期；' -ForegroundColor DarkGray
        Write-Host '      若已执行过 -Only 17 / -Only 18 仍 FAIL，说明安装真的失败了，重跑对应步骤。' -ForegroundColor DarkGray
    }
    else { Write-Host '说明：全部必需项通过。' -ForegroundColor DarkGray }
    Write-Host '边界：winget --location 仅对「全新安装」生效；已装软件不会自动迁移到 D 盘。' -ForegroundColor DarkGray
}

# ============================================================
# 六、执行
# ============================================================
$allSteps = @($Steps | ForEach-Object { [pscustomobject]$_ } | Sort-Object no)
# 冒烟校验永远最后执行：后续追加的 17、18… 不会排到校验后面，校验结果才准确
$ordered = @($allSteps | Where-Object { $_.kind -ne 'check' }) + @($allSteps | Where-Object { $_.kind -eq 'check' })

# -Only 用 [object] 接收再自行拆分，兼容两种调用：
#   powershell -File 传字符串 "1,2,3"；直接敲裸命令时 PowerShell 会把 1,2,3 解析成数组。
$onlySet = @()
if ($null -ne $Only) {
    $raw = @()
    if ($Only -is [array]) { $raw = @($Only | ForEach-Object { [string]$_ }) }
    else { $raw = @([string]$Only) }
    $onlySet = @((($raw -join ',') -split '[,;\s]+') | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
}

# -Help：只看指令表，不安装任何东西
if ($Help) { Show-Commands; return }

# -All 与 -Only 互斥，避免误触发全量安装
if ($All -and $onlySet.Count -gt 0) {
    Write-Warning '不能同时使用 -All 与 -Only：请二选一（本次未执行任何安装）。'
    return
}

# 不带参数 = 安装所有，给出明确提示
if (-not $All -and -not $List -and $onlySet.Count -eq 0) {
    Write-Host '[模式] 未指定步骤，按「安装所有」执行（等价 -All）。' -ForegroundColor DarkGray
}

if ($All) {
    $total = @($ordered | Where-Object { $_.enabled }).Count
    Write-Host "`n[安装所有] 即将执行全部 $total 步（人工步骤只打印操作，冒烟校验最后执行）。" -ForegroundColor Cyan
    Write-Host "    安装规则：软件本体 → $InstallRoot，工具链 / 仓库 → $WorkspaceRoot，非必要绝不装 C 盘。" -ForegroundColor Cyan
    Write-Host '    会联网下载并安装 / 升级软件，可能弹 UAC 确认；第 17 步 ESP-IDF、第 18 步 Qt 均需下载数 GB。' -ForegroundColor DarkGray
    Write-Host "    ESP-IDF 全部产物（框架/工具链/缓存/venv）→ $WorkspaceRoot\esp；Qt → $QtRoot" -ForegroundColor DarkGray
}

if ($List) {
    $allSteps | Format-Table @{ L = '编号'; E = 'no' }, @{ L = '方式'; E = 'kind' }, @{ L = '安装项'; E = 'title' }, @{ L = '启用'; E = 'enabled' } -AutoSize | Out-Host
    Write-Host "  [安装规则] 软件本体 → $InstallRoot；工具链 / 仓库 / 数据 → $WorkspaceRoot" -ForegroundColor Cyan
    Write-Host "    ESP-IDF 用官方 TOML 配置钉死 D 盘；Qt 镜像 $QtMirror（版本 $(if ($QtVersion) { $QtVersion } else { '自动探测' })）" -ForegroundColor Cyan
    foreach ($e in @($allSteps | Where-Object { $_.noRelocate })) {
        Write-Host "    必要例外 步骤 $($e.no)：MSIX 固定 C:\Program Files\WindowsApps，winget 无法改位置" -ForegroundColor Yellow
    }
    Write-Host '    必要例外：winget --location 仅对全新安装生效；已装软件不迁移；EIM 索引 JSON 仍在 C 盘（几 KB）。' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "  [步骤 2 明细] VSCode 插件清单（共 $($Extensions.Count) 个）" -ForegroundColor Cyan
    $idx = 0
    foreach ($id in $Extensions) {
        $idx++
        $label = $ExtensionLabels[$id]
        if (-not $label) { $label = '（未标注用途）' }
        Write-Host ("    {0,2}. {1,-40} {2}" -f $idx, $id, $label)
    }
    Show-Commands
    return
}

# 安装规则：确保 D 盘软件安装根存在（换机无 D 盘时须用 -InstallRoot 显式指定）
if (-not (Test-Path -LiteralPath $InstallRoot)) {
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Write-Host "[安装规则] 已创建软件安装根：$InstallRoot" -ForegroundColor Cyan
}

$manualPending = New-Object System.Collections.ArrayList
$done = 0

foreach ($s in $ordered) {
    if (-not $s.enabled) { continue }
    if ($onlySet.Count -gt 0 -and $onlySet -notcontains [int]$s.no) { continue }
    Write-Title $s
    if ($s.detail -and $s.kind -ne 'manual') { Write-Host "    说明 $($s.detail)" -ForegroundColor DarkGray }

    switch ($s.kind) {
        'winget' {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                Write-Warning '    未找到 winget：请先安装「应用安装程序 App Installer」，再用 -Only 重跑本步骤。'
                break
            }
            $pkgId = $s.id
            $target = $null
            if ($s.dir) { $target = Join-Path $InstallRoot $s.dir }
            Write-Host "    拉取最新稳定版：$pkgId" -ForegroundColor White
            if ($s.noRelocate) {
                Write-Host '    [必要例外] MSIX 固定 C:\Program Files\WindowsApps，winget 不支持 --location' -ForegroundColor Yellow
            }
            else {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                Write-Host "    目标位置：$target" -ForegroundColor White
            }
            # winget 输出 UTF-8；PowerShell 5.1 默认按 OEM(GBK) 解码原生程序输出，会显示乱码。
            $oldConsole = [Console]::OutputEncoding
            $oldOutput = $OutputEncoding
            try {
                $utf8 = New-Object System.Text.UTF8Encoding($false)
                [Console]::OutputEncoding = $utf8
                $OutputEncoding = $utf8
                # 安装规则：除 MSIX 例外，每条 install 都必须带 --location，绝不落到 C 盘默认位置
                $installArgs = @('install', '--id', $pkgId, '--source', 'winget',
                                 '--accept-package-agreements', '--accept-source-agreements')
                if (-not $s.noRelocate) { $installArgs += @('--location', $target) }
                Write-Host "    [winget] $($installArgs -join ' ')" -ForegroundColor DarkGray
                & winget @installArgs | Out-Host
                $installExit = $LASTEXITCODE
                # install 本身已含「已安装则尝试升级」，upgrade 的「找不到可用的升级」重复刷屏；
                # 这里只在真有升级动作时才把 upgrade 输出打出来。
                $upOut = @(& winget upgrade --id $pkgId --source winget --accept-package-agreements --accept-source-agreements 2>&1 | Out-String)
                $upText = $upOut -join "`n"
                if ($upText -match '已成功安装|已成功升级|Successfully installed|正在下载|正在启动程序包安装') {
                    Write-Host "    [winget upgrade] $pkgId" -ForegroundColor DarkGray
                    Write-Host $upText.Trim()
                }
                else { Write-Host "    [winget upgrade] $pkgId 已是最新" -ForegroundColor DarkGray }
            }
            finally {
                [Console]::OutputEncoding = $oldConsole
                $OutputEncoding = $oldOutput
            }
            if ($installExit -eq 0) { Write-Ok "$pkgId（未装则安装，已装则升到最新）" }
            elseif ($installExit -eq -1978335189) {
                # 0x8A15002B = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED：
                # 包已存在且无需升级，winget 用这个退出码表达「什么都没做」，不是失败。
                Write-Ok "$pkgId 已安装且已是最新（winget 未做变更）"
            }
            else { Write-Warning "    $pkgId 安装退出码 $installExit，详见上方 winget 输出判断是否真失败" }
            # 如实提示：--location 只对全新安装生效，不会把 C 盘已装的软件搬到 D 盘
            if (-not $s.noRelocate -and $target -and (Test-Path -LiteralPath $target)) {
                if (@(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                    Write-Host "    注意：目标目录为空且 winget 报「已安装」，说明该软件此前装在 C 盘；--location 不会迁移。" -ForegroundColor Yellow
                }
            }
            # 可选后处理：装完 EIM 后自动调用 eim install 装最新稳定版 ESP-IDF
            if ($s.postTool) {
                $tool = Resolve-Tool $s.postTool $eimFallback
                # winget portable 是同会话新装的，PATH 尚未刷新；再扫一次 WinGet 包目录兜底
                if (-not $tool) {
                    # --location 到 D 盘后，优先扫 D 盘目标目录，再退回 WinGet 默认包目录
                    foreach ($root in @($target, (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))) {
                        if ($root -and (Test-Path -LiteralPath $root)) {
                            $cand = Get-ChildItem -LiteralPath $root -Filter "$($s.postTool).exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($cand) { $tool = $cand.FullName; break }
                        }
                    }
                }
                if (-not $tool) {
                    Write-Warning "    未找到 $($s.postTool)：winget 便携包需重开终端刷新 PATH，重跑 -Only $($s.no) 即可继续。"
                    break
                }
                if ($s.eimConfig) {
                    # 关键修复：用官方 TOML 把工具链 / 缓存 / venv / 激活脚本全部钉到 D 盘。
                    # 只写 -p 会让它们默认落 C:\Espressif（实测 10.42 GB），违反安装规则。
                    $espRoot = Join-Path $WorkspaceRoot 'esp'
                    New-Item -ItemType Directory -Force -Path $espRoot | Out-Null
                    $cfg = New-EimConfig $espRoot
                    Write-Host "    D 盘配置：$cfg" -ForegroundColor White
                    Write-Host "    框架 / 工具链 / 缓存 / venv / 激活脚本 → $espRoot" -ForegroundColor White
                    $runArgs = @('install', '--config', $cfg)
                }
                else {
                    $runArgs = @($s.postArgs)
                }
                Write-Host "    执行 $($s.postTool) $($runArgs -join ' ')（非交互，装最新稳定版 ESP-IDF，需联网下载数 GB）" -ForegroundColor White
                & $tool @runArgs
                if ($LASTEXITCODE -eq 0) { Write-Ok 'ESP-IDF 最新稳定版安装完成（全部产物在 D 盘）' }
                else { Write-Warning "    $($s.postTool) 退出码 $LASTEXITCODE：检查上面的错误，或改用 eim wizard 交互安装" }
            }
            # Node.js 后处理：把 npm 的全局目录与缓存从 C 盘挪到 D 盘。
            # npm 默认 prefix=%APPDATA%\npm、cache=%LOCALAPPDATA%\npm-cache，全局装几个 CLI 就是几百 MB。
            # 这里写入用户级 .npmrc（npm config set 默认 --location=user），属性值指向 D 盘。
            if ($s.postNode) {
                $nodeExe = Join-Path $target 'node.exe'
                $npmCmd  = Join-Path $target 'npm.cmd'
                if ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npmCmd)) {
                    $npmGlobal = Join-Path $WorkspaceRoot 'tools\npm-global'
                    $npmCache  = Join-Path $WorkspaceRoot 'tools\npm-cache'
                    foreach ($d in @($npmGlobal, $npmCache)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
                    # npm 是 .cmd 包装的原生程序，stderr 有输出时在 Stop 模式下会抛异常，局部放宽
                    $prevEap = $ErrorActionPreference
                    $ErrorActionPreference = 'Continue'
                    try {
                        & $npmCmd config set prefix $npmGlobal --location=user 2>&1 | Out-Null
                        & $npmCmd config set cache  $npmCache  --location=user 2>&1 | Out-Null
                        $pNow = (& $npmCmd config get prefix 2>&1 | Select-Object -Last 1)
                        $cNow = (& $npmCmd config get cache  2>&1 | Select-Object -Last 1)
                        if ($pNow -and $cNow) {
                            Write-Ok "npm prefix = $pNow"
                            Write-Ok "npm cache  = $cNow"
                        } else {
                            Write-Warning '    npm config 读取失败：手动执行 npm config set prefix/cache 指向 D 盘'
                        }
                    } catch {
                        Write-Warning "    配置 npm 目录失败：$_（可手动 npm config set prefix $npmGlobal）"
                    } finally {
                        $ErrorActionPreference = $prevEap
                    }
                    Write-Host "    提示：全局命令目录 $npmGlobal 未加入 PATH（脚本不改 PATH）；需要全局 CLI 时手动加入，或直接用 npx。" -ForegroundColor Yellow
                    # 本机 PATH 里可能已有别的 node（WorkBuddy 内置 / nvm / 旧安装），先装的不一定先命中
                    $pathNodeCmd = Get-Command node -ErrorAction SilentlyContinue
                    $pathNode = if ($pathNodeCmd) { $pathNodeCmd.Source } else { '' }
                    if ($pathNode -and (-not $pathNode.Equals($nodeExe, [System.StringComparison]::OrdinalIgnoreCase))) {
                        Write-Host "    注意：当前 PATH 里的 node 是 $pathNode，不是本步骤刚装的 $nodeExe；" -ForegroundColor Yellow
                        Write-Host "          要让新版本生效，把 $target 放到 PATH 中更靠前的位置（或移除前一个 node）。" -ForegroundColor Yellow
                    }
                } else {
                    Write-Warning "    未找到 $nodeExe / npm.cmd：winget 可能把包装到了别处，检查 $target 是否为空。"
                }
            }
        }
        'qt-aqt' {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                Write-Warning '    未找到 winget：请先安装「应用安装程序 App Installer」，再用 -Only 18 重跑。'
                break
            }
            # 1) 安装 aqtinstall（走 Qt 官方镜像，免 Qt 账号，portable）
            $aqtTarget = Join-Path $InstallRoot 'aqtinstall'
            New-Item -ItemType Directory -Force -Path $aqtTarget | Out-Null
            Write-Host "    目标位置：$aqtTarget" -ForegroundColor White
            $oldConsole = [Console]::OutputEncoding
            $oldOutput = $OutputEncoding
            try {
                $utf8 = New-Object System.Text.UTF8Encoding($false)
                [Console]::OutputEncoding = $utf8
                $OutputEncoding = $utf8
                # 安装规则：portable 包同样 --location 落到 D 盘
                $aqtArgs = @('install', '--id', 'miurahr.aqtinstall', '--source', 'winget',
                             '--accept-package-agreements', '--accept-source-agreements',
                             '--location', $aqtTarget)
                Write-Host "    [winget] $($aqtArgs -join ' ')" -ForegroundColor DarkGray
                & winget @aqtArgs | Out-Host
                $upText = @(& winget upgrade --id miurahr.aqtinstall --source winget --accept-package-agreements --accept-source-agreements 2>&1 | Out-String) -join "`n"
                if ($upText -match '已成功安装|已成功升级|Successfully installed|正在下载') { Write-Host $upText.Trim() }
                else { Write-Host '    [winget upgrade] aqtinstall 已是最新' -ForegroundColor DarkGray }
            }
            finally {
                [Console]::OutputEncoding = $oldConsole
                $OutputEncoding = $oldOutput
            }
            # 2) 定位 aqt.exe（portable 同会话 PATH 未刷新时按兜底路径 + 包目录扫描）
            $aqt = $null
            foreach ($n in @('aqt', 'aqt_x64')) {
                $c = Get-Command $n -ErrorAction SilentlyContinue
                if ($c) { $aqt = $c.Source; break }
            }
            if (-not $aqt) {
                foreach ($p in $aqtFallback) { if (Test-Path -LiteralPath $p) { $aqt = $p; break } }
            }
            if (-not $aqt) {
                foreach ($root in @($aqtTarget, (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))) {
                    if ($root -and (Test-Path -LiteralPath $root)) {
                        $cand = Get-ChildItem -LiteralPath $root -Filter 'aqt*.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($cand) { $aqt = $cand.FullName; break }
                    }
                }
            }
            if (-not $aqt) {
                Write-Warning '    未找到 aqt.exe：重开终端刷新 PATH 后重跑 -Only 18。'
                break
            }
            Write-Ok "aqtinstall：$aqt"
            # 3) 所有产物只落 D 盘这一个根
            New-Item -ItemType Directory -Force -Path $QtRoot | Out-Null
            Write-Host "    Qt 安装根目录：$QtRoot" -ForegroundColor White
            # 4) 版本选择：实测坑 —— list-qt 返回的最大版本（6.12.0 / 6.11.x）在镜像上
            #    没有 Updates.xml，直接装必然 ERROR。必须按 --dry-run 逐个探测可装版本。
            $ver = $QtVersion
            if (-not $ver) {
                $verLines = @(& $aqt list-qt windows desktop 2>$null)
                $vers = @($verLines | ForEach-Object {
                    [regex]::Matches($_, '\b6\.\d+\.\d+\b') | ForEach-Object { $_.Value }
                } | Sort-Object -Unique | ForEach-Object { [version]$_ } | Sort-Object -Descending)
                if ($vers.Count -eq 0) {
                    Write-Warning '    aqt list-qt 未取到 6.x 版本（多为网络问题），检查后重跑 -Only 18。'
                    break
                }
                foreach ($cand in ($vers | Select-Object -First 8)) {
                    $cv = $cand.ToString()
                    Write-Host "    探测版本可用性：$cv" -ForegroundColor DarkGray
                    & $aqt install-qt windows desktop $cv win64_mingw -O $QtRoot -b $QtMirror --dry-run 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) { $ver = $cv; break }
                }
                if (-not $ver) {
                    Write-Warning '    前 8 个候选版本在镜像上都不可装，用 -QtVersion <版本> 显式指定后重跑 -Only 18。'
                    break
                }
            }
            Write-Host "    选定 Qt $ver / win64_mingw（镜像 $QtMirror）" -ForegroundColor White

            # 5) MinGW 工具包必须与该 Qt 版本配套，不能取编号最大的（实测 6.10.3 配 13.1.0，
            #    而 tools_mingw1510 属于更新的 Qt，下载还会 IncompleteRead 中断）。
            $probe = @(& $aqt install-qt windows desktop $ver win64_mingw -O $QtRoot -b $QtMirror --dry-run 2>&1)
            $m = [regex]::Match(($probe -join "`n"), 'MinGW-w64-x86_64-(\d+)\.(\d+)\.(\d+)')
            $mingwName = $null
            if ($m.Success) {
                $mingwName = 'tools_mingw{0}{1}0' -f $m.Groups[1].Value, $m.Groups[2].Value
            }
            $toolLines = @(& $aqt list-tool windows desktop 2>$null)
            if (-not $mingwName -or $toolLines -notmatch $mingwName) {
                # 回退：取与 runtime 最接近且编号不超过它的候选
                $cands = @($toolLines | ForEach-Object { [regex]::Matches($_, 'tools_mingw\d+') | ForEach-Object { $_.Value } } | Sort-Object -Unique)
                if ($cands.Count -gt 0) { $mingwName = $cands | Sort-Object | Select-Object -Last 1 }
            }

            # 6) 安装（每条命令带 -O $QtRoot + -b 镜像 + 超时；失败重试 2 次）
            $failures = New-Object System.Collections.ArrayList
            function Invoke-Aqt([string[]]$AqtArgs, [string]$Label) {
                for ($i = 1; $i -le 3; $i++) {
                    Write-Host "    $Label（第 $i/3 次）" -ForegroundColor White
                    & $aqt @AqtArgs
                    if ($LASTEXITCODE -eq 0) { return $true }
                    Write-Warning "    $Label 退出码 $LASTEXITCODE，稍后重试"
                }
                return $false
            }
            $qtOk = Invoke-Aqt @('install-qt', 'windows', 'desktop', $ver, 'win64_mingw', '-O', $QtRoot, '-b', $QtMirror, '--timeout', '30') "安装 Qt $ver"
            if (-not $qtOk) { [void]$failures.Add("Qt $ver 库") }
            if ($mingwName) {
                $mgOk = Invoke-Aqt @('install-tool', 'windows', 'desktop', $mingwName, '-O', $QtRoot, '-b', $QtMirror, '--timeout', '30') "安装 MinGW $mingwName"
                if (-not $mgOk) { [void]$failures.Add("MinGW $mingwName") }
            }
            else { Write-Warning '    未解析到配套 MinGW 工具包，可手工 aqt list-tool windows desktop 查看。' }
            if ($toolLines -match 'tools_qtcreator') {
                $qcOk = Invoke-Aqt @('install-tool', 'windows', 'desktop', 'tools_qtcreator', '-O', $QtRoot, '-b', $QtMirror, '--timeout', '30') '安装 Qt Creator'
                if (-not $qcOk) { [void]$failures.Add('Qt Creator') }
            }

            # 7) 唯一成功判据：qmake.exe 真实存在。不再无条件打印「完成」。
            $qmake = Get-ChildItem -LiteralPath $QtRoot -Filter 'qmake.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($qmake -and $failures.Count -eq 0) {
                Write-Ok "Qt $ver 已装到 $QtRoot（$($qmake.FullName)）"
            }
            else {
                Write-Warning "    Qt 未完整安装：失败项 = $($failures -join '、')；qmake = $(if ($qmake) { $qmake.FullName } else { '未找到' })"
                Write-Warning '    修好网络后重跑 -Only 18；已下载内容会复用，不会重复下载。'
            }
        }
        'vscode-extensions' {
            $code = Resolve-Tool 'code' $codeFallback
            if (-not $code) { Write-Warning '    未找到 code：先执行步骤 1，或重开终端刷新 PATH。'; break }
            $ok = 0; $fail = 0
            foreach ($id in $Extensions) {
                & $code --install-extension $id --force | Out-Null
                if ($LASTEXITCODE -eq 0) { $ok++ } else { $fail++; Write-Warning "    扩展失败：$id" }
            }
            Write-Ok "插件安装：成功 $ok，失败 $fail（共 $($Extensions.Count) 个）"
        }
        'git-config' {
            $git = Resolve-Tool 'git' $gitFallback
            if (-not $git) { Write-Warning '    未找到 git：先执行步骤 3，或重开终端刷新 PATH。'; break }
            foreach ($g in $GitSettings) {
                & $git config --global $g.Key $g.Value
            }
            Write-Ok "已写入 $($GitSettings.Count) 项全局配置（未生成任何文件引用）"
        }
        'vscode-idf-config' {
            $code = Resolve-Tool 'code' $codeFallback
            if (-not $code) { Write-Warning '    未找到 code：先执行步骤 1，或重开终端刷新 PATH。'; break }
            $espRoot = Join-Path $WorkspaceRoot 'esp'
            # 探测最新 esp-idf 版本目录（与 Invoke-Verify 同源逻辑，取最新）
            $idfDir = Get-ChildItem -LiteralPath $espRoot -Directory -ErrorAction SilentlyContinue |
                      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'esp-idf\tools\idf_tools.py') } |
                      Sort-Object Name | Select-Object -Last 1
            if (-not $idfDir) {
                Write-Warning "    未找到已装的 ESP-IDF（步骤 17 未执行？）。先跑 -Only 17 再跑本步骤。"
                break
            }
            $idfPath = Join-Path $idfDir.FullName 'esp-idf'
            # 探测 venv：tools\python\v<ver>\venv\Scripts\python.exe
            $pyDir = Get-ChildItem -LiteralPath (Join-Path $espRoot 'tools\python') -Directory -ErrorAction SilentlyContinue |
                     Sort-Object Name | Select-Object -Last 1
            $pyBin = if ($pyDir) { Join-Path $pyDir.FullName 'venv\Scripts\python.exe' } else { $null }
            if (-not ($pyBin -and (Test-Path -LiteralPath $pyBin))) {
                Write-Warning "    未找到 ESP-IDF 自带 Python venv（$pyBin）；仍写入 idf.customExtraVars，pythonBinPath 跳过。"
                $pyBin = $null
            }
            # 修复 eim_idf.json：迁移到 D 盘后，安装记录里的 idfToolsPath/python/activationScript 仍指向已删的 C:\Espressif，
            # 扩展 2.3.0 把 idfToolsPath 1:1 当 IDF_TOOLS_PATH 传给 idf_tools.py export，错值会致 cmake not found。
            # 注：idfToolsPath 必须是容器根（如 D:\Dev\esp），不是 D:\Dev\esp\tools（后者反而 no installed versions）。
            $eimJson = Join-Path $espRoot 'tools\eim_idf.json'
            if (Test-Path -LiteralPath $eimJson) {
                try {
                    $eim = Get-Content -LiteralPath $eimJson -Raw -Encoding UTF8 | ConvertFrom-Json
                    $fixed = $false
                    if ($eim.idfInstalled) {
                        # 多版本关键：每条记录必须按自己的 name 推导 python / 激活脚本，
                        # 不能统一取「最新版本」那一份，否则 v5.4.3 会被写成 v6.1 的 venv，直接坏。
                        foreach ($inst in $eim.idfInstalled) {
                            $name = $inst.name
                            if ($inst.idfToolsPath -and $inst.idfToolsPath -ne $espRoot) {
                                $inst.idfToolsPath = $espRoot; $fixed = $true
                            }
                            $expPy = Join-Path $espRoot "tools\python\$name\venv\Scripts\python.exe"
                            if ((Test-Path -LiteralPath $expPy) -and $inst.python -ne $expPy) {
                                $inst.python = $expPy; $fixed = $true
                            }
                            $expAct = Join-Path $espRoot "tools\Microsoft.$name.PowerShell_profile.ps1"
                            if ((Test-Path -LiteralPath $expAct) -and $inst.activationScript -ne $expAct) {
                                $inst.activationScript = $expAct; $fixed = $true
                            }
                            if ($inst.path) {
                                $normPath = [System.IO.Path]::GetFullPath($inst.path)
                                if ($inst.path -ne $normPath) { $inst.path = $normPath; $fixed = $true }
                            }
                        }
                    }
                    if ($fixed) {
                        [System.IO.File]::WriteAllText($eimJson, ($eim | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
                        Write-Ok "已修复 $eimJson（idfToolsPath=$espRoot；python/激活脚本按各版本自身推导）"
                    } else {
                        Write-Host '    eim_idf.json 路径已正确，无需修改。' -ForegroundColor DarkGray
                    }
                    # EIM 默认还会往 C:\Espressif\tools\eim_idf.json 写一份；把 D 盘这份同步过去，
                    # 让裸命令 `eim list / eim select` 与 IDE 看到同一份记录（避免两边分叉）。
                    $cJson = 'C:\Espressif\tools\eim_idf.json'
                    if (Test-Path -LiteralPath (Split-Path -Parent $cJson)) {
                        try {
                            Copy-Item -LiteralPath $eimJson -Destination $cJson -Force
                            Write-Host "    已同步安装记录到 $cJson（供 eim list 使用）" -ForegroundColor DarkGray
                        } catch { }
                    }
                } catch {
                    Write-Warning "    修复 eim_idf.json 失败：$_（可手动把 $eimJson 的 idfToolsPath 改为 $espRoot）"
                }
            } else {
                Write-Warning "    未找到 $eimJson；请先执行步骤 17 安装 ESP-IDF。"
            }
            # idf.py 在 $IDF_TOOLS_PATH 根目录找 espidf.constraints.v<版本>.txt，而 EIM 把它放在 ...\tools\ 下。
            # 缺了会报 "doesn't exist. Perhaps you've forgotten to run the install scripts"（VSCode 里也同样报）。
            $cfiles = Get-ChildItem -LiteralPath (Join-Path $espRoot 'tools') -Filter 'espidf.constraints.*.txt' -File -ErrorAction SilentlyContinue
            foreach ($c in $cfiles) {
                $dstFile = Join-Path $espRoot $c.Name
                if (-not (Test-Path -LiteralPath $dstFile)) {
                    Copy-Item -LiteralPath $c.FullName -Destination $dstFile -Force
                    Write-Ok "已补 constraints 到容器根：$($c.Name)"
                }
            }
            # 读/合并 VSCode 全局 settings.json（保留已有键，不覆盖整个文件）
            # 兼容 PowerShell 5.1：不用 -AsHashtable（5.1 不支持会报参数错误），改用 PSCustomObject + Add-Member -Force
            $vsSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
            $vsDir = Split-Path -Parent $vsSettings
            if (-not (Test-Path -LiteralPath $vsDir)) { New-Item -ItemType Directory -Force -Path $vsDir | Out-Null }
            $obj = $null
            if (Test-Path -LiteralPath $vsSettings) {
                try { $obj = Get-Content -LiteralPath $vsSettings -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $obj = $null }
            }
            if (-not $obj) { $obj = New-Object PSObject }
            # 主修复：扩展 2.3.0 已移除 idf.espIdfPath/idf.toolsPath/idf.pythonBinPath，改用 EIM + idf.customExtraVars。
            # IDF_TOOLS_PATH 的取值优先级为 customExtraVars > 缓存配置 > 进程env > 空；为空时 idf_tools.py export
            # 会回退到不存在的 ~/.espressif，报 "tool cmake has no installed versions" → cmake not found。
            # 多版本共存：只钉「共享」的 IDF_TOOLS_PATH（所有版本共用一个工具根），
            # 刻意不钉 IDF_PATH / IDF_PYTHON_ENV_PATH —— 它们必须随 eim_idf.json 的选中版本变化，
            # 一旦钉死就会把所有项目锁在同一版本，idf-use 切版本也随之失效。
            # 合并而非整体替换：用户可能自建了其它 customExtraVars（例如 IDF_CCACHE_ENABLE），
            # 整体覆盖会静默清掉它们。只有 IDF_TOOLS_PATH 这一项由脚本掌管。
            $customVars = New-Object PSObject
            $prevVars = $obj.PSObject.Properties['idf.customExtraVars']
            if ($prevVars -and $prevVars.Value) {
                foreach ($p in $prevVars.Value.PSObject.Properties) {
                    $customVars | Add-Member -MemberType NoteProperty -Name $p.Name -Value $p.Value -Force
                }
            }
            $customVars | Add-Member -MemberType NoteProperty -Name 'IDF_TOOLS_PATH' -Value $espRoot -Force
            $obj | Add-Member -MemberType NoteProperty -Name 'idf.customExtraVars' -Value $customVars -Force
            # 清掉 2.3.0 已不读的旧键，避免误以为它们是「当前版本」而手改错（多版本下尤其误导）
            foreach ($deadKey in @('idf.espIdfPath', 'idf.toolsPath', 'idf.pythonBinPath')) {
                if ($obj.PSObject.Properties[$deadKey]) { $obj.PSObject.Properties.Remove($deadKey) }
            }
            # 备份：钉死 eim_idf.json 路径，避免扩展回退到 Windows 默认的 C:\Espressif\tools\eim_idf.json
            $obj | Add-Member -MemberType NoteProperty -Name 'idf.eimIdfJsonPath' -Value $eimJson -Force
            if (-not $obj.'terminal.integrated.profiles.windows') {
                $obj | Add-Member -MemberType NoteProperty -Name 'terminal.integrated.profiles.windows' -Value (New-Object PSObject) -Force
            }
            # 终端 profile 走 idf-use -Default：按 eim_idf.json 的选中版本激活，不再写死某一版。
            # 显式带 -EspRoot：换机用 -WorkspaceRoot 改盘时，新终端不必依赖 IDF_TOOLS_PATH 等环境变量先就位。
            $idfUseScript = Join-Path $env:USERPROFILE 'idf-use.ps1'
            $obj.'terminal.integrated.profiles.windows' | Add-Member -MemberType NoteProperty -Name 'ESP-IDF' -Value @{
                source = 'PowerShell'
                args   = @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $idfUseScript, '-Default', '-EspRoot', $espRoot)
            } -Force
            [System.IO.File]::WriteAllText($vsSettings, ($obj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
            Write-Ok "已钉 idf.customExtraVars: IDF_TOOLS_PATH=$espRoot（共享工具根；IDF_PATH/venv 由 eim 选中版本决定）"
            Write-Ok "已钉 idf.eimIdfJsonPath = $eimJson；「ESP-IDF」终端 profile → idf-use -Default"
            Write-Host '    重启 VSCode 后，打开 ESP 项目用 Build 按钮或「ESP-IDF」终端即可编译。' -ForegroundColor DarkGray
            Write-Host '    多版本切换：在终端敲 idf-use 5.4.3（详见 README 5.8）。' -ForegroundColor DarkGray
        }
        'eim-multi' {
            # 与步骤 17 共用同一个 EIM TOML（路径全钉 D 盘），只额外用 -i 指定要装的版本。
            # EIM 会按「path + 版本名」派生 v<版本>\esp-idf，因此多版本天然分目录、可共存。
            $espRoot = Join-Path $WorkspaceRoot 'esp'
            New-Item -ItemType Directory -Force -Path $espRoot | Out-Null
            $cfg = New-EimConfig $espRoot
            $tool = Resolve-Tool 'eim' $eimFallback
            if (-not $tool) {
                foreach ($root in @((Join-Path $InstallRoot 'EIM'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))) {
                    if ($root -and (Test-Path -LiteralPath $root)) {
                        $cand = Get-ChildItem -LiteralPath $root -Filter 'eim.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($cand) { $tool = $cand.FullName; break }
                    }
                }
            }
            if (-not $tool) { Write-Warning '    未找到 eim：先执行步骤 17，或重开终端刷新 PATH 后重跑 -Only 20。'; break }
            $vers = @($s.idfVersions)
            if ($vers.Count -eq 0) { Write-Warning '    清单里没有配置 idfVersions，跳过。'; break }
            # 已装的版本跳过，避免重复下载
            $todo = @()
            foreach ($v in $vers) {
                $dir = Join-Path $espRoot "$v\esp-idf"
                if (Test-Path -LiteralPath (Join-Path $dir 'tools\idf_tools.py')) {
                    Write-Host "    $v 已存在，跳过：$dir" -ForegroundColor DarkGray
                } else { $todo += $v }
            }
            if ($todo.Count -eq 0) { Write-Ok "目标版本均已安装：$($vers -join ', ')"; break }
            Write-Host "    D 盘配置：$cfg" -ForegroundColor White
            Write-Host "    待装版本：$($todo -join ', ') → $espRoot\v<版本>\esp-idf（共享工具根 $espRoot\tools）" -ForegroundColor White
            Write-Host "    执行 eim install -i $($todo -join ',')（非交互，需联网下载数 GB）" -ForegroundColor White
            # 关键：EIM 默认把安装记录写到 C:\Espressif\tools\eim_idf.json，
            # 而 VSCode 扩展读的是 idf.eimIdfJsonPath 钉死的 D 盘那份 —— 不指回来就会出现
            # 「装好了但 IDE/新版本环境读不到」的情况；同时避免 C 盘再长出目录。
            # 镜像：GitHub 直连实测会 git clone exit 128 / schannel closed abruptly，必须走国内镜像。
            $jsonDir = Join-Path $espRoot 'tools'
            New-Item -ItemType Directory -Force -Path $jsonDir | Out-Null
            $mirrorArgs = @(
                '--esp-idf-json-path', $jsonDir
                '--idf-mirror', 'https://git.espressif.com.cn'
                '--repo-stub', 'Espressif/esp-idf'
                '-m', 'https://dl.espressif.cn/github_assets'
            )
            & $tool install --config $cfg -i ($todo -join ',') @mirrorArgs
            $exit = $LASTEXITCODE
            if ($exit -eq 0) {
                Write-Ok "已安装：$($todo -join ', ')（与已有版本共存于 $espRoot）"
                $jsonFile = Join-Path $jsonDir 'eim_idf.json'
                if (Test-Path -LiteralPath $jsonFile) {
                    Write-Ok "安装记录已落在 D 盘：$jsonFile"
                } else {
                    Write-Warning "    $jsonDir 下未生成 eim_idf.json：请检查 C:\Espressif\tools\eim_idf.json 并合并到 D 盘。"
                }
                if (Test-Path -LiteralPath 'C:\Espressif\tools') {
                    $cLeft = @(Get-ChildItem -LiteralPath 'C:\Espressif\tools' -Force -ErrorAction SilentlyContinue)
                    if ($cLeft.Count -gt 0) {
                        Write-Warning "    C:\Espressif\tools 仍有 $($cLeft.Count) 项（EIM 默认索引位置，仅元数据可接受；不应有工具链）。"
                    }
                }
            }
            else { Write-Warning "    eim 退出码 $exit：看上面的错误；单个版本失败可改用 -Only 20 前先确认 tag 存在（git ls-remote --tags）" }
        }
        'idf-switch' {
            # 切换器源文件与 bootstrap.ps1 同目录（仓库里成对分发），复制到用户目录后注册裸命令
            $src = Join-Path $PSScriptRoot 'idf-use.ps1'
            $dst = Join-Path $env:USERPROFILE 'idf-use.ps1'
            if (-not (Test-Path -LiteralPath $src)) {
                Write-Warning "    未找到 $src；请把它和 bootstrap.ps1 放在同一目录（仓库 F:\githup\vscode\idf-use.ps1）。"
                break
            }
            # 同目录部署时 src == dst，Copy-Item 会报「无法使用项其自身覆盖该项」，需跳过
            $srcFull = [System.IO.Path]::GetFullPath($src)
            $dstFull = [System.IO.Path]::GetFullPath($dst)
            if ($srcFull -ieq $dstFull) {
                Write-Host "    切换器已在目标位置，跳过复制：$dst" -ForegroundColor DarkGray
                Write-Host '    提示：当前运行的就是用户目录副本；仓库更新后想在用户目录生效，请在仓库目录再跑一次 -Only 21。' -ForegroundColor DarkGray
            } else {
                Copy-Item -LiteralPath $src -Destination $dst -Force
                Write-Ok "已部署切换器：$dst"
            }
            # 注册别名（幂等：已注册则跳过）
            # 注意：$PROFILE 必须存成 UTF-8 BOM，否则 PowerShell 5.1 按 ANSI 解析会把中文注释读成乱码；
            # 这里注释与标记一律用 ASCII，最稳。
            $profilePath = $PROFILE
            $profileDir = Split-Path -Parent $profilePath
            if (-not (Test-Path -LiteralPath $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
            # v2：额外把实际容器根写进 $env:IDF_USE_ROOT。
            # 原因：Set-Alias 无法携带参数，换机用 -WorkspaceRoot 改盘后 idf-use 无法靠参数得知新根，
            # 而新机在步骤 19/20 之前没有用户级 IDF_TOOLS_PATH 可探测 —— 会误判「没有安装」。
            $marker = '# ESP-IDF multi-version switcher (bootstrap step 21) v2'
            $markerV1 = '# ESP-IDF multi-version switcher (bootstrap step 21)'
            $existing = if (Test-Path -LiteralPath $profilePath) { Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 } else { '' }
            if ($existing -notmatch [regex]::Escape($marker)) {
                # 旧版（v1）块是追加在文件末尾的，先整段裁掉再写 v2，避免两段并存/重复注册
                $idx = $existing.IndexOf($markerV1)
                if ($idx -ge 0) { $existing = $existing.Substring(0, $idx) }
                $espRootForProfile = Join-Path $WorkspaceRoot 'esp'
                $block = @"

$marker
`$idfUseScript = Join-Path `$env:USERPROFILE 'idf-use.ps1'
`$env:IDF_USE_ROOT = '$espRootForProfile'
if (Test-Path -LiteralPath `$idfUseScript) {
    Set-Alias -Name 'idf-use' -Value `$idfUseScript -Scope Global -Force
}
"@
                $merged = $existing.TrimEnd() + "`r`n" + (($block -replace "`r`n", "`n") -replace "`n", "`r`n") + "`r`n"
                [System.IO.File]::WriteAllText($profilePath, $merged, (New-Object System.Text.UTF8Encoding($true)))
                Write-Ok "已在 $profilePath 注册 idf-use 别名 + IDF_USE_ROOT=$espRootForProfile（UTF-8 BOM 保存）"
            } else {
                Write-Host "    $profilePath 已注册 idf-use（v2），跳过。" -ForegroundColor DarkGray
            }
            Write-Host '    重开终端后可直接敲：idf-use -List / idf-use 5.4.3 / idf-use -Current' -ForegroundColor DarkGray
        }
        'dirs' {
            foreach ($sub in $s.dirs) {
                $p = Join-Path $WorkspaceRoot $sub
                New-Item -ItemType Directory -Force -Path $p | Out-Null
                Write-Ok $p
            }
        }
        'manual' {
            Write-Host "    人工步骤：$($s.detail)" -ForegroundColor Yellow
            $i = 1
            foreach ($h in $s.howto) {
                Write-Host "      $i) $h" -ForegroundColor Yellow
                $i++
            }
            [void]$manualPending.Add([int]$s.no)
        }
        'check' { Invoke-Verify }
        default { Write-Warning "    未知方式：$($s.kind)，请检查清单" }
    }

    if ($s.check -and $s.kind -ne 'manual') { Write-Hint $s.check }
    $done++
}

Write-Host "`n[完成] 共执行 $done 步。" -ForegroundColor Green
if ($manualPending.Count -gt 0) {
    Write-Host "[待人工] 步骤编号：$($manualPending -join ', ')" -ForegroundColor Yellow
}
Write-Host '[提示] -All 安装所有 / -Only <编号> 单步 / -Help 全部指令' -ForegroundColor DarkGray
