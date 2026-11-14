#Requires -Version 5.1
<#
.SYNOPSIS
  为 GitHub 账户搭建可重复的本地开发 / Git 环境（不含任何明文凭据）。
.DESCRIPTION
  设置 GitHub 专属身份（条件包含，不破坏现有工作 Git 配置）、生成 SSH 密钥、
  配置凭据；可选 -Login 走 gh 设备流登录（浏览器点一下授权，自动注册 SSH 公钥、
  自动接管 git 凭据，消灭“手动贴公钥 + 粘 PAT”两步）；可选克隆/创建仓库与分支。
  本脚本不写入任何明文密码 / token；秘钥只通过 SSH 公钥或 gh 一次授权录入。
.EXAMPLE
  github_setup.ps1                          # 仅搭建身份 + SSH + 凭据（幂等）
  github_setup.ps1 -Login                    # 设备流登录 + 自动注册公钥 + 接管凭据
  github_setup.ps1 -Login -Verify            # 登录后立即验证连接
  github_setup.ps1 -Verify                   # 仅验证连接（ssh -T / gh auth status）
  github_setup.ps1 -Repo https://github.com/Lc180327/foo.git   # 搭建并克隆
  github_setup.ps1 -NewRepo my-project       # 用 gh 新建仓库（需先 -Login）
.NOTES
  安全：绝不把密码 / token 写进脚本或仓库。GitHub 自 2021 起不再接受账户密码做 git 认证，
  必须使用 Personal Access Token(PAT) 或 SSH 密钥。gh 设备流登录用一次性设备码 + 浏览器授权，
  令牌由 gh 安全存储，不落盘明文。账户密码仅用于登录 GitHub 网站。
#>
[CmdletBinding()]
param(
    [string]$GitHubUser     = 'Lc180327',
    [string]$GitHubEmail    = '',          # 留空 = 使用 GitHub 提供的私密 no-reply 地址
    [string]$GitHubRoot     = 'D:\Dev\repos\github',
    [string]$SshKeyName     = 'id_ed25519_github',
    [string]$Repo           = '',          # 要克隆的仓库 URL
    [string]$NewRepo        = '',          # 要新建的仓库名（需 gh 已登录）
    [string]$DefaultBranch  = 'main',
    [switch]$SkipSsh,
    [switch]$Login,                         # 设备流登录 + 自动注册 SSH 公钥 + 配置 git 凭据
    [switch]$Verify,                        # 仅验证连接（ssh -T / gh auth status）
    [switch]$SkipGhInstall                   # 不自动安装 gh（已装时可加，省一步）
)

$ErrorActionPreference = 'Continue'

# git 定位：优先 PATH，否则退回系统安装位置
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    $cand = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
    if (Test-Path $cand) { $git = $cand }
}
function Invoke-Git { & $git @args }

$sshDir  = Join-Path $env:USERPROFILE '.ssh'
$keyPath = Join-Path $sshDir $SshKeyName
$ghConfig = Join-Path $GitHubRoot '.gitconfig-github'

# 邮箱默认用 GitHub 私密地址，避免泄露真实邮箱，同时能正常计入贡献
if (-not $GitHubEmail) { $GitHubEmail = "$GitHubUser@users.noreply.github.com" }

# ---------- gh 定位 / 安装 ----------
function Get-GhPath {
    $g = Get-Command gh -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    $cand = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
    if (Test-Path $cand) { return $cand }
    # 安装后可能在不同子目录
    $found = Get-ChildItem 'D:\Program Files\GitHub CLI' -Recurse -Filter gh.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    return $found
}
function Install-Gh {
    Write-Host '    未找到 gh CLI，尝试用 winget 安装到 D:\Program Files\GitHub CLI ...' -ForegroundColor Yellow
    $ghLoc = 'D:\Program Files\GitHub CLI'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning '    本机无 winget，请手动下载安装 GitHub CLI：https://cli.github.com/'
        return $null
    }
    winget install GitHub.cli --location "$ghLoc" --accept-package-agreements --accept-source-agreements 2>&1 | Out-Host
    $exe = Get-GhPath
    if ($exe -and (Test-Path $exe)) {
        # 加入用户 PATH（新终端生效）
        $p = [Environment]::GetEnvironmentVariable('Path', 'User')
        $dir = Split-Path $exe
        if ($p -notlike "*$dir*") {
            [Environment]::SetEnvironmentVariable('Path', ($p + ';' + $dir), 'User')
        }
        Write-Host "    gh 已安装: $exe（已加入用户 PATH，新开终端生效）" -ForegroundColor Green
        return $exe
    }
    Write-Warning '    gh 安装失败，请手动 winget install GitHub.cli 后重跑 -Login。'
    return $null
}
$ghExe = Get-GhPath
if (-not $ghExe -and -not $SkipGhInstall) { $ghExe = Install-Gh }
function Invoke-Gh { if ($ghExe) { & $ghExe @args } else { Write-Error 'gh 不可用' } }

# ---------- 仅验证模式 ----------
if ($Verify) {
    Write-Host '[验证] ssh -T git@github.com ...' -ForegroundColor Cyan
    ssh -T git@github.com 2>&1
    if ($ghExe) { Write-Host '[验证] gh auth status ...' -ForegroundColor Cyan; & $ghExe auth status 2>&1 }
    exit 0
}

Write-Host '[1/8] 检查 Git ...' -ForegroundColor Cyan
if (-not $git) { Write-Error '未找到 git，请先安装 Git for Windows（见 bootstrap.ps1 步骤 3）。'; exit 1 }
& $git --version

Write-Host '[2/8] 创建 GitHub 仓库根目录 ' + $GitHubRoot + ' ...' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $GitHubRoot | Out-Null

# 3) SSH 密钥（推荐凭据方案，私钥永不出本机）
if (-not $SkipSsh) {
    Write-Host '[3/8] SSH 密钥 ...' -ForegroundColor Cyan
    if (Test-Path "$keyPath.pub") {
        Write-Host "    已存在 $keyPath.pub，跳过生成。"
    } else {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
        # PowerShell 给原生命令传空口令串 "" 会被整个吞掉，导致 ssh-keygen 报
        # "option requires an argument -- N"；用临时 .cmd 让 cmd 正确把 "" 当作空口令。
        $keyWin = $keyPath.Replace('/', '\')
        $tmp = Join-Path $env:TEMP ('gen_ssh_' + [guid]::NewGuid().ToString('N') + '.cmd')
        @"
@echo off
ssh-keygen -t ed25519 -f "$keyWin" -N "" -C "$GitHubUser@github"
"@ | Set-Content -Path $tmp -Encoding ASCII
        & cmd /c $tmp 2>&1 | Out-Null
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Host "    已生成 $keyPath（无口令，注意文件权限；见 GITHUB_SETUP.md 如何加口令）。"
    }
    $pub = Get-Content "$keyPath.pub" -Raw
    Write-Host '    公钥（如需手动添加可用）：' -ForegroundColor DarkGray
    Write-Host "    $($pub.Trim())" -ForegroundColor DarkGray

    # ~/.ssh/config：github.com 固定用该密钥，与工作 GitLab 密钥隔离
    $cfgPath = Join-Path $sshDir 'config'
    $entry = "Host github.com`n    HostName github.com`n    IdentityFile $keyPath`n    User git`n    IdentitiesOnly yes`n"
    if (Test-Path $cfgPath) {
        $cur = Get-Content $cfgPath -Raw
        if ($cur -notmatch "IdentityFile .*$SshKeyName") {
            Add-Content $cfgPath "`n$entry"
            Write-Host "    已向 $cfgPath 追加 github.com 条目。"
        } else { Write-Host "    $cfgPath 已含该密钥条目，跳过。" }
    } else {
        Set-Content $cfgPath $entry
        Write-Host "    已创建 $cfgPath。"
    }
    # 收紧 config 权限（仅当前用户可读）
    icacls $cfgPath /inheritance:r /grant:r "$env:USERNAME`:(R)" | Out-Null
}

# 4) gh 设备流登录（消灭“手动贴公钥 + 粘 PAT”两步）
if ($Login) {
    Write-Host '[4/8] gh 设备流登录（需你在浏览器点一下授权）...' -ForegroundColor Cyan
    if (-not $ghExe) { Write-Error 'gh 不可用，无法登录；请先 winget install GitHub.cli。'; exit 1 }
    Write-Host '    脚本会打印一个一次性设备码和网址，请在浏览器打开、输入设备码、点击 Authorize。' -ForegroundColor Yellow
    & $ghExe auth login --web -p https -h github.com
    if ($LASTEXITCODE -ne 0) { Write-Error 'gh auth login 失败，请重试。'; exit 1 }
    # 让 git 用 gh 的 token 做 github.com 的 HTTPS 凭据（无需单独 PAT/GCM）
    & $ghExe auth setup-git
    # 注册我们的 SSH 公钥到 GitHub（idempotent：已存在会报错，忽略即可）
    if (-not $SkipSsh -and (Test-Path "$keyPath.pub")) {
        Write-Host '    注册 SSH 公钥到 GitHub（gh ssh-key add）...' -ForegroundColor Cyan
        & $ghExe ssh-key add "$keyPath.pub" --title ('workbuddy-' + $env:COMPUTERNAME) 2>&1 | Out-Null
    }
    Write-Host '    gh 登录完成，git 凭据与 SSH 公钥均已就绪。' -ForegroundColor Green
} else {
    Write-Host '[4/8] 跳过 gh 登录（未指定 -Login）。将使用 GCM+PAT 或已有 SSH 密钥。' -ForegroundColor DarkGray
}

# 5) GitHub 专属 git 配置（条件包含，不影响现有工作配置）
Write-Host '[5/8] 写入 GitHub 专属 git 配置（条件包含）...' -ForegroundColor Cyan
# 注意：凭据助手不写在这里（避免覆盖 gh/auth setup-git 或全局 GCM），统一在步骤 6 处理
$ghContent = @"
[user]
    name = $GitHubUser
    email = $GitHubEmail
"@
New-Item -ItemType Directory -Force -Path $GitHubRoot | Out-Null
Set-Content $ghConfig $ghContent -Encoding utf8
$ghRootFwd  = $GitHubRoot.Replace('\', '/')
$ghCfgFwd   = $ghConfig.Replace('\', '/')
Invoke-Git config --global ("includeIf.gitdir:" + $ghRootFwd + "/**" + ".path") $ghCfgFwd
Write-Host "    已设置条件包含：$ghRootFwd 下的仓库自动使用身份 $GitHubUser <$GitHubEmail>"

# 6) 凭据助手
Write-Host '[6/8] 配置凭据助手 ...' -ForegroundColor Cyan
if ($Login) {
    Write-Host '    已通过 gh auth setup-git 接管 github.com 凭据（令牌由 gh 安全存储，无需单独 PAT/GCM）。'
} else {
    Invoke-Git config --global credential.https://github.com.helper manager
    Write-Host '    已设置 GCM；首次 push/pull 时登录 PAT（由 Windows 凭据管理器加密保存）。'
}

# 7) 克隆或新建仓库
if ($Repo) {
    Write-Host '[7/8] 克隆仓库 ' + $Repo + ' ...' -ForegroundColor Cyan
    & $git -C $GitHubRoot clone $Repo
} elseif ($NewRepo) {
    Write-Host '[7/8] 新建仓库 ' + $NewRepo + ' ...' -ForegroundColor Cyan
    if ($ghExe) {
        & $ghExe repo create $NewRepo --private --clone 2>&1
    } else {
        Write-Warning '    未安装 gh CLI；请先 github_setup.ps1 -Login（会安装并登录 gh）后再用 -NewRepo。'
    }
} else {
    Write-Host '[7/8] 未指定 -Repo / -NewRepo，跳过仓库操作（需要时重跑并传入）。' -ForegroundColor DarkGray
}

# 8) 默认分支约定
Write-Host '[8/8] 默认分支提示 ...' -ForegroundColor Cyan
Write-Host "    新建仓库默认分支约定为 $DefaultBranch；克隆仓库请沿用远端默认分支，提交前先拉取。"

Write-Host "`n[完成] GitHub 环境脚手架已就绪。" -ForegroundColor Green
if ($Login) {
    Write-Host "下一步：运行 github_setup.ps1 -Verify 验证连接；或直接 git clone git@github.com:$GitHubUser/<仓库>.git" -ForegroundColor Yellow
} else {
    Write-Host '下一步：1) 运行 github_setup.ps1 -Login（浏览器点一下授权，自动注册公钥/凭据）；或 2) 手动把 SSH 公钥加到 GitHub / 首次用 GCM 登录 PAT。详见 GITHUB_OPS_GUIDE.md。' -ForegroundColor Yellow
}

