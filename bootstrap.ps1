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
)

# ============================================================
# 二、VSCode 插件清单（加减插件只改这里）
# ============================================================
$Extensions = @(
    'ms-vscode.cpptools'
    'ms-vscode.cmake-tools'
    'twxs.cmake'
    'espressif.esp-idf-extension'
    'ms-vscode.hexeditor'
    'eamodio.gitlens'
    'ms-vscode.powershell'
    'ms-python.python'
    'redhat.vscode-yaml'
    'EditorConfig.EditorConfig'
    'yzhang.markdown-all-in-one'
    'PKief.material-icon-theme'
    'ms-ceintl.vscode-language-pack-zh-hans'   # VSCode 中文（简体）语言包
    'tencent-cloud.coding-copilot'             # 腾讯云代码助手 CodeBuddy（WorkBuddy 是独立客户端，无 VSCode 插件）
)

# 插件用途对照：只用于 -List 展示，安装仍按 $Extensions 顺序执行
$ExtensionLabels = @{
    'ms-vscode.cpptools'                     = 'C/C++ 智能提示与调试'
    'ms-vscode.cmake-tools'                  = 'CMake 构建集成'
    'twxs.cmake'                             = 'CMake 语法高亮'
    'espressif.esp-idf-extension'            = 'ESP-IDF 开发（编译/烧录/监视）'
    'ms-vscode.hexeditor'                    = '二进制 / 固件十六进制查看'
    'eamodio.gitlens'                        = 'Git 行级溯源与提交对比'
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
    $espRoot = Join-Path $WorkspaceRoot 'esp'
    $idfDir = Get-ChildItem -LiteralPath $espRoot -Directory -ErrorAction SilentlyContinue |
              Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'esp-idf\tools\idf_tools.py') } |
              Select-Object -First 1
    $idfTools = Get-ChildItem -LiteralPath (Join-Path $espRoot 'tools') -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'xtensa|riscv|cmake|ninja' } | Select-Object -First 1
    [void]$r.Add([pscustomobject]@{ Item = 'ESP-IDF 框架'; Status = $(if ($idfDir) { 'PASS' } else { 'FAIL' }); Detail = $(if ($idfDir) { $idfDir.FullName } else { "$espRoot 下未找到已装版本（步骤 17）" }) })
    [void]$r.Add([pscustomobject]@{ Item = 'ESP-IDF 工具链'; Status = $(if ($idfTools) { 'PASS' } else { 'FAIL' }); Detail = $(if ($idfTools) { "$espRoot\tools 已落地" } else { "$espRoot\tools 未找到（旧版脚本会误落 C:\Espressif）" }) })

    # Qt：装到 D 盘但未必加了 PATH，按目录扫 qmake.exe / mingw32-make.exe，不只看 Get-Command
    $qtQmake = $null; $qtMake = $null
    if (Test-Path -LiteralPath $QtRoot) {
        $qtQmake = Get-ChildItem -LiteralPath $QtRoot -Filter 'qmake.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $qtMake  = Get-ChildItem -LiteralPath $QtRoot -Filter 'mingw32-make.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    [void]$r.Add([pscustomobject]@{ Item = 'Qt qmake'; Status = $(if ($qtQmake) { 'PASS' } else { 'FAIL' }); Detail = $(if ($qtQmake) { $qtQmake.FullName } else { "$QtRoot 下未找到 qmake.exe（步骤 18 未成功）" }) })
    [void]$r.Add([pscustomobject]@{ Item = 'Qt MinGW'; Status = $(if ($qtMake) { 'PASS' } else { 'FAIL' }); Detail = $(if ($qtMake) { $qtMake.FullName } else { "$QtRoot 下未找到 mingw32-make.exe" }) })

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
