# Windows 开发环境一键搭建方案

> 面向嵌入式 / Qt 开发的 Windows 10/11 环境复现方案。
> 目标：**换一台电脑，只跑一条命令，把开发环境按同一套规则装好。**
> 核心是一个自包含单文件脚本 `bootstrap.ps1` + 一份编号安装清单，不做老机采样、不做系统镜像。

---

## 一、方案定位

| 项目 | 说明 |
|---|---|
| 交付物 | `bootstrap.ps1`（主脚本，自包含，不依赖同目录任何文件）+ `idf-use.ps1`（ESP-IDF 多版本切换器，步骤 21 部署） |
| 驱动方式 | 脚本顶部 `$Steps` 编号清单（当前 23 步），脚本按清单逐项执行 |
| 软件版本 | **不钉版本号**，winget / EIM / aqt 自动取最新稳定版，重复执行幂等 |
| 适用系统 | Windows 10/11，Windows PowerShell 5.1 或 PowerShell 7 |
| 人工收尾 | 步骤 11–15（工具链、驱动、SSH 凭据、代码仓库）只打印操作，不自动执行 |
| 验收 | 步骤 16 冒烟校验，强制排在最后执行 |

**为什么不用别的方案**

| 方案 | 一致性 | 维护成本 | 结论 |
|---|---|---|---|
| 手写清单照着装 | 低，易漂移 | 低 | 一年换一次机可以，多机不行 |
| **清单驱动脚本（本方案）** | **高** | **低** | **多机、常重装、Windows 场景最优** |
| Boxstarter / Chocolatey + DSC | 高 | 中高 | 企业批量装机才值得 |
| 系统镜像克隆 | 最高 | 高、绑硬件 | 固定机型专用 |
| devcontainer / Codespaces | 高 | 中 | 串口烧录、USB 穿透差，嵌入式不适用 |

---

## 二、软件安装规则（强制，2026-11-14 起）

1. **软件本体 → `D:\Program Files`；工具链 / 仓库 / 编译产物 / 数据 → `D:\Dev`。非必要绝不装 C 盘。**
2. **任何安装 / 配置命令必须显式带目标路径参数**，禁止只写 `winget install --id ...`，禁止接受安装器默认的 `C:\Program Files`、`%LOCALAPPDATA%\Programs`、`C:\Qt`、`C:\esp`。

| 安装器 | 显式路径参数 | 本方案示例 |
|---|---|---|
| winget | `--location` | `winget install --id Git.Git --location "D:\Program Files\Git"` |
| ESP-IDF EIM | TOML 配置（见第五节） | `eim install --config D:\Dev\esp\eim-config.toml` |
| Qt aqtinstall | `-O / --outputdir` | `aqt install-qt ... -O "D:\Dev\tools\Qt"` |
| Qt 官方在线安装器 | `--root` | `qt-unified-windows-x64-online.exe --root "D:\Dev\tools\Qt" ...` |
| 官方 MSI | `INSTALLFOLDER` / `TARGETDIR` | `msiexec /i ... INSTALLFOLDER="D:\Program Files\..."` |
| VSCode / Git（Inno） | `--override "/DIR=..."` | 必要时替代 winget `--location` |

3. **必要例外必须显式说明，不得假装装到了 D 盘**；遇到例外优先找 MSI / 便携版等可改路径的替代方案。
4. **配置类操作同样优先 D 盘**：环境变量（`IDF_PATH` / `IDF_TOOLS_PATH` / `QTDIR`）、下载缓存、临时目录、工具链输出目录。
5. **换机无 D 盘**时先询问目标盘符，或用 `-InstallRoot` / `-WorkspaceRoot` 显式覆盖，**不静默回退 C 盘**。

### 本方案的必要例外（如实列出）

| 例外 | 原因 |
|---|---|
| 步骤 4 PowerShell 7、步骤 5 Windows Terminal | MSIX / Appx 包固定 `C:\Program Files\WindowsApps`，winget `--location` 无效 |
| `winget --location` 对**已安装**软件 | 仅对全新安装生效，upgrade 不会把 C 盘已装软件迁移到 D 盘；要迁就先卸载再装 |
| EIM 索引文件 `eim_idf.json` | 默认 `C:\Espressif\tools`，仅几 KB；迁走会让 `eim list` / `select` 等命令都得带额外参数，得不偿失 |
| 步骤 22 会修改用户 PATH | npm 全局 CLI 目录（`D:\Dev\tools\npm-global`）不加 PATH 就敲不出来，npm 自己不会加。这是脚本**唯一**主动改 PATH 的地方：只追加自己一条目录、幂等去重、保留注册表值类型，不删改他人条目 |
| `~\.npmrc`（npm 用户配置） | 配置文件本身很小且必须在用户目录，但**内容**（prefix / cache）全部指向 D 盘 |
| 步骤 23 MobaXterm 用绿色版 | 官方 MSI 是 per-machine 安装，装到非系统盘需管理员提权，且 winget 的 `--location` 对它无效（实测仍落 C 盘 85 MB）。绿色版文件完整、无注册表写入、卸载即删目录 |

---

## 三、快速开始

### 一次性准备（每台新机只做一次）

```powershell
# 1) 允许运行本地脚本（用户级、持久、可撤销）
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force

# 2) 把 bootstrap.ps1 放到用户主目录，并在 $PROFILE 注册别名，
#    这样提示符在任意目录都能裸敲 bootstrap.ps1
#    PowerShell 5.1: Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
#    PowerShell 7:   Documents\PowerShell\Microsoft.PowerShell_profile.ps1
#    profile 内容：
#      Set-Alias -Name 'bootstrap.ps1' -Value (Join-Path $env:USERPROFILE 'bootstrap.ps1') -Scope Global
```

不注册别名也可以，在脚本所在目录用 `.\bootstrap.ps1 -List`。

### 全部指令（裸命令，不含任何路径）

| 指令 | 作用 |
|---|---|
| `bootstrap.ps1 -List` | 查看 23 步清单 + 16 个插件明细 + 安装规则 + 指令表 |
| `bootstrap.ps1 -All` | **安装所有**：执行全部 23 步 |
| `bootstrap.ps1` | 同 `-All` |
| `bootstrap.ps1 -Only 1,2,3` | 只跑指定步骤（单步写 `-Only 17`） |
| `bootstrap.ps1 -Only 16` | 单独跑冒烟校验 |
| `bootstrap.ps1 -Help` | 只看指令表 |
| `bootstrap.ps1 -WorkspaceRoot <目录> -All` | 换机改工作根目录（默认 `D:\Dev`） |
| `bootstrap.ps1 -InstallRoot <目录> -All` | 换机改软件安装根（默认 `D:\Program Files`） |
| `bootstrap.ps1 -QtVersion 6.10.3 -Only 18` | 钉 Qt 版本（留空则自动探测镜像上可装版本） |
| `bootstrap.ps1 -QtMirror <镜像> -Only 18` | 换 Qt 下载镜像 |

`-All` 与 `-Only` 互斥，同时写会拒绝执行，避免手滑触发全量安装。

### 建议的首次执行顺序

```
bootstrap.ps1 -List            # 先看清单
bootstrap.ps1 -Only 1,2,3      # 先验证 VSCode / 插件 / Git
bootstrap.ps1 -All             # 全量（会联网下载数 GB，可能弹 UAC）
bootstrap.ps1 -Only 16         # 复核校验表
```

第 17 步 ESP-IDF、第 18 步 Qt 各需下载数 GB，**建议单跑** `-Only 17`、`-Only 18`；
第 20 步（6.0.2 / 5.4.3 双版本）同样要下载数 GB，**单跑** `-Only 20`。

---

## 四、完整安装清单与逐步流程

| # | 安装项 | 方式 | 目标位置 | 验证 |
|---|---|---|---|---|
| 1 | 最新版 VSCode | winget | `D:\Program Files\Microsoft VS Code` | `code --version` |
| 2 | VSCode 插件（16 个） | `code --install-extension` | VSCode 用户扩展目录 | `code --list-extensions` |
| 3 | 最新版 Git | winget | `D:\Program Files\Git` | `git --version` |
| 4 | 最新版 PowerShell 7 | winget（MSIX 例外） | `C:\Program Files\WindowsApps` | `pwsh --version` |
| 5 | 最新版 Windows Terminal | winget（MSIX 例外） | `C:\Program Files\WindowsApps` | `wt --version` |
| 6 | 最新版 7-Zip | winget | `D:\Program Files\7-Zip` | `winget list --id 7zip.7zip` |
| 7 | 最新版 Python 3.12 | winget | `D:\Program Files\Python312` | `python --version` |
| 8 | PuTTY（串口调试） | winget | `D:\Program Files\PuTTY` | `winget list --id PuTTY.PuTTY` |
| 9 | 配置 Git 全局项 | `git config --global` | 12 项，值里无任何路径 | `git config --global --list` |
| 10 | 创建统一工作目录 | `New-Item` | `D:\Dev\{repos,tools,esp,tmp}` | `dir D:\Dev` |
| 11 | ESP-IDF v6.0 工具链 | 人工 | `D:\Dev\esp\v6.0` | `idf.py --version` |
| 12 | Qt6 + MinGW（官方完整 IDE） | 人工 | `D:\Dev\tools\Qt` | `qmake --version` |
| 13 | USB 串口 / JTAG 驱动 | 人工 | 跟硬件走 | 设备管理器 COM 口 |
| 14 | 恢复 SSH 密钥并验证 GitLab | 人工 | `%USERPROFILE%\.ssh\` | `ssh -T git@...` |
| 15 | 克隆项目仓库并切分支 | 人工 | `D:\Dev\repos` | `git status` |
| 16 | 冒烟校验 | 自动（强制最后） | — | PASS / WARN / FAIL 表 |
| 17 | 最新版 ESP-IDF（EIM 自动） | winget + `eim install` | `D:\Dev\esp`（全部产物） | `eim list` |
| 18 | 最新版 Qt6 + MinGW（aqt 自动） | winget + `aqt` | `D:\Dev\tools\Qt` | qmake.exe 真实存在 |
| 19 | 配置 VSCode ESP-IDF 集成路径 | 写 VSCode settings | `idf.*` 钉到 `D:\Dev\esp` | 打开 ESP 项目能编译（见 5.7） |
| 20 | ESP-IDF 多版本 6.0.2 / 5.4.3 | `eim install -i` | `D:\Dev\esp\v6.0.2`、`v5.4.3`（共享 `tools`） | `idf-use -List` 三个版本（见 5.8） |
| 21 | IDF 版本切换器 `idf-use` | 复制脚本 + `$PROFILE` 别名 | `%USERPROFILE%\idf-use.ps1` | `idf-use 5.4.3` 后 `idf.py --version` |
| 22 | Node.js LTS（npm 目录落 D 盘） | winget + `npm config` | `D:\Program Files\nodejs`；npm 全局/缓存 → `D:\Dev\tools` | `node --version`；`npm config get prefix` 在 D 盘 |
| 23 | MobaXterm（串口 / SSH 终端） | 官方绿色版 zip | `D:\Dev\tools\MobaXterm` | 主程序存在、CygUtils 插件齐全 |

> 执行顺序是 1→15 → 17 → 18 → 19 → 20 → 21 → 22 → 23 → 16：追加步骤后冒烟校验仍强制排最后，保证校验结果准确。
> 步骤 22（Node.js）、23（MobaXterm）独立无依赖，赶时间可先单跑 `-Only 22` / `-Only 23`，不必等 ESP-IDF / Qt 那几步。

### 前三步的具体流程

```powershell
# 步骤 1：最新版 VSCode
winget install --id Microsoft.VisualStudioCode --source winget `
  --accept-package-agreements --accept-source-agreements `
  --location "D:\Program Files\Microsoft VS Code"
winget upgrade --id Microsoft.VisualStudioCode --source winget `
  --accept-package-agreements --accept-source-agreements
code --version

# 步骤 2：16 个插件（见第五节清单，脚本逐行 --force 安装）
code --install-extension ms-vscode.cpptools --force
code --list-extensions

# 步骤 3：最新版 Git
winget install --id Git.Git --source winget `
  --accept-package-agreements --accept-source-agreements `
  --location "D:\Program Files\Git"
winget upgrade --id Git.Git --source winget `
  --accept-package-agreements --accept-source-agreements
git --version
```

`install + upgrade` 成对执行：**没装就装最新、装过就检查升级**，重复跑不会出错。装完脚本会自动补工具定位，不需要改 PATH。

### 步骤 17：ESP-IDF（重点，D 盘规则的关键）

```powershell
winget install --id Espressif.EIM-CLI --source winget `
  --accept-package-agreements --accept-source-agreements `
  --location "D:\Program Files\EIM"
# 生成 D 盘 TOML 配置（内容见第五节），再执行：
eim install --config D:\Dev\esp\eim-config.toml
eim list
```

⚠️ **只写 `eim install -p D:\Dev\esp` 是不够的**：实测 `-p` 只把 ESP-IDF 框架源码放 D 盘，
工具链、下载缓存、Python 虚拟环境、激活脚本仍按默认落到 `C:\Espressif`（实测 10.42 GB）。
必须用官方 TOML 配置把 6 个路径字段全部钉到 D 盘。

### 步骤 18：Qt（自动，走国内镜像）

```powershell
winget install --id miurahr.aqtinstall --source winget `
  --accept-package-agreements --accept-source-agreements `
  --location "D:\Program Files\aqtinstall"

# 1) 按 dry-run 从高到低探测镜像上真正可装的 Qt 6.x 版本
aqt install-qt windows desktop <可用版本> win64_mingw `
  -O "D:\Dev\tools\Qt" -b "https://mirrors.aliyun.com/qt/" --dry-run

# 2) 正式安装（失败自动重试 3 次）
aqt install-qt   windows desktop <版本> win64_mingw -O "D:\Dev\tools\Qt" -b <镜像> --timeout 30
aqt install-tool windows desktop tools_mingw1310     -O "D:\Dev\tools\Qt" -b <镜像> --timeout 30
aqt install-tool windows desktop tools_qtcreator     -O "D:\Dev\tools\Qt" -b <镜像> --timeout 30
```

**成功判据是 `qmake.exe` 真实存在**，不是"命令跑完了"。所有命令都带 `-O D:\Dev\tools\Qt`。

### 人工步骤 11–15

| 步骤 | 操作 |
|---|---|
| 11 ESP-IDF v6.0 | 官网下载 Windows 离线 Installer 选 v6.0 → 装到 `D:\Dev\esp\v6.0`，工具链 `D:\Dev\esp\tools`（路径无空格中文）→ 设 `IDF_PATH` / `IDF_TOOLS_PATH` → VSCode 装 `espressif.esp-idf-extension` 关联 → `export.ps1` 后 `idf.py --version` |
| 12 Qt 官方 IDE | Qt Online Installer 登录账号 → 组件勾 Qt 6.x MinGW 64-bit / Core / Widgets / Network / Qt Creator → 路径必须改 `D:\Dev\tools\Qt`（不要留 `C:\Qt`）→ 无人值守：`--root <路径> --accept-licenses --default-answer --confirm-command install <组件名>` → 加 PATH → 验证 qmake / mingw32-make |
| 13 驱动 | 按主板芯片装 CP210x / CH340 / FTDI；JTAG 另装调试器驱动；设备管理器确认 COM 口 |
| 14 SSH | 从加密载体恢复 `id_ed25519_new` 到 `%USERPROFILE%\.ssh\`，权限仅当前用户；`~/.ssh/config` 指定 IdentityFile；`ssh -T git@liberlive-gitlab.liberlive-music.com` |
| 15 仓库 | clone 到 `D:\Dev\repos` → checkout 开发分支 → 确认 `git status` 干净、submodule 已初始化 |

**凭据绝不写进脚本或仓库。**

---

## 五、必要配置内容

### 5.1 EIM TOML 配置（步骤 17 自动生成，本次优化核心）

路径：`D:\Dev\esp\eim-config.toml`（由 `New-EimConfig` 运行时生成，脚本本身仍是单文件）

```toml
# Generated by bootstrap.ps1: force ALL ESP-IDF artifacts onto D drive
path = "D:/Dev/esp"
tool_download_folder_name = "D:/Dev/esp/dist"
tool_install_folder_name = "D:/Dev/esp/tools"
activation_script_path_override = "D:/Dev/esp/tools"
config_file_save_path = "D:/Dev/esp/eim-config-saved.toml"
non_interactive = true
cleanup = true
```

| 字段 | 作用 | 不写的后果 |
|---|---|---|
| `path` | ESP-IDF 框架源码根（版本目录自动派生） | 默认用户目录 |
| `tool_download_folder_name` | 工具链下载缓存 dist | **默认 `C:\Espressif\dist`，数 GB 落 C 盘** |
| `tool_install_folder_name` | 编译器 / OpenOCD / cmake 等工具链 | **默认 `C:\Espressif\tools`，数 GB 落 C 盘** |
| `activation_script_path_override` | PowerShell 激活脚本 | 默认 C 盘 |
| `config_file_save_path` | 保存本次配置便于复现 | 默认当前目录 |
| `cleanup` | 装完删除 dist 缓存，省磁盘 | 缓存常驻 |

> 不写 `idf_path`：EIM 按「path + 版本」自动派生，钉死反而装不了下一个最新版。
> 不写 `python_env_folder_name`：默认落在 `tool_install_folder_name` 下，自动跟到 D 盘。
> 不写 `esp_idf_json_path`：几 KB 索引留默认 C 盘，避免 `eim list` 等命令都得带额外参数。
>
> 字段依据：Espressif 官方 [Configuration](https://docs.espressif.com/projects/idf-im-ui/en/latest/configuration.html) /
> [CLI Commands](https://docs.espressif.com/projects/idf-im-ui/en/latest/cli_commands.html)。
> 本机 `eim install --help` 已确认 `--config` 等参数存在。

### 5.2 Git 全局配置（12 项，值里不含任何路径）

```ini
user.name            = licong
user.email           = licong@liberlive-music.com
core.longpaths       = true
core.autocrlf        = false
core.editor          = code --wait
init.defaultBranch   = main
pull.rebase          = true
push.autoSetupRemote = true
merge.conflictStyle  = zdiff3
credential.helper    = manager
alias.st             = status -sb
alias.lg             = log --oneline --graph --decorate --all
```

逐项 `git config --global` 写入，**不生成文件、不写 `include.path`**（避免留下指向会话临时目录的悬空引用）。

### 5.3 VSCode 插件清单（16 个）

| # | 扩展 ID | 用途 |
|---|---|---|
| 1 | `ms-vscode.cpptools` | C/C++ 智能提示与调试 |
| 2 | `ms-vscode.cmake-tools` | CMake 构建集成（含 CMake 语言服务） |
| 3 | `espressif.esp-idf-extension` | ESP-IDF 开发（编译/烧录/监视） |
| 4 | `ms-vscode.hexeditor` | 二进制 / 固件十六进制查看 |
| 5 | `eamodio.gitlens` | Git 行级溯源与提交对比 |
| 6 | `mhutchie.git-graph` | Git 提交图谱可视化（分支/合并一目了然） |
| 7 | `donjayamanne.githistory` | Git 文件 / 提交历史查看 |
| 8 | `github.vscode-pull-request-github` | GitHub PR / Issue 浏览与管理 |
| 9 | `ms-vscode.powershell` | PowerShell 语言与调试支持 |
| 10 | `ms-python.python` | Python 语言支持 |
| 11 | `redhat.vscode-yaml` | YAML 语法校验 |
| 12 | `EditorConfig.EditorConfig` | 统一缩进 / 换行风格 |
| 13 | `yzhang.markdown-all-in-one` | Markdown 编辑增强 |
| 14 | `PKief.material-icon-theme` | 文件图标主题 |
| 15 | `ms-ceintl.vscode-language-pack-zh-hans` | 中文（简体）界面语言包 |
| 16 | `tencent-cloud.coding-copilot` | 腾讯云代码助手 CodeBuddy |

> **不再安装 `twxs.cmake`**：官方已弃用（deprecated），CMake Tools 已内置 CMake 语言服务（语法高亮/智能提示），
> 装了会反复弹「建议卸载 twxs.cmake」。已卸载的机器无需再处理，重装后由 CMake Tools 接管。

> **WorkBuddy 是独立桌面客户端，VSCode 里没有官方 WorkBuddy 插件**（`tencent.workbuddy` 在扩展市场 404）；
> VSCode 里的腾讯官方 AI 插件是 CodeBuddy，故清单用 `tencent-cloud.coding-copilot`。
> 中文语言包装完若界面仍英文：`Ctrl+Shift+P` → `Configure Display Language` → `zh-cn`。
> Python 扩展会自动带出 `ms-python.debugpy` / `vscode-pylance` / `vscode-python-envs`，不在清单里属正常。

加减插件只改脚本里的 `$Extensions` 数组；用途说明漏写不影响安装。

### 5.4 Qt 下载镜像与版本策略

| 镜像 | 实测 |
|---|---|
| `https://mirrors.aliyun.com/qt/`（默认） | 可解析，稳定 |
| `https://mirrors.tuna.tsinghua.edu.cn/qt/` | 可解析 |
| `https://download.qt.io`（aqt 默认） | 国内常连接失败 / `IncompleteRead` |

版本策略：**不取 `list-qt` 的最大版本号**，而是从高到低用 `install-qt --dry-run` 逐个探测，
选第一个镜像上真正有 `Updates.xml` 的版本。MinGW 工具包按该版本 dry-run 输出里的
`MinGW-w64-x86_64-<x.y.z>` 自动匹配（如 6.10.3 → `tools_mingw1310`），不取编号最大的。

### 5.5 环境变量与目录结构

```
D:\Program Files\          # 软件本体
  ├─ Microsoft VS Code\
  ├─ Git\
  ├─ 7-Zip\
  ├─ Python312\
  ├─ PuTTY\
  ├─ nodejs\               # Node.js LTS（含 npm / npx）
  ├─ EIM\
  └─ aqtinstall\
D:\Dev\                    # 工具链 / 仓库 / 数据
  ├─ repos\                # 代码仓库
  ├─ tools\Qt\             # Qt 库 + MinGW + Qt Creator
  ├─ tools\npm-global\     # npm 全局包（npm config prefix）
  ├─ tools\npm-cache\      # npm 缓存（npm config cache）
  ├─ tools\MobaXterm\      # 串口 / SSH 终端（绿色版，配置写同目录 ini）
  ├─ esp\                  # ESP-IDF 根（多版本共存）
  │   ├─ eim-config.toml   #   EIM 配置：路径全部钉 D 盘
  │   ├─ v6.1\esp-idf\     #   最新版（步骤 17）
  │   ├─ v6.0.2\esp-idf\   #   6.0.2（步骤 20）
  │   ├─ v5.4.3\esp-idf\   #   5.4.3（步骤 20）
  │   ├─ dist\             #   下载缓存（共享）
  │   └─ tools\            #   工具根（多版本共享，工具按「名称\版本」并存）
  │       ├─ cmake\4.0.3\          #   多版本各取所需，互不覆盖
  │       ├─ xtensa-esp-elf\esp-15.2.0_xxx\ 、esp-14.2.0_xxx\
  │       ├─ python\v6.1\venv\ 、v6.0.2\venv\ 、v5.4.3\venv\
  │       ├─ Microsoft.v6.1.PowerShell_profile.ps1      # 每版一个激活脚本
  │       ├─ Microsoft.v6.0.2.PowerShell_profile.ps1
  │       ├─ Microsoft.v5.4.3.PowerShell_profile.ps1
  │       └─ eim_idf.json  #   安装记录 + 当前选中版本（IDE 读这个）
  └─ tmp\
```

ESP-IDF 激活后由 EIM 注入环境变量。**多版本共存的关键是分工**：

| 变量 | 取值 | 是否随版本变 |
|---|---|---|
| `IDF_TOOLS_PATH` | `D:\Dev\esp`（容器根，**不是** `...\tools`） | 否，三版共享同一个工具根 |
| `IDF_PATH` | `D:\Dev\esp\v<版本>\esp-idf` | 是 |
| `IDF_PYTHON_ENV_PATH` | `D:\Dev\esp\tools\python\v<版本>\venv` | 是 |
| `PATH` | 各版激活脚本注入自己所需的工具版本目录 | 是（切换时先剔除旧条目） |
| `IDF_USE_ROOT` | `D:\Dev\esp`（步骤 21 写进 `$PROFILE`，只给 `idf-use` 定位容器根用） | 否；换盘时由 `-WorkspaceRoot` 重写 |

> `IDF_USE_ROOT` 是**给切换器自己的**定位变量，不参与 ESP-IDF 构建；
> 它解决的是「`Set-Alias` 不能带参数」导致换盘后 `idf-use` 找不到根的问题。

Qt 需把 `D:\Dev\tools\Qt\Tools\mingw*\bin` 与 `D:\Dev\tools\Qt\<版本>\mingw_64\bin` 加入 PATH。

### 5.6 VSCode 用户设置（受限模式修复）

VSCode 的「工作区信任（Workspace Trust）」会在打开**未信任**文件夹时进入受限模式（Restricted Mode）：
扩展被禁用、任务不自动运行、配置不生效。本机实测信任列表为空（打开任何文件夹都受限）。

修复：在 VSCode 用户设置里关闭该机制，重启 VSCode（或 `Developer: Reload Window`）生效。

- 位置：`%APPDATA%\Code\User\settings.json`（标准安装；User Installer 同路径）
- 新增一行：

```json
{
    "security.workspace.trust.enabled": false
}
```

> 这是「机器级」开关：之后打开任何文件夹都不再询问，包括将来 clone 的第三方仓库。
> 对个人开发机、文件都是自己的场景通常没问题，也是常用做法。
> 若想**保留信任保护、只信任自己的开发根目录**，可改为把 `F:\githup`、`D:\Dev` 等加入信任列表，
> 而不是整体关闭——需要时再单独处理。

### 5.7 VSCode ESP-IDF 集成路径（编译报 `cmake was not found` / `idf_tools.py export` 失败的根因）

ESP-IDF 扩展 **2.3.0 已移除** `idf.espIdfPath` / `idf.toolsPath` / `idf.pythonBinPath` 这三个旧设置
（源码里 0 引用，写了也不生效），**改由 EIM（Espressif Install Manager）+ `idf.customExtraVars` 提供路径**。
扩展启动会跑 `idf_tools.py export`，靠 `IDF_TOOLS_PATH` 定位工具目录并导出 PATH（含 cmake/ninja）。
`IDF_TOOLS_PATH` 的取值优先级（源码 `c = customExtraVars || 缓存配置 || 进程env || ""`）：

1. **`idf.customExtraVars.IDF_TOOLS_PATH`**（最高优先级，本机修复的主开关）；
2. 扩展缓存的全局配置 / `process.env.IDF_TOOLS_PATH`；
3. 都不设 → **为空** → `idf_tools.py` 回退到 `~/.espressif`（本机不存在）→ 报
   `ERROR: tool cmake has no installed versions` → 连锁导致 `idf.py set-target` 报
   `cmake must be available on the PATH` / `cmake was not found`。

> 这就是本机一直报错、且报错文本逐字节不变的根因：**`IDF_TOOLS_PATH` 为空**，不是指向 C 盘。

**修复（本机已按此配好，双保险覆盖所有取值路径）：**

- **主修复 — VSCode 用户设置**（`%APPDATA%\Code\User\settings.json`）用 `idf.customExtraVars` 显式钉死
  （优先级最高，直接覆盖"为空"的情况）：

```json
{
    "idf.customExtraVars": {
        "IDF_TOOLS_PATH": "D:\\Dev\\esp"
    },
    "idf.eimIdfJsonPath": "D:\\Dev\\esp\\tools\\eim_idf.json",
    "terminal.integrated.profiles.windows": {
        "ESP-IDF": {
            "source": "PowerShell",
            "args": ["-NoExit", "-ExecutionPolicy", "Bypass", "-File", "C:\\Users\\<用户名>\\idf-use.ps1", "-Default", "-EspRoot", "D:\\Dev\\esp"]
        }
    }
}
```

> **多版本注意**：`idf.customExtraVars` 里**只放 `IDF_TOOLS_PATH`**（三版共享的工具根）。
> 千万不要把 `IDF_PATH` / `IDF_PYTHON_ENV_PATH` 也钉进去——那会把所有项目锁死在同一个版本，
> `idf-use` 切版本、`eim select` 都会失效（详见 5.8）。`IDF_PATH` 由 `eim_idf.json` 的选中版本决定。
> 终端 profile 用 `idf-use -Default` 而不是写死某个 `Microsoft.v<版本>.PowerShell_profile.ps1`，切版本后自动跟随；
> 末尾的 `-EspRoot` 是显式容器根，换机改盘（`-WorkspaceRoot`）时新终端不依赖任何环境变量先就位。
> 其中 `<用户名>` 与 `D:\\Dev\\esp` 由 `bootstrap.ps1 -Only 19` 自动替换为真实绝对路径（VSCode 的 args 不展开 `%VAR%`）。

> **写入语义**：步骤 19 对 `idf.customExtraVars` 是**合并**而非整体替换——你自己加的
> `IDF_CCACHE_ENABLE` 等键会保留，只有 `IDF_TOOLS_PATH` 由脚本掌管。重复执行不会越写越乱。

- **备份 — EIM 安装记录 `eim_idf.json`**：扩展还会从 `idf.eimIdfJsonPath`（本机指向 `D:\Dev\esp\tools\eim_idf.json`）
  或默认回退位置 `C:\Espressif\tools\eim_idf.json` 读 `idfToolsPath`。两份都要保证 `idfToolsPath` 为容器根
  `D:\Dev\esp`（注意**不是** `D:\Dev\esp\tools`），并把 `python` / `activationScript` / `path` 也指向 D 盘。
  本机已把这两份都改成正确值。
  > ⚠️ `idfToolsPath` 必须是容器根 `D:\Dev\esp`：实测 `=D:\Dev\esp` 时 `idf_tools.py export` 成功（EXIT 0）；
  > `=D:\Dev\esp\tools` 反而报 "no installed versions"。

> 说明：`idf.espIdfPath` / `idf.toolsPath` / `idf.pythonBinPath` 在 2.3.0 已失效（仅保留兼容、不生效）；
> 真正生效的是 **`idf.customExtraVars` + 正确的 `eim_idf.json`**。
> 另外扩展启动会跑 `eim.exe gui --help` 探测 GUI 支持，本机 eim 0.21.1 无 `gui` 子命令会报
> `unrecognized subcommand 'gui'` —— 这是**非致命噪声**，扩展会自动回退 `wizard`，不影响编译。
> 换机可用 `bootstrap.ps1 -Only 19` 一键修 `eim_idf.json` 并钉死 `idf.customExtraVars` / `idf.eimIdfJsonPath`。

### 5.8 多版本 ESP-IDF 共存与切换（6.0.2 / 5.4.3 / 最新版）

同一台机可并存多套 ESP-IDF，**互不覆盖**。EIM 按「根目录 + 版本名」派生框架目录，工具根则三版共享。

**为什么能共存**

| 组成 | 位置 | 是否共享 |
|---|---|---|
| 框架源码 | `D:\Dev\esp\v<版本>\esp-idf` | 每版独立 |
| 工具链（cmake / ninja / gcc / openocd…） | `D:\Dev\esp\tools\<工具名>\<工具版本>` | **共享根**，按版本号分子目录并存 |
| Python 虚拟环境 | `D:\Dev\esp\tools\python\v<版本>\venv` | 每版独立 |
| 激活脚本 | `D:\Dev\esp\tools\Microsoft.v<版本>.PowerShell_profile.ps1` | 每版独立 |
| 下载缓存 | `D:\Dev\esp\dist` | 共享（省重复下载） |
| 安装记录 / 选中版本 | `D:\Dev\esp\tools\eim_idf.json` | 共享，`idfSelectedId` 决定 IDE 用哪版 |

> 关键：`IDF_TOOLS_PATH` 只有**一个**值 `D:\Dev\esp`（容器根），三版共用；
> 变的只有 `IDF_PATH`、`IDF_PYTHON_ENV_PATH` 和注入 PATH 的具体工具目录。

**安装（步骤 20）**

```powershell
bootstrap.ps1 -Only 20      # 装 v6.0.2 + v5.4.3，已存在的版本自动跳过
```

等价手工命令（国内镜像，GitHub 直连不稳定时必须带）：

```powershell
eim install --config D:\Dev\esp\eim-config.toml -i v6.0.2,v5.4.3 -n true `
  --idf-mirror https://git.espressif.com.cn --repo-stub Espressif/esp-idf `
  -m https://dl.espressif.cn/github_assets
```

- `--idf-mirror` + `--repo-stub` 把 clone 地址改成 `https://git.espressif.com.cn/Espressif/esp-idf.git`；
- `-m` 让工具链（cmake / ninja / gcc 等）从 `dl.espressif.cn` 下载，而不是 github.com；
- 不加镜像时实测会报 `git clone failed (exit code 128)` / `schannel: server closed abruptly`。

**切换（步骤 21 部署的 `idf-use`）**

```powershell
idf-use -List                 # 列出已装版本，* 为当前会话在用
idf-use 5.4.3                 # 切换：当前会话生效 + 持久化（新终端默认该版）
idf-use v6.0.2 -SessionOnly   # 只切当前会话，不动用户级环境变量
idf-use -Current              # 查看 IDF_PATH / venv / cmake / python / idf.py 版本
idf-use -Default              # 回到 eim 选中的版本（VSCode 终端 profile 用这个）
idf-use -List -EspRoot E:\Dev\esp   # 容器根不在默认位置时手动指定
```

**容器根怎么找（跨机关键）**：切换器**不写死** `D:\Dev\esp`，按下列顺序取第一个「确实是 ESP 容器根」
（该目录下存在 `v*\esp-idf\tools\idf_tools.py`）的候选：

1. 命令行 `-EspRoot`；
2. `$env:IDF_USE_ROOT` —— 步骤 21 写进 `$PROFILE` 的实际容器根（换机改盘时最可靠）；
3. `$env:IDF_TOOLS_PATH`（约定就是容器根；若被写成 `...\tools` 会取其父目录）；
4. `$env:IDF_PATH` 反推（`<根>\v<版本>\esp-idf` 往上两级）；
5. `eim_idf.json` 里各安装记录的 `idfToolsPath`（D 盘副本与 `C:\Espressif\tools` 都看）；
6. 兜底 `D:\Dev\esp`。

因此换机后用 `-WorkspaceRoot E:\Dev` 搭建，`idf-use` 依然开箱可用，无需改脚本。

切换动作（全部在同一会话内完成，无需重开终端）：

1. 退出上一版 venv（`VIRTUAL_ENV\Scripts\deactivate.ps1`）；
2. 从 PATH 剔除所有 `D:\Dev\esp\tools\*` 条目，但**保留**共享 base python（`tools\python`、`tools\python\Scripts`）；
3. 清掉 `IDF_*` / `ESP_*` 变量与 `idf.py` / `esptool` 等函数别名；
4. dot-source 目标版本的 `Microsoft.v<版本>.PowerShell_profile.ps1`；
5. 把 `IDF_TOOLS_PATH` 纠正为容器根 `D:\Dev\esp`（EIM 激活脚本会写成本版本 `...\tools`，层级不对）；
6. 把 `tools\espidf.constraints.v<版本>.txt` 补一份到容器根（见下方「路径层级坑」）；
7. `eim select <版本> --esp-idf-json-path <容器根>\tools` 同步 `eim_idf.json`，VSCode ESP-IDF 扩展随之切换
   （**必须带这个参数**：eim 默认只写 `C:\Espressif\tools\`，扩展读的却是 D 盘那份，不带就会出现「终端切了、IDE 没切」）；
8. 把 `IDF_PATH` / `IDF_PYTHON_ENV_PATH` / `IDF_TOOLS_PATH` 里的正反斜杠统一成 `\`
   （EIM 激活脚本写成 `D:/Dev/esp\tools\...` 混用，`idf.py` 按字符串比对会误报
   `Python interpreter ... is not from installed venv`，纯噪声）；
9. 默认写用户级持久变量（`IDF_PATH` / `IDF_PYTHON_ENV_PATH` / `ESP_IDF_VERSION` / `IDF_VERSION`），让新终端也落在同一版。

**路径层级坑（实测，必须知道）**

同一台机上，两个工具对 `IDF_TOOLS_PATH` 的隐含约定不同：

| 工具 | 要求 | 原因 |
|---|---|---|
| `idf_tools.py export` | `IDF_TOOLS_PATH=D:\Dev\esp`（容器根） | EIM 写进 `tools.json` 的目录名带 `tools/` 前缀，实际拼成 `D:\Dev\esp\tools\<工具>`；给 `...\tools` 会拼成 `...\tools\tools\<工具>` → 报 `tool xxx has no installed versions` |
| `idf.py` | 在 `$IDF_TOOLS_PATH` **根**找 `espidf.constraints.v<版本>.txt` | EIM 把该文件放在 `D:\Dev\esp\tools\` 下 → 容器根缺文件时报 `doesn't exist. Perhaps you've forgotten to run the install scripts` |

桥接办法（`idf-use` 已自动做）：`IDF_TOOLS_PATH` 固定容器根，同时把 `tools\espidf.constraints.*.txt`
复制一份到 `D:\Dev\esp\`。两个工具就都满足，`idf.py --version` 与 `idf_tools.py export` 同时正常。

**共存时的三条硬约束**

1. **不要把 `IDF_PATH` / `IDF_PYTHON_ENV_PATH` 写进 VSCode 的 `idf.customExtraVars`** —— 一旦钉死，所有项目锁在同一版本，`idf-use` 与 `eim select` 全部失效（只钉 `IDF_TOOLS_PATH`）。
2. **不要跨版本共用 venv** —— v5.4.3 与 v6.x 的 `requirements` 不同，EIM 已按版本建独立 venv。
3. **切版本后先 `idf.py fullclean`** —— 不同版本的 `build/` 配置（CMake 缓存、工具链 ABI）不兼容，直接增量编译会报奇怪的链接错误。

**验证**

```powershell
idf-use -List
idf-use 5.4.3 ; idf.py --version      # 期望 ESP-IDF v5.4.3
idf-use 6.0.2 ; idf.py --version      # 期望 ESP-IDF v6.0.2
idf-use 6.1   ; idf.py --version      # 期望 ESP-IDF v6.1
```

### 5.9 Node.js 与 npm（步骤 22）

```powershell
bootstrap.ps1 -Only 22      # 装 Node.js LTS + 把 npm 全局目录/缓存挪到 D 盘
```

**装什么、装哪里**

| 项 | 位置 | 说明 |
|---|---|---|
| Node.js LTS（含 `npm` / `npx`） | `D:\Program Files\nodejs` | winget 包 `OpenJS.NodeJS.LTS`；实测该包是 **wix** 安装器，`--location` 生效，`C:\Program Files\nodejs` 不会产生目录 |
| npm 全局包 | `D:\Dev\tools\npm-global` | `npm config set prefix`，写入用户级 `~\.npmrc` |
| npm 缓存 | `D:\Dev\tools\npm-cache` | `npm config set cache`，同上 |

为什么必须改 npm 目录：npm 默认 `prefix=%APPDATA%\npm`、`cache=%LOCALAPPDATA%\npm-cache`，
全局装几个 CLI（`@vue/cli`、`typescript`、`pnpm` 等）就是几百 MB，直接落在 C 盘，违反安装规则。
配置文件本身很小（`~\.npmrc` 两行），无法搬离用户目录，但**内容全部指向 D 盘**。

**PATH 须知（重要）**

| 目录 | 谁负责写进 PATH | 说明 |
|---|---|---|
| `D:\Program Files\nodejs` | Node 官方 MSI（写**机器** PATH） | 不用脚本管；装完新终端 `node` 就是 v26.x |
| `D:\Dev\tools\npm-global` | **步骤 22 主动加入用户 PATH** | npm 自己不会加，不加则 `npm i -g` 装的 CLI 敲不出来 |

> `npm-global` 是**脚本里唯一一处主动改 PATH** 的地方：只追加自己的一条目录、幂等去重、
> 保留注册表原值类型（不会把 `REG_EXPAND_SZ` 降级），改完广播环境变量变更。
> 其它工具仍遵循「脚本不改 PATH，靠安装器自己写」。

**两个容易误判的现象**

1. **在 IDE / 客户端内置终端里看到旧 node 版本**：某些客户端（如 WorkBuddy）会给自己启动的子进程
   **前置注入**自己的 node 目录，这不是持久化配置。判断真实顺序要看注册表拼出来的 PATH：

```powershell
$pure = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$env:PATH = $pure ; (Get-Command node).Source    # 这才是"新开一个普通终端"会命中的
```

2. **旧机器上有 `C:\Users\<你>\AppData\Roaming\npm` 这类死路径**：那是 npm **旧**默认全局目录，
   prefix 改到 D 盘后它已失效。留着会让「到底哪个 npm 目录生效」变得含糊，建议替换成
   `D:\Dev\tools\npm-global`（本机已按此处理，原 PATH 备份在 `%USERPROFILE%\path-backup-<时间>.txt`）。

若系统/用户 PATH 里确实还有别的 node 排在前面，步骤 22 会打印实际先命中的 `node.exe` 并提示调整顺序
（只比对**持久化 PATH**，不会因为 IDE 注入而误报）。

**验证**

```powershell
node --version                                  # 期望 v26.x（以 winget 当时的 LTS 为准）
& 'D:\Program Files\nodejs\node.exe' --version  # 确认本体版本，绕过 PATH 顺序
npm config get prefix                           # 期望 D:\Dev\tools\npm-global
npm config get cache                            # 期望 D:\Dev\tools\npm-cache
$env:PATH -split ';' -contains 'D:\Dev\tools\npm-global'   # 期望 True（新终端里）
npm ls -g --depth=0                             # 全局包列表（刚装完为空属正常）
```

> 校验表（步骤 16）里的 **Node.js** 一行按「安装根目录实扫 `node.exe`」判定，并显示 npm prefix
> 是否在 D 盘 —— 不受 PATH 顺序影响，能真实反映本方案有没有装到位。

### 5.10 MobaXterm（串口 / SSH 终端，步骤 23）

```powershell
bootstrap.ps1 -Only 23      # 从官网拉最新绿色版，解压到 D:\Dev\tools\MobaXterm
```

**为什么不用 winget 装（实测结论）**

| 尝试 | 结果 |
|---|---|
| `winget install --id Mobatek.MobaXterm --location "D:\Program Files\MobaXterm"` | 退出码 0，但文件落在 **`C:\Program Files (x86)\Mobatek\MobaXterm`（85 MB）**——该包是 `InstallerType: zip` + `NestedInstallerType: wix`，`--location` 传的 `TARGETDIR` 不被 MSI 采用 |
| `msiexec /i msi INSTALLDIR=...`（非提权） | 返回 **1603**（致命错误），per-machine MSI 需要管理员 |
| `msiexec /x {ProductCode}` 卸载 | 同样 1603；`winget uninstall` 也报 1603（这条路径没有提权） |
| `msiexec /a msi TARGETDIR=...`（管理安装，无需提权） | 成功，但**只展开 MSI 文件表里的 2 个文件**（`MobaXterm.exe` + `MobaXterm_installer.dat`），缺 `CygUtils.plugin` / `CygUtils64.plugin` / `MobaRTE.exe` |
| 官方 portable zip | ✅ 三个文件齐全，解压即用，无需管理员、不写注册表 |

> 结论：这类「zip 套 wix」的包，`--location` 基本指望不上；想装到非系统盘，绿色版是最稳的路子。

**装了什么**

| 文件 | 说明 |
|---|---|
| `MobaXterm_Personal_26.6.exe`（15.8 MB） | 主程序，文件名带版本号 |
| `CygUtils.plugin` / `CygUtils64.plugin`（31 MB） | 会话底层插件，**缺它串口/SSH 起不来** |
| `MobaXterm.ini` | 首次运行在同目录生成，配置随目录走（可直接备份迁移） |

下载链接从官网 `download-home-edition.html` 页面**实时解析**，不写死版本号；优先用系统 `curl.exe`
（44 MB 的包在 PS 5.1 的 `Invoke-WebRequest` 下实测会断流，只下到 26 MB），失败自动重试 3 次。

**使用**

1. 双击 `D:\Dev\tools\MobaXterm\MobaXterm_Personal_26.6.exe`；
2. 右键任务栏图标 → 固定，方便下次打开（绿色版不注册开始菜单项）；
3. 串口：`Session → Serial` → 选板子的 COM 口 → 波特率按固件设置（常见 115200）；
4. SSH：`Session → SSH`，与 PuTTY 并存，按习惯选用。

**升级 / 卸载**

- 升级：删掉 `D:\Dev\tools\MobaXterm` 整个目录，重跑 `-Only 23`（会重新解析官网当前版）；
- 卸载：直接删目录即可，不留注册表垃圾。

**验证**

```powershell
Get-ChildItem 'D:\Dev\tools\MobaXterm'          # 应有 MobaXterm_Personal_*.exe + 2 个 CygUtils*.plugin
```

> 校验表（步骤 16）里的 **MobaXterm（串口）** 一行按目录实扫主程序与插件，不依赖 PATH 或注册表。

---

## 六、冒烟校验

| 检查项 | PASS 条件 |
|---|---|
| winget / git / code / pwsh / python / ssh | 命令可定位 |
| Git 用户邮箱 | `user.email` 非空 |
| SSH 私钥 | `%USERPROFILE%\.ssh\id_ed25519_new` 存在 |
| 工作目录 / 安装根（D 盘） | 目录存在，统计子目录数 |
| ESP-IDF 框架 | 目录实扫 `D:\Dev\esp\v*\esp-idf\tools\idf_tools.py` |
| ESP-IDF 多版本（步骤 20） | `idf-use -List` 能列出 6.0.2 / 5.4.3 / 最新版，各自有 venv 与激活脚本 |
| ESP-IDF 工具链 | `D:\Dev\esp\tools` 下有 xtensa / riscv / cmake 等目录 |
| Node.js（步骤 22） | `D:\Program Files\nodejs\node.exe` 存在，且 `npm config get prefix` 在 D 盘 |
| MobaXterm（步骤 23） | `D:\Dev\tools\MobaXterm\MobaXterm_Personal_*.exe` 存在，且 `CygUtils*.plugin` 不少于 2 个 |
| Qt qmake / Qt MinGW | 目录实扫 `qmake.exe` / `mingw32-make.exe` |
| VSCode 扩展 | 已装数 ≥ 清单 16 个 |
| C 盘残留 | `C:\Espressif` 存在则 WARN，如实报告 |

**按目录实扫**而不是只读 `Get-Command` 或 `$env:IDF_PATH`：EIM 只在激活脚本里注入环境变量，
Qt 装到 D 盘也可能没加 PATH，只看环境变量会误报 FAIL。

结果分 PASS / WARN / FAIL 三级，说明文字按真实状态给出：
已跑过 `-Only 17` / `-Only 18` 仍 FAIL，就是安装真的失败了，重跑对应步骤。

---

## 七、修复经验档案（现象 → 根因 → 修复）

本章是新机排障的第一入口：每条都写明**真实现象**、**实测根因**、**落在哪个脚本步骤/小节**。
按「先看现象对不对」查，避免凭猜测改配置。

### 7.1 已修复问题总表

| 级别 | 实测现象 | 根因 | 修复 |
|---|---|---|---|
| 🔴 P0 | ESP-IDF 框架在 `D:\Dev\esp`，但工具链/缓存/venv 全落 `C:\Espressif`，**实测 10.42 GB**，违反 D 盘规则 | `eim install -p` 只控制框架路径；工具链默认 `C:\Espressif\tools` | 改用官方 TOML 配置，6 个路径字段全部钉 D 盘 + `cleanup = true` |
| 🔴 P0 | `安装 Qt 6.12.0` 报 `Failed to locate XML data`，MinGW 下载 `IncompleteRead` 中断，脚本却打印「完成 Qt 已装到…」 | `list-qt` 返回的最新版本在镜像上还没有 `Updates.xml`；脚本不检查 `$LASTEXITCODE`，无条件 `Write-Ok` | dry-run 逐个探测可装版本 + 国内镜像 + 重试 3 次 + **以 qmake.exe 真实存在为唯一成功判据** |
| 🟠 P1 | MinGW 选了 `tools_mingw1510`，与 Qt 6.10.x 的 MinGW 13.1.0 不配套 | 简单取「编号最大」的工具名 | 从 dry-run 输出解析 runtime 版本，自动匹配 `tools_mingw1310` |
| 🟠 P1 | `ESP-IDF FAIL IDF_PATH = <未设置>`，但 EIM 明明装成功 | EIM 只在激活脚本/快捷方式注入环境变量，不写系统环境变量 | 改为按目录扫描 `D:\Dev\esp\v*\esp-idf` |
| 🟠 P1 | 装完仍 FAIL，校验却写「首次 FAIL 属正常」 | 说明文字写死，掩盖真实失败 | 按实际状态动态提示，区分「未安装」与「安装失败」 |
| 🟠 P1 | 校验里 git / code 仍指向 C 盘 | `--location` 只对全新安装生效，不迁移已装软件 | 显式列为必要例外，执行时检测空目标目录并提示 |
| 🔵 P2 | `找不到可用的升级` 打印两遍 | `install` 已自动尝试升级，随后 `upgrade` 又输出一次 | 只在真有升级动作时打印 upgrade 输出 |
| 🔵 P2 | 校验新增 `C 盘残留` | 旧脚本遗留需在后续清理 | WARN 级如实报告，不假装全在 D 盘 |
| 🟠 P1 | VSCode 编译 ESP 项目报 `cmake was not found` / `idf_tools.py export` 失败 | 扩展 2.3.0 的 `IDF_TOOLS_PATH` 为空（未设 `idf.customExtraVars`、缓存配置里也没有该值），`idf_tools.py` 回退到不存在的 `~/.espressif` → `no installed versions` → cmake 不在 PATH | 用 `idf.customExtraVars` 钉死 `IDF_TOOLS_PATH=D:\Dev\esp`（主），并修 `eim_idf.json` 三处路径 + 钉 `idf.eimIdfJsonPath`（备）；详见 5.7，bootstrap 步骤 19 一键修复 |
| 🟠 P1 | 需求变成 6.0.2 / 5.4.3 / 最新版三版共存 | 单版本环境变量（`IDF_PATH`/venv/PATH）切版本会被上一版残留污染；`idf.customExtraVars` 若钉死 `IDF_PATH` 会把所有项目锁在同一版 | 框架按 `v<版本>` 分目录 + 共享工具根 + 每版独立 venv/激活脚本；新增 `idf-use` 切换器（剔除旧 PATH、纠正 `IDF_TOOLS_PATH`、`eim select` 同步、可选持久化）；`customExtraVars` 只留 `IDF_TOOLS_PATH`（详见 5.8） |
| 🔴 P0 | `eim install -i v6.0.2,v5.4.3` 报 `git clone failed (exit code 128)` / `schannel: server closed abruptly` | 直连 GitHub clone 被中断（国内网络） | 安装加 `--idf-mirror https://git.espressif.com.cn --repo-stub Espressif/esp-idf -m https://dl.espressif.cn/github_assets`，clone 与工具下载都走国内镜像 |
| 🟠 P1 | EIM 安装记录默认写 `C:\Espressif\tools\eim_idf.json`，与 D 盘那份分裂 | EIM 的 `--esp-idf-json-path` 默认值是 `C:\Espressif\tools` | 步骤 20 显式传 `--esp-idf-json-path D:\Dev\esp\tools`，安装后校验记录落地并检查 C 盘残留 |
| 🟡 P2 | 重跑已装步骤时 winget 返回 `-1978335189`（0x8A15002B），脚本报「安装失败」 | 该码是 `PACKAGE_ALREADY_INSTALLED`：包已存在且无升级，winget 用非 0 退出码表达「什么都没做」 | 单独识别该码并输出「已安装且已是最新」，不再误报失败 |
| 🟠 P1 | 装完 Node.js 后 `npm i -g` 的包和缓存都堆在 C 盘（`%APPDATA%\npm`、`%LOCALAPPDATA%\npm-cache`） | npm 默认 prefix/cache 就在用户漫游目录，与 Node 本体装哪无关 | 步骤 22 用 `npm config set prefix/cache` 指向 `D:\Dev\tools\npm-global` 与 `npm-cache`，写入用户级 `~\.npmrc`（详见 5.9） |
| 🟡 P2 | `node --version` 显示的版本不是刚装的那个 | 机器上常有多个 node（IDE 内置、nvm、旧安装），PATH 先命中的不是本方案装的；**IDE 还会给子进程前置注入自己的 node**，在 IDE 终端里看到的未必是真实配置 | 步骤 22 按「持久化 PATH（机器 + 用户）」模拟命中并提示，不会被注入误导；校验表按「安装根目录实扫」判定。查真实顺序的方法见 5.9 |
| 🟡 P2 | 用户 PATH 里残留 `C:\Users\<你>\AppData\Roaming\npm` | 那是 npm **旧**默认全局目录，prefix 改到 D 盘后已成死路径，容易让人误判「哪个 npm 目录生效」 | 替换为 `D:\Dev\tools\npm-global`（本机已处理，原 PATH 备份在 `%USERPROFILE%\path-backup-<时间>.txt`）；步骤 22 幂等补加，不会重复 |
| 🔴 P0 | `winget install MobaXterm --location "D:\..."` 报成功，实际仍装在 `C:\Program Files (x86)\Mobatek`（85 MB） | 该包 `InstallerType: zip` + `NestedInstallerType: wix`，winget 把 location 作 `TARGETDIR` 传给 MSI，而 MobaXterm 的目录属性是 `INSTALLDIR` | 放弃 winget 安装路径，步骤 23 改走官方绿色版 zip 解压到 `D:\Dev\tools\MobaXterm`（详见 5.10） |
| 🟠 P1 | 想用 `msiexec /i INSTALLDIR=...` 重装到 D 盘、或 `/x` 卸载，都返回 **1603** | per-machine MSI 需要管理员；脚本进程未提权，`winget uninstall` 同样失败 | 脚本不弹 UAC：改用绿色版；已装在 C 盘的实例建议从「设置 → 应用」手动卸载 |
| 🟡 P2 | `msiexec /a`（管理安装）展开成功，但程序目录只有 2 个文件，串口起不来 | 管理安装只解 MSI **文件表**里的文件；`CygUtils*.plugin` 存在 `MobaXterm_installer.dat`（zip 自解压包）里，要首次运行才落地 | 不用 `/a`，直接用官方 portable zip（三个文件齐全） |
| 🟡 P2 | PS 5.1 `Invoke-WebRequest` 下载 44 MB 的包只下到 26 MB 就结束 | IWR 在大文件 + 进度条场景下会中断流 | 优先调用系统 `curl.exe -L --fail --retry -C -`，失败重试 3 次并按文件大小校验 |

### 7.2 跨机可移植性加固（2026-11-16 全流程审核）

把「本机能跑」变成「换机能跑」时审核出的断点，全部已修：

| 编号 | 现象 | 根因 | 修复 |
|---|---|---|---|
| 🔴 P0 | 换机用 `-WorkspaceRoot E:\Dev` 搭建后，`idf-use` 一律报「没有找到任何 ESP-IDF 安装」 | `idf-use.ps1` 的 `$EspRoot` 默认值写死 `D:\Dev\esp`；`Set-Alias` 无法携带参数，别名永远用默认值 | 改为多级自动探测（`-EspRoot` → `IDF_USE_ROOT` → `IDF_TOOLS_PATH` → `IDF_PATH` 反推 → `eim_idf.json` → 兜底），并在步骤 21 把实际容器根写进 `$PROFILE` 的 `IDF_USE_ROOT`（见 5.8） |
| 🟠 P1 | 步骤 19 修完 VSCode 终端 profile 后，新机首次打开终端仍是旧盘路径 | 终端 profile 只传 `-Default`，容器根靠环境变量推断，而新机此时还没有用户级 `IDF_TOOLS_PATH` | 步骤 19 在 args 里显式追加 `-EspRoot <实际容器根>`；步骤 21 同时写 `IDF_USE_ROOT` 双保险 |
| 🟠 P1 | 手改过 `idf.customExtraVars`（例如加了 `IDF_CCACHE_ENABLE`）的机器，跑完步骤 19 那些键消失 | 原实现新建空对象整体 `Add-Member -Force` 覆盖 | 改为先复制既有键、再只覆盖 `IDF_TOOLS_PATH`（合并语义，见 5.7） |
| 🟠 P1 | 指定不存在的容器根时，报 `找不到与参数名称"Directory"匹配的参数`，与「没装版本」完全无关 | 目标盘符不存在时 `Get-ChildItem` 的 `-Directory` 是 FileSystem provider 动态参数，不可用 → 参数绑定失败；`$ErrorActionPreference='Stop'` 直接终止 | `Get-IdfVersions` 先 `Test-Path` 判存在；不存在则走友好提示（列已装版本 + 提示 `-EspRoot`） |
| 🟡 P2 | 每次 `idf.py` 都打印 `WARNING: Python interpreter ... is not from installed venv ...` | EIM 激活脚本里路径正反斜杠混用（`D:/Dev/esp\tools\...`），`idf.py` 按字符串比对 venv 路径判不相等 | 切换后把 `IDF_PATH` / `IDF_PYTHON_ENV_PATH` / `IDF_TOOLS_PATH` 统一为 `\`，警告消失、语义不变 |
| 🟡 P2 | 容器根若真装在 `C:\Espressif`，切版本时会被当成「迁移残留」清掉 PATH | `Remove-EspPathEntries` 无条件剔除 `c:\espressif` 开头的条目 | 仅当容器根不在 `C:\Espressif` 下才剔除（`$killLegacy`） |
| 🟡 P2 | 步骤 21 反复执行后 `$PROFILE` 里可能残留新旧两段别名块 | 幂等判断只认单一 marker 文本 | marker 升到 `... step 21) v2`，发现旧 v1 块先整段裁掉再写；写入统一 CRLF |
| 🔵 P3 | `bootstrap.ps1` 里有一个定义了但从未使用的 `$eimProfilePath` | 早期版本遗留（曾计划写 `idf.espIdfPath`，2.3.0 移除该键后废弃） | 删除死代码，避免误导后来者以为要配激活脚本路径 |
| 🔴 P0 | `idf-use 5.4.3` 后终端确实是 5.4.3，但 VSCode 的 ESP-IDF 扩展仍按**旧版本**编译 | `eim select` 不带 `--esp-idf-json-path` 时固定读写 `C:\Espressif\tools\eim_idf.json`，而扩展读 `idf.eimIdfJsonPath` 钉死的 D 盘那份 → 两份记录分叉（实测：C 盘 mtime 变了，D 盘纹丝不动） | 切换器调用改为 `eim select <版本> --esp-idf-json-path <容器根>\tools`，直写 D 盘那份；终端与 IDE 从此一致 |

### 7.3 设计决策备忘（改动前先读，避免回退）

| 决策 | 原因（实测） | 不要做什么 |
|---|---|---|
| `IDF_TOOLS_PATH` 恒为**容器根** `D:\Dev\esp` | `idf_tools.py` 的 `tools.json` 目录名自带 `tools/` 前缀；给 `...\tools` 会拼成 `tools\tools` → `no installed versions` | 不要为了「让 `idf.py` 找到 constraints」把 `IDF_TOOLS_PATH` 改成 `...\tools`；正解是复制 constraints 到根 |
| `idf.customExtraVars` 只钉 `IDF_TOOLS_PATH` | 钉死 `IDF_PATH` 会把所有项目锁在同一版本，`idf-use` / `eim select` 失效 | 不要为了「让某个项目编译」把 `IDF_PATH` 塞进 customExtraVars；用项目级 `.vscode` 或 `idf-use` |
| 多版本共用工具根、框架分目录 | 工具按 `名称\版本号` 子目录并存（cmake 3.30.2 与 4.0.3、gcc 14.2.0 与 15.2.0 实测共存） | 不要给每个版本单独 `IDF_TOOLS_PATH`，会重复下载数 GB |
| 安装一律带国内镜像 | 直连 GitHub 实测 `git clone failed (exit code 128)` / `schannel: server closed abruptly` | 不要图省事去掉 `--idf-mirror` / `-m` |
| 脚本内不写死盘符与用户名 | 换机可能无 D 盘、用户名不同 | 不要把 `D:\Dev\esp`、`C:\Users\licong` 写进逻辑（注释/兜底候选除外） |
| 仓库 `bootstrap.ps1` + `idf-use.ps1` 成对同步 | 曾经用 C 盘旧版覆盖仓库文件，丢掉 3 个 SCM 插件；用户目录副本与仓库不同步时「改了没生效」 | 不要只改一边；从仓库目录跑 `-Only 21` 才会把新版复制到用户目录 |
| `$PROFILE` 用 UTF-8 **BOM** 写 | PS 5.1 无 BOM 时按 ANSI 解析，中文注释变乱码 | 不要用 `Out-File -Encoding utf8`（5.1 默认带 BOM，但 `Set-Content` 不带，容易翻车） |
| `eim_idf.json` 同步方向是**单向**的 | 步骤 19：D→C（eim CLI 默认读 C 盘，需要看到安装记录）；`idf-use`：`eim select --esp-idf-json-path` 直写 D 盘 | 不要写成「双向全量覆盖」，会把对方刚写的记录/选中项冲掉 |

### 7.4 实测依据

- `aqt install-qt ... --dry-run`：6.12.0 / 6.11.3 / 6.11.2 → `exit=1 Failed to locate XML data`；6.10.3 → `exit=0 Total packages: 8`
- 国内镜像 `mirrors.aliyun.com/qt/`、`mirrors.tuna.tsinghua.edu.cn/qt/` → `exit=0`
- 6.10.3 dry-run 输出中的 MinGW runtime：`MinGW-w64-x86_64-13.1.0` → 对应 `tools_mingw1310`
- `eim_idf.json` 实测：迁移后 `idfToolsPath` 残留 `C:\Espressif\tools`、`python` 残留 `C:\Espressif\tools\python\v6.1\venv\Scripts\python.exe`（已修正为 `D:\Dev\esp` / `D:\Dev\esp\tools\...`）；`idfToolsPath` 必须是容器根 `D:\Dev\esp`（`D:\Dev\esp\tools` 反而会 "no installed versions"）
- `eim select v6.1` 实测（2026-11-16）：不带 `--esp-idf-json-path` 时只有 `C:\Espressif\tools\eim_idf.json` 的 mtime 变化、选中变 v6.1，`D:\Dev\esp\tools\eim_idf.json` 仍停留在 v5.4.3；加上 `--esp-idf-json-path D:\Dev\esp\tools` 后两份同步为 v6.1，`bootstrap.ps1 -Only 16` 的「（选中）」标记随之正确
- 容器根自适应实测：清空 `IDF_TOOLS_PATH` / `IDF_PATH` 后 `idf-use -List` 仍能从 `eim_idf.json` 定位到 `D:\Dev\esp`；`-EspRoot Z:\nope` 给出友好提示而非参数绑定错误
- `idf_tools.py export` 实测：`IDF_TOOLS_PATH=D:\Dev\esp` 时 EXIT=0 正确导出全部工具 PATH；**为空/未设**会回退 `~/.espressif` 报 `ERROR: tool cmake has no installed versions`（exit 1），这正是 VSCode 扩展报错、`cmake not found` 的根源。修复靠 `idf.customExtraVars.IDF_TOOLS_PATH`（优先级最高，覆盖为空）

### 7.5 C 盘残留迁移指引（本次 10.42 GB）

脚本**不会自动删除** `C:\Espressif`，需要人工确认后处理：

1. 用新配置跑一次 `bootstrap.ps1 -Only 17`，把工具链完整装到 `D:\Dev\esp\tools`；
2. `bootstrap.ps1 -Only 16` 确认「ESP-IDF 框架」「ESP-IDF 工具链」都 PASS；
3. 确认 `D:\Dev\esp` 下产物可用、`eim list` 正常后，再删除 `C:\Espressif`（主要是 `dist` 下载缓存，可先只删 `C:\Espressif\dist` 快速释放空间）；
4. 若之前有指向 C 盘的激活脚本快捷方式，改用 D 盘新生成的激活脚本。

---

## 八、故障排查

| 现象 | 处理 |
|---|---|
| winget 中文输出乱码 | 脚本已在调用 winget 期间临时把控制台编码切 UTF-8，结束后恢复 |
| `-Only 1,2,3` 只跑了 1 步 | 参数用 `[object]` 接收再自行拆分，兼容 `-File` 字符串与裸命令数组两种传法 |
| 提示「无法识别 bootstrap.ps1」 | 重开终端加载 `$PROFILE`，或当前窗口执行 `. $PROFILE`；也可用 `.\bootstrap.ps1` |
| 提示「禁止运行脚本」 | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force` |
| 装完 VSCode/Git 手敲 `git` 找不到 | 脚本不改 PATH；重开一个终端即可 |
| 未找到 winget | Microsoft Store 装「应用安装程序 App Installer」 |
| Qt 下载中断 | 重跑 `-Only 18`，已下载内容会复用；必要时 `-QtMirror` 换镜像或 `-QtVersion` 钉版本 |
| ESP-IDF 下载慢 | EIM 会自动选国内镜像（`git.espressif.com.cn` / `dl.espressif.cn`）；失败重跑 `-Only 17` |
| VSCode 老是处于受限模式 | 信任列表为空所致；在 `%APPDATA%\Code\User\settings.json` 加 `"security.workspace.trust.enabled": false`，重启 VSCode 生效（详见 5.6） |
| VSCode 编译报 `cmake was not found` / `idf_tools.py export` 失败（`no installed versions`） | 扩展 2.3.0 的 `IDF_TOOLS_PATH` 为空所致；用 `idf.customExtraVars` 钉死 `IDF_TOOLS_PATH=D:\Dev\esp`（主）+ 修正 `eim_idf.json` 三处路径并钉 `idf.eimIdfJsonPath`（备），重启 VSCode（详见 5.7） |
| 扩展日志出现 `eim.exe gui --help` 报 `unrecognized subcommand 'gui'` | 本机 eim 0.21.1 无 `gui` 子命令，属非致命探测噪声，扩展自动回退 `wizard`，不影响编译 |
| 项目级 `.vscode` 仍指向 `C:\Espressif` | 打开项目报找不到工具；检查项目 `.vscode/settings.json` 的 `idf.*` 是否误写 C 盘，改 D 盘或删除让全局生效（详见 5.7） |
| `idf-use 5.4.3` 报「未安装版本」 | 目标版本没装或目录不完整；`idf-use -List` 看已装列表，缺版本跑 `bootstrap.ps1 -Only 20` |
| 切版本后编译报 CMake/链接错乱 | `build/` 是上一版生成的；`idf.py fullclean` 后重编（详见 5.8 三条硬约束） |
| `idf.py --version` 与 `idf-use -List` 标的不一致 | 之前在别的窗口激活过旧版本；在当前窗口重跑 `idf-use <版本>`，它会先剔旧 PATH 再激活 |
| 装了新版本但 VSCode 看不到 | EIM 记录写到了 `C:\Espressif\tools\eim_idf.json`；确认 `%APPDATA%\Code\User\settings.json` 的 `idf.eimIdfJsonPath` 指向 `D:\Dev\esp\tools\eim_idf.json`，并把记录合并过去（步骤 20 已显式传 `--esp-idf-json-path`） |
| `eim install` 报 `git clone failed (exit code 128)` | 直连 GitHub 被断；改用国内镜像参数（见 5.8 安装命令） |
| `idf.py` 每次打印 `WARNING: Python interpreter ... is not from installed venv` | EIM 激活脚本里路径正反斜杠混用导致误判；`idf-use` 已统一为 `\`。若仍出现，说明当前会话是手动 dot-source 激活脚本而非 `idf-use`，改用 `idf-use <版本>` |
| `idf-use` 报「没有找到任何 ESP-IDF 安装」但目录明明在 | 容器根探测失败；`idf-use -List -EspRoot <根>` 直接指定。换机改盘场景重跑 `bootstrap.ps1 -Only 21` 写入 `IDF_USE_ROOT` 后即恢复 |
| `idf-use` 报「找不到与参数名称 Directory 匹配的参数」 | 传入的容器根所在盘符不存在（如 `Z:`）；检查 `-EspRoot` 或 `$env:IDF_USE_ROOT` |
| 从仓库改了 `idf-use.ps1` 但终端行为没变 | 步骤 21 部署的是 `%USERPROFILE%\idf-use.ps1`；在仓库目录执行 `bootstrap.ps1 -Only 21` 覆盖，再重开终端 |
| 换机用 `-WorkspaceRoot E:\Dev` 后 VSCode 编译找不到工具 | 重跑 `bootstrap.ps1 -Only 19`（重钉 `IDF_TOOLS_PATH` 与终端 `-EspRoot`）+ `-Only 21`（重写 `IDF_USE_ROOT`），然后重启 VSCode |
| `idf-use` 切了版本，但 VSCode 里编译用的还是旧版 | `eim select` 默认只改 `C:\Espressif\tools\eim_idf.json`；确认切换器输出里有「写入 `D:\Dev\esp\tools\eim_idf.json`」。旧版脚本需重跑 `bootstrap.ps1 -Only 21` 部署新版 |
| `eim list` 与 `idf-use -List` 选中项不一致 | 同上，两份 `eim_idf.json` 分叉；用 `eim list --esp-idf-json-path D:\Dev\esp\tools` 对齐查看 |

---

## 九、换机流程

> 目标：一台干净 Windows 从零到「能编译 ESP 项目、能切 IDF 版本」，中途不需要猜配置。
> 全程只用本仓库两个文件，不依赖旧机上的任何状态。

**9.1 准备（5 分钟）**

1. 从本仓库取 `bootstrap.ps1` **与 `idf-use.ps1`**，两个文件放同一目录；
   - 想让「裸命令」可用：两个都放到 `%USERPROFILE%`；
   - 想让「仓库更新能落盘」：两个都放在仓库目录，步骤 21 会复制到 `%USERPROFILE%`（推荐，二选一即可）；
2. 执行一次 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force`；
3. 按第三节注册 `$PROFILE` 的 `bootstrap.ps1` 别名（不注册就用 `.\bootstrap.ps1`，功能完全一样）。

**9.2 执行**

```powershell
bootstrap.ps1 -List                 # 先看清单，确认 20/21/22/23 步在列
bootstrap.ps1 -All                  # 全部 23 步（含插件、Git、目录、ESP-IDF 集成、Qt、Node、MobaXterm）
bootstrap.ps1 -Only 20              # 多版本：v6.0.2 + v5.4.3（数 GB，建议单跑）
bootstrap.ps1 -Only 21              # 部署 idf-use 切换器 + 写 IDF_USE_ROOT
bootstrap.ps1 -Only 22              # Node.js LTS + npm 目录落 D 盘（很小，-All 已含）
bootstrap.ps1 -Only 23              # MobaXterm 绿色版（串口/SSH，约 44 MB）
bootstrap.ps1 -Only 16              # 冒烟校验
```

**9.3 人工步骤 11–15**（工具链安装器、USB 驱动、SSH 凭据、克隆仓库）——脚本只打印指引，不会代做。

**9.4 无 D 盘的新机**

```powershell
bootstrap.ps1 -InstallRoot "E:\Program Files" -WorkspaceRoot "E:\Dev" -All
```

此时所有脚本自动跟随：步骤 19 的 `idf.customExtraVars.IDF_TOOLS_PATH`、
步骤 20 的安装根、步骤 21 写入 `$PROFILE` 的 `IDF_USE_ROOT`、终端 profile 的 `-EspRoot`
全部是 `E:\Dev\esp`，**不需要手改任何文件**。装完按第十章清单逐项验证即可。

**9.5 从旧机迁移（已有 D 盘环境）**

只需迁移两样**不可再生**的东西：SSH 私钥、未推送的仓库改动。
其余（工具链、venv、Qt、IDE 插件）全部重装，比搬迁更可靠——`venv` 与激活脚本里含绝对路径，跨机搬过去必坏。

---

## 十、跨机验收清单

新机搭完后逐条执行，**全部 PASS 才算搭建完成**。这套清单是本次审核的落地结论，
覆盖了此前所有「本机能跑、换机就崩」的环节。

| # | 命令 | PASS 条件 | 对应坑 |
|---|---|---|---|
| 1 | `bootstrap.ps1 -Only 16` | 无 FAIL；`C:\Espressif` 若有只报 WARN | 校验逻辑只认目录实扫 |
| 2 | `idf-use -List` | 列出预期版本（如 6.1 / 6.0.2 / 5.4.3），每行都有 `venv` + `激活脚本` | `$EspRoot` 探测、venv 缺失 |
| 3 | `idf-use 5.4.3 ; idf.py --version` | 输出 `ESP-IDF v5.4.3`，**无** `not from installed venv` 警告 | 路径正反斜杠混用 |
| 4 | `idf-use 6.1 ; idf.py --version` | 输出 `ESP-IDF v6.1` | 切版本残留污染 |
| 5 | `idf-use -Current` | `IDF_TOOLS_PATH` 为**容器根**（如 `D:\Dev\esp`），不是 `...\tools` | 路径层级冲突 |
| 6 | `idf-use 5.4.3 ; cmake --version` | 3.30.x（v5.4.3 侧）；`idf-use 6.1` 后应为 4.0.x | 工具链未真正跟随版本切换 |
| 7 | `eim list --esp-idf-json-path D:\Dev\esp\tools` | 三个版本均为 `[ok]`，选中项与 `idf-use -List` 的 `*` 一致 | `eim_idf.json` 分裂 |
| 8 | 看 `%APPDATA%\Code\User\settings.json` | 有 `idf.customExtraVars.IDF_TOOLS_PATH` 与 `idf.eimIdfJsonPath`；**没有** `idf.espIdfPath` / `idf.toolsPath` | 配了 2.3.0 已失效的旧键 |
| 9 | VSCode 打开 ESP 项目 → Build | 能完成 configure + build，不再报 `cmake was not found` | `idf_tools.py export` 失败根因 |
| 10 | VSCode 终端选「ESP-IDF」profile | 打开即已激活正确版本，`idf.py --version` 可用 | 终端 profile 未带 `-EspRoot` |
| 11 | `Get-Content $PROFILE -Tail 6` | 含 `IDF_USE_ROOT = '<实际容器根>'` 与 `idf-use` 别名 | 换盘后切器找不到根 |
| 12 | `git config --global user.email` | 非空且为自己邮箱 | Git 全局配置丢失 |
| 13 | `node --version` / `npm config get prefix` | 版本与 winget 当时的 LTS 一致；prefix 为 `D:\Dev\tools\npm-global`；`npm i -g <小工具>` 后能在任意目录直接敲 | Node 未装、npm 全局目录留在 C 盘或未进 PATH |
| 14 | 串口 `PuTTY` + 设备管理器 | 有 COM 口，能读到板子日志 | 驱动未装 |
| 15 | `Get-ChildItem D:\Dev\tools\MobaXterm` | 主程序 `MobaXterm_Personal_*.exe` + 2 个 `CygUtils*.plugin` 齐全 | MobaXterm 未装或插件缺失 |

> 第 3/4 步如果恰好落在「已激活版本」，`idf.py --version` 仍会响应——**不要只看它**，
> 第 6 步的 `cmake` 版本差异才证明「工具链真的跟着切了」。

---

## 十一、维护方式

清单、插件、Git 配置、校验逻辑**全部内联在 `bootstrap.ps1`**，没有外部依赖文件。

| 想改什么 | 改哪里 |
|---|---|
| 追加安装步骤 | 脚本顶部 `$Steps` 数组追加一项（校验会自动排到最后） |
| 加减 VSCode 插件 | `$Extensions` 数组；用途说明改 `$ExtensionLabels` |
| 改 Git 配置 | `$GitSettings` 数组 |
| 临时不装某项 | 该步 `enabled = $false` |
| 改安装盘 | `-InstallRoot` / `-WorkspaceRoot` 参数，脚本内无第二套路径 |
| 加/减 IDF 版本 | 步骤 20 的 `idfVersions` 数组（如加 `v6.0.3`） |
| 换 Node 版本线 | 步骤 22 的 `id`：`OpenJS.NodeJS.LTS`（LTS）↔ `OpenJS.NodeJS`（Current） |
| 改 npm 全局目录 | 步骤 22 的 `$npmGlobal` / `$npmCache`（默认 `$WorkspaceRoot\tools` 下）；改目录后新目录会被自动补进用户 PATH，旧条目不会自动清理，需手动删 |
| 换 MobaXterm 版本 | 删掉 `D:\Dev\tools\MobaXterm` 后重跑 `-Only 23`（下载链接从官网实时解析，不写死版本） |
| 改切换器逻辑 | `idf-use.ps1`（仓库与 `%USERPROFILE%` 成对同步；改完在仓库跑 `-Only 21` 部署） |
| 排查历史坑 | 第七章「修复经验档案」按现象查；改动前先读 7.3「设计决策备忘」 |

维护铁律：

1. **两个脚本必须成对提交**——`bootstrap.ps1` 与 `idf-use.ps1` 任一方改动，提交前确认另一方没被旧版覆盖（出过事）。
2. **不要写死盘符/用户名到逻辑里**——兜底候选与注释可以写，功能路径必须走参数或探测。
3. **改完必跑三件事**：语法检查、`-Only 16` 校验、第十章验收清单第 2–7 条。
