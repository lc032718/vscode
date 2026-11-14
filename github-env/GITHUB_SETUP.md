# GitHub 本地开发与 Git 环境搭建说明（账户 Lc180327）

> 配套脚本：`github_setup.ps1`（可重复执行，不含任何明文凭据）
> 适用：Windows 10/11 + Git for Windows + PowerShell 5.1

---

## 一、已经为你搭好的部分（已完成）

| 项目 | 内容 | 验证方式 |
|---|---|---|
| SSH 密钥 | `C:\Users\licong\.ssh\id_ed25519_github`（ed25519，无口令） | `ssh -T git@github.com` |
| `~/.ssh/config` | `github.com` 固定用上面的密钥，与工作 GitLab 密钥隔离 | 见该文件 |
| GitHub 专属 git 身份 | 位于 `D:\Dev\repos\github\.gitconfig-github`（name=Lc180327，email=私密 no-reply 地址） | 见该文件 |
| 条件包含 | 仅 `D:\Dev\repos\github/**` 下的仓库自动套用 Lc180327 身份，**不动你现有的工作配置** | `git config --global --list` |
| 凭据助手 | GCM（`credential.https://github.com.helper=manager`），首次使用一次登录后由系统加密保存 | 同上 |
| 仓库根目录 | `D:\Dev\repos\github`（GitHub 仓库统一放这里） | 资源管理器 |

**注意**：你原有的全局 git 身份（`licong` / `licong@liberlive-music.com` / GitLab）一字未改。

---

## 二、你还需要做的一件事（涉及网页操作，脚本无法代劳）

> **推荐（一键）**：直接运行 `github_setup.ps1 -Login`。脚本会自动安装 gh CLI、走**设备流登录**（打印设备码+网址），你**只需在浏览器打开网址、输入设备码、点击 Authorize** 这一下；随后脚本自动 `gh auth setup-git`（git 凭据由 gh 接管）+ `gh ssh-key add`（把 SSH 公钥注册到 GitHub）。整个过程不用复制粘贴任何密钥或 token。
> 验证：`github_setup.ps1 -Verify`。

### 备选手动流程（不用 gh 时）

### 1) 把 SSH 公钥加到 GitHub（推荐，最省事）
1. 复制公钥（已生成，内容如下，也可 `cat C:\Users\licong\.ssh\id_ed25519_github.pub`）：
   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAHZTvm+CZIxTcRWzinz2K/viNHA7wPWgbOFAIygFEi Lc180327@github
   ```
2. 登录 GitHub → 右上角头像 → **Settings → SSH and GPG keys → New SSH key**
3. Title 随意（如 `my-win-pc`），Key 粘贴上面的公钥，保存。
4. 验证：`ssh -T git@github.com`（首次会问是否信任，输 `yes`，返回 `Hi Lc180327! You've successfully authenticated` 即成功）。

### 2) 若用 HTTPS 而非 SSH：用 PAT 登录
GitHub **不接受账户密码**做 git 认证（2021.8 起废弃）。需先生成 Personal Access Token：
1. 登录 GitHub（用你的账户密码 + 2FA）→ **Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token**
2. 作用域勾 `repo`（私有库读写）；设有效期。
3. **生成后立刻复制 token**（只显示一次）。
4. 首次 `git push` / `git pull` 时，GCM 弹窗登录：用户名填 `Lc180327`，密码框**粘贴 PAT**（不是账户密码）。
5. 之后凭据由 **Windows 凭据管理器（DPAPI 加密）** 保存，不再询问。

---

## 三、安全存放秘钥的方式（重点）

> ⚠️ **你提供的账户密码 `Lc180327` 没有、也不会写入任何文件或脚本。**
> 该密码只用于登录 GitHub 网站（含 2FA）。**它不能直接用于 git 认证**，必须换成下面两种凭据之一。

| 凭据方式 | 存放位置 | 是否明文落盘 | 推荐度 |
|---|---|---|---|
| **SSH 私钥** | `C:\Users\licong\.ssh\id_ed25519_github`（仅本机文件，权限限当前用户） | 否（私钥永不出本机，公钥才上传） | ⭐⭐⭐ 最推荐 |
| **PAT（HTTPS）** | Windows 凭据管理器（DPAPI 加密，不在磁盘明文） | 否 | ⭐⭐ |
| ❌ 账户密码 | — | — | 不可用于 git |

**安全守则**
1. **绝不**把密码 / PAT / 私钥写进脚本、配置文件、提交内容或聊天记录。本套脚本与文档零明文凭据。
2. 私钥文件权限收紧到仅当前用户（本机已生成，若重装系统或换机，**私钥必须随加密载体迁移，不要明文拷贝**）。
3. PAT 泄漏后立即在 GitHub 上 **revoke** 并重发；SSH 私钥泄漏后到 GitHub 删除对应公钥。
4. 不同账户隔离：工作 GitLab 用 `id_ed25519_new`，GitHub 用 `id_ed25519_github`，靠 `~/.ssh/config` 的 `Host` 区分，互不串用。
5. 想要更高安全：给 SSH 私钥加口令（见下），并用 `ssh-agent` 缓存，避免每次输入。

**给 SSH 私钥加口令（可选，提升安全性）**
```powershell
ssh-keygen -p -f C:\Users\licong\.ssh\id_ed25519_github   # 按提示输入新口令
# 之后每次用密钥前：ssh-add（需 ssh-agent，Windows 可用 `start-ssh-agent` 或 Git Bash）
```

---

## 四、每次提交应遵循的步骤

> 前提：已按第二节把公钥/PAT 配好，且 `git status` 在目标仓库内。

```bash
# 0) 确认身份（github 目录下的仓库会自动用 Lc180327；其他仓库用工作身份）
git config user.name && git config user.email

# 1) 先看改动，避免误提交
git status
git diff --stat

# 2) 先同步远端（你习惯 rebase，见全局配置 pull.rebase=true）
git pull --rebase origin main

# 3) 精确添加，不要用 git add -A 盲加
git add <具体文件1> <具体文件2>

# 4) 规范提交信息：简洁说明 what 与 why
git commit -m "fix: 修正 ESP-IDF EIM 工具链误落 C 盘的问题"

# 5) 推送（首次会走 GCM 登录或 SSH 验证）
git push origin main
```

**提交纪律（来自你现有规范）**
- 分支策略：`main` 受保护，日常在 `feature/xxx` 分支开发，合并前先 `rebase` / `pull --rebase`。
- 冲突解决：`merge.conflictStyle=zdiff3` 已配；冲突时优先保留当前分支修改。
- 提交信息：中文/英文均可，说明**做了什么 + 为什么**，不要把调试日志、密钥、大文件带进去。
- 推送前确认 `remote` 指向正确账户（`git remote -v`），避免推错仓库。
- 发布/合并前精简日志、清理调试代码（你的一贯要求）。

---

## 五、脚本用法（可重复执行，幂等）

```powershell
# 仅搭建身份 + SSH + 凭据（已执行过，重跑安全）
github_setup.ps1

# 一键：gh 设备安装流登录（浏览器点一下授权）+ 自动注册 SSH 公钥 + 接管 git 凭据
github_setup.ps1 -Login

# 登录后立即验证连接
github_setup.ps1 -Login -Verify

# 仅验证连接（ssh -T / gh auth status）
github_setup.ps1 -Verify

# 搭建并克隆一个仓库
github_setup.ps1 -Repo https://github.com/Lc180327/<仓库名>.git

# 搭建并用 gh 新建私有仓库（需先 -Login 登录 gh）
github_setup.ps1 -NewRepo my-project

# 自定义身份/邮箱/仓库根
github_setup.ps1 -GitHubUser Lc180327 -GitHubEmail you@example.com -GitHubRoot D:\Dev\repos\github
```

脚本参数：`GitHubUser`(默认 Lc180327)、`GitHubEmail`(留空=私密 no-reply)、`GitHubRoot`(默认 D:\Dev\repos\github)、`SshKeyName`(默认 id_ed25519_github)、`Repo`(克隆 URL)、`NewRepo`(新建名)、`DefaultBranch`(默认 main)、`SkipSsh`、`Login`(设备流登录+自动注册公钥+接管凭据)、`Verify`(仅验证连接)、`SkipGhInstall`(跳过自动安装 gh)。

---

## 六、关于本次提供的密码

- 你给的 `Lc180327` 是 GitHub **账户密码**。GitHub 自 2021-08 起，git 的 HTTPS 认证**只接受 PAT 或 SSH**，不再接受账户密码。
- 该密码**仅用于登录 GitHub 网站**以：添加 SSH 公钥、或生成 PAT。本机 git 认证走的是上面配置好的 SSH 密钥 / GCM 保存的 PAT，与账户密码无关。
- 因此脚本与文档中**没有任何一处写入该密码**，符合"秘钥安全存放"的要求。请妥善保管该密码，不要在别处复用。
