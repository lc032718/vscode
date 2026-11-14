# Windows 开发环境一键搭建方案

> 面向嵌入式 / Qt 开发的 Windows 10/11 环境复现方案。
> 目标：**换一台电脑，只跑一条命令，把开发环境按同一套规则装好。**
> 核心是一个自包含单文件脚本 `bootstrap.ps1` + 一份编号安装清单，不做老机采样、不做系统镜像。

---

## 一、方案定位

| 项目 | 说明 |
|---|---|
| 交付物 | `bootstrap.ps1`（唯一可执行脚本，自包含，不依赖同目录任何文件） |
| 驱动方式 | 脚本顶部 `$Steps` 编号清单（当前 18 步），脚本按清单逐项执行 |
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
| `bootstrap.ps1 -List` | 查看 18 步清单 + 17 个插件明细 + 安装规则 + 指令表 |
| `bootstrap.ps1 -All` | **安装所有**：执行全部 18 步 |
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

第 17 步 ESP-IDF、第 18 步 Qt 各需下载数 GB，**建议单跑** `-Only 17`、`-Only 18`。

---

## 四、完整安装清单与逐步流程

| # | 安装项 | 方式 | 目标位置 | 验证 |
|---|---|---|---|---|
| 1 | 最新版 VSCode | winget | `D:\Program Files\Microsoft VS Code` | `code --version` |
| 2 | VSCode 插件（17 个） | `code --install-extension` | VSCode 用户扩展目录 | `code --list-extensions` |
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

> 执行顺序是 1→15 → 17 → 18 → 16：追加步骤后冒烟校验仍强制排最后，保证校验结果准确。

### 前三步的具体流程

```powershell
# 步骤 1：最新版 VSCode
winget install --id Microsoft.VisualStudioCode --source winget `
  --accept-package-agreements --accept-source-agreements `
  --location "D:\Program Files\Microsoft VS Code"
winget upgrade --id Microsoft.VisualStudioCode --source winget `
  --accept-package-agreements --accept-source-agreements
code --version

# 步骤 2：17 个插件（见第五节清单，脚本逐行 --force 安装）
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

### 5.3 VSCode 插件清单（17 个）

| # | 扩展 ID | 用途 |
|---|---|---|
| 1 | `ms-vscode.cpptools` | C/C++ 智能提示与调试 |
| 2 | `ms-vscode.cmake-tools` | CMake 构建集成 |
| 3 | `twxs.cmake` | CMake 语法高亮 |
| 4 | `espressif.esp-idf-extension` | ESP-IDF 开发（编译/烧录/监视） |
| 5 | `ms-vscode.hexeditor` | 二进制 / 固件十六进制查看 |
| 6 | `eamodio.gitlens` | Git 行级溯源与提交对比 |
| 7 | `mhutchie.git-graph` | Git 提交图谱可视化（分支/合并一目了然） |
| 8 | `donjayamanne.githistory` | Git 文件 / 提交历史查看 |
| 9 | `github.vscode-pull-request-github` | GitHub PR / Issue 浏览与管理 |
| 10 | `ms-vscode.powershell` | PowerShell 语言与调试支持 |
| 11 | `ms-python.python` | Python 语言支持 |
| 12 | `redhat.vscode-yaml` | YAML 语法校验 |
| 13 | `EditorConfig.EditorConfig` | 统一缩进 / 换行风格 |
| 14 | `yzhang.markdown-all-in-one` | Markdown 编辑增强 |
| 15 | `PKief.material-icon-theme` | 文件图标主题 |
| 16 | `ms-ceintl.vscode-language-pack-zh-hans` | 中文（简体）界面语言包 |
| 17 | `tencent-cloud.coding-copilot` | 腾讯云代码助手 CodeBuddy |

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
  ├─ EIM\
  └─ aqtinstall\
D:\Dev\                    # 工具链 / 仓库 / 数据
  ├─ repos\                # 代码仓库
  ├─ tools\Qt\             # Qt 库 + MinGW + Qt Creator
  ├─ esp\                  # ESP-IDF（框架 v6.1/、工具链 tools/、缓存 dist/、配置 *.toml）
  └─ tmp\
```

ESP-IDF 激活后由 EIM 注入：`IDF_PATH`、`IDF_TOOLS_PATH`、`IDF_PYTHON_ENV_PATH`。
Qt 需把 `D:\Dev\tools\Qt\Tools\mingw*\bin` 与 `D:\Dev\tools\Qt\<版本>\mingw_64\bin` 加入 PATH。

---

## 六、冒烟校验

| 检查项 | PASS 条件 |
|---|---|
| winget / git / code / pwsh / python / ssh | 命令可定位 |
| Git 用户邮箱 | `user.email` 非空 |
| SSH 私钥 | `%USERPROFILE%\.ssh\id_ed25519_new` 存在 |
| 工作目录 / 安装根（D 盘） | 目录存在，统计子目录数 |
| ESP-IDF 框架 | 目录实扫 `D:\Dev\esp\v*\esp-idf\tools\idf_tools.py` |
| ESP-IDF 工具链 | `D:\Dev\esp\tools` 下有 xtensa / riscv / cmake 等目录 |
| Qt qmake / Qt MinGW | 目录实扫 `qmake.exe` / `mingw32-make.exe` |
| VSCode 扩展 | 已装数 ≥ 清单 17 个 |
| C 盘残留 | `C:\Espressif` 存在则 WARN，如实报告 |

**按目录实扫**而不是只读 `Get-Command` 或 `$env:IDF_PATH`：EIM 只在激活脚本里注入环境变量，
Qt 装到 D 盘也可能没加 PATH，只看环境变量会误报 FAIL。

结果分 PASS / WARN / FAIL 三级，说明文字按真实状态给出：
已跑过 `-Only 17` / `-Only 18` 仍 FAIL，就是安装真的失败了，重跑对应步骤。

---

## 七、本次优化记录（基于 2026-11-14 全量 `-All` 实测日志）

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

### 实测依据

- `aqt install-qt ... --dry-run`：6.12.0 / 6.11.3 / 6.11.2 → `exit=1 Failed to locate XML data`；6.10.3 → `exit=0 Total packages: 8`
- 国内镜像 `mirrors.aliyun.com/qt/`、`mirrors.tuna.tsinghua.edu.cn/qt/` → `exit=0`
- 6.10.3 dry-run 输出中的 MinGW runtime：`MinGW-w64-x86_64-13.1.0` → 对应 `tools_mingw1310`
- `eim_idf.json` 实测：`idfToolsPath: C:\Espressif\tools`、`python: C:\Espressif\tools\python\v6.1\venv\Scripts\python.exe`

### C 盘残留迁移指引（本次 10.42 GB）

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

---

## 九、换机流程

1. 从本仓库取 `bootstrap.ps1`，放到新机用户主目录 `%USERPROFILE%`；
2. 执行一次 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force`；
3. 按第三节注册 `$PROFILE` 别名（不注册则用 `.\bootstrap.ps1`）；
4. `bootstrap.ps1 -List` 看清单 → `bootstrap.ps1 -All`；
5. 完成人工步骤 11–15（工具链、驱动、SSH 凭据、代码仓库）；
6. `bootstrap.ps1 -Only 16` 复核校验表。

若新机没有 D 盘：

```powershell
bootstrap.ps1 -InstallRoot "E:\Program Files" -WorkspaceRoot "E:\Dev" -All
```

---

## 十、维护方式

清单、插件、Git 配置、校验逻辑**全部内联在 `bootstrap.ps1`**，没有外部依赖文件。

| 想改什么 | 改哪里 |
|---|---|
| 追加安装步骤 | 脚本顶部 `$Steps` 数组追加一项（校验会自动排到最后） |
| 加减 VSCode 插件 | `$Extensions` 数组；用途说明改 `$ExtensionLabels` |
| 改 Git 配置 | `$GitSettings` 数组 |
| 临时不装某项 | 该步 `enabled = $false` |
| 改安装盘 | `-InstallRoot` / `-WorkspaceRoot` 参数，脚本内无第二套路径 |
