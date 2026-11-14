# GitHub 环境操作手册（实操篇）

> 配套：`github_setup.ps1`（已自动执行 + 可重跑）+ `GITHUB_SETUP.md`（原理/安全/脚本说明）
> 适用账户：**Lc180327** ｜ 适用系统：Windows 10/11 + Git for Windows + PowerShell 5.1
>
> 本文只讲**你接下来要亲自操作的步骤**，照着做即可。

---

## 一、已经自动搭好（你不用动）

| 项目 | 位置 / 状态 |
|---|---|
| SSH 密钥 | `C:\Users\licong\.ssh\id_ed25519_github`（已生成，ed25519，无口令） |
| `~/.ssh/config` | `github.com` 已固定用上面密钥，与 GitLab 密钥 `id_ed25519_new` 隔离 |
| GitHub 专属 git 身份 | `D:\Dev\repos\github\.gitconfig-github`（name=`Lc180327`，私密 no-reply 邮箱） |
| 条件包含规则 | 仅 `D:\Dev\repos\github/**` 下仓库用 Lc180327 身份，**你的工作配置未改** |
| gh CLI | `D:\Program Files\GitHub CLI\gh.exe`（首次用 `-Login` 时自动安装并加入 PATH） |

> 凭据方案有两种，选其一即可，脚本都已支持：
> - **推荐：gh 设备流（一键）**——令牌由 gh 安全存储，且自动把上面 SSH 公钥注册到 GitHub。
> - 备选：GCM + PAT（手动生成 token，首次 push 时登录）。

---

## 二、推荐做法：一键 + 浏览器点一下（消灭“手动贴公钥 / 粘 PAT”）

在 PowerShell 执行**一条命令**就够了：

```powershell
github_setup.ps1 -Login
```

执行后会：
1. 自动安装 gh CLI 到 `D:\Program Files\GitHub CLI`（若未装）；
2. 打印一个**一次性设备码 + 网址**，例如：
   ```
   ! First copy your one-time code: ABCD-1234
   - https://github.com/login/device
   ```
3. **你只需**：浏览器打开上面的网址 → 输入设备码 → 点击 **Authorize**（这就是唯一的手动动作）；
4. 脚本自动完成：`gh auth setup-git`（git 凭据由 gh 接管）+ `gh ssh-key add`（把你的 SSH 公钥注册到 GitHub）。

> 整个流程你只在浏览器点一下授权，不用复制粘贴任何密钥或 token。

### 验证连接（一键）

```powershell
github_setup.ps1 -Verify
```

看到 `Hi Lc180327! You've successfully authenticated...` 即成功。

---

## 三、如果你不想用 gh（备选手动流程）

### 步骤 1：把 SSH 公钥加到 GitHub

① 复制下面这整行公钥（或 PowerShell 里 `cat C:\Users\licong\.ssh\id_ed25519_github.pub` 获取）：
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAHZTvm+CZIxTcRWzinz2K/viNHA7wPWgbOFAIygFEi Lc180327@github
```
② 登录 GitHub → 右上角头像 → **Settings → SSH and GPG keys → New SSH key**
③ Title 随意（如 `my-win-pc`），Key 文本框粘贴上面的公钥，点 **Add SSH key**。

### 步骤 2：验证连接

```powershell
ssh -T git@github.com
```
- 首次提示 `Are you sure you want to continue connecting (yes/no/[fingerprint])?`，输入 `yes`。
- 看到 `Hi Lc180327! You've successfully authenticated...` 即**成功**。
- 若 `Permission denied (publickey)`，说明步骤 1 公钥还没加好。

### 步骤 3：首次推送 / 克隆（HTTPS 走 GCM + PAT）

**克隆：**
```powershell
cd D:\Dev\repos\github
git clone git@github.com:Lc180327/<仓库名>.git
```

**推送已有本地仓库**（如之前那份 `D:\Dev\repos\vscode`，本地提交 `f30081e` 还没推）：
```powershell
cd D:\Dev\repos\vscode
git remote -v                 # 确认当前 remote（之前是 lc032718/vscode）
git remote set-url origin git@github.com:Lc180327/vscode.git   # 改指向你的账户
git push -u origin main
```
> 提示：`lc032718/vscode` 与 `Lc180327/vscode` 是两个不同账户下的仓库，务必先确认 `git remote -v` 再 push，别推错地方。

**HTTPS+PAT 附录**：登录 GitHub（密码+2FA）→ Settings → Developer settings → PAT → Generate new token（勾 `repo`），生成后复制（只显示一次）；首次 `git push/pull` 时 GCM 弹窗：用户名 `Lc180327`，密码框粘 **PAT**（不是账户密码）。

---

## 四、每次提交的标准流程（复制即用）

> 前提：已完成第二节（gh 登录）或第三节（手动），且 `git status` 在目标仓库目录内。

```bash
# 0) 确认身份（github 目录下会自动用 Lc180327；其他仓库用工作身份，别混）
git config user.name && git config user.email

# 1) 先看改动，避免误提交
git status
git diff --stat

# 2) 先同步远端（你习惯 rebase，全局已配 pull.rebase=true）
git pull --rebase origin main

# 3) 精确添加，不要用 git add -A 盲加
git add <具体文件1> <具体文件2>

# 4) 规范提交信息：说明 what + why
git commit -m "fix: 修正 ESP-IDF EIM 工具链误落 C 盘的问题"

# 5) 推送（gh 登录后走令牌 / SSH 验证，无需再登录）
git push origin main
```

**提交纪律（沿用你现有规范）**
- 分支：日常在 `feature/xxx` 开发，`main` 受保护；合并前先 `rebase` / `pull --rebase`。
- 冲突：`merge.conflictStyle=zdiff3` 已配；冲突时优先保留当前分支修改。
- 提交信息：说明**做了什么 + 为什么**，别把调试日志、密钥、大文件带进去。
- 推送前确认 `git remote -v` 指向正确账户。

---

## 五、安全要点（浓缩）

- ⚠️ 你给的账户密码 `Lc180327` **没有、也不会写入任何文件**。GitHub 自 2021-08 起 git 认证**只接受 PAT 或 SSH**，不接受账户密码；该密码仅用于登录 GitHub 网站（加公钥 / 生成 PAT / 设备流授权）。
- **gh 令牌由 gh 安全存储**（系统凭据库/DPAPI），不落盘明文；设备码授权用完即失效。
- **SSH 私钥永不出本机**：只上传 `.pub` 公钥；私钥就在 `C:\Users\licong\.ssh\`，换机时随加密载体迁移，不要明文拷贝。
- 不同账户隔离：GitLab 用 `id_ed25519_new`，GitHub 用 `id_ed25519_github`，靠 `~/.ssh/config` 的 `Host` 区分。
- 想更稳：给 SSH 私钥加口令 `ssh-keygen -p -f C:\Users\licong\.ssh\id_ed25519_github`，然后用 `ssh-agent` 缓存。

---

## 六、可重复执行的脚本

```powershell
github_setup.ps1                          # 重搭身份+SSH+凭据（幂等，安全）
github_setup.ps1 -Login                   # 一键：gh 设备安装流登录 + 自动注册公钥 + 接管凭据
github_setup.ps1 -Login -Verify           # 登录后立即验证
github_setup.ps1 -Verify                  # 仅验证连接
github_setup.ps1 -Repo https://github.com/Lc180327/foo.git    # 搭建并克隆
github_setup.ps1 -NewRepo my-project      # 用 gh 新建仓库（需先 -Login）
```

> 脚本不写任何明文密码 / token，符合安全存放要求。
