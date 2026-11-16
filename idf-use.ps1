<#
.SYNOPSIS
    ESP-IDF 多版本切换器（Windows / PowerShell）。

.DESCRIPTION
    D:\Dev\esp 下可并存多套 ESP-IDF（如 v6.1 / v6.0.2 / v5.4.3）。
    各版本共用同一个工具根 D:\Dev\esp\tools，工具按「名称\版本号」子目录并存
    （例如 xtensa-esp-elf\esp-15.2.0_xxx 与 esp-14.2.0_xxx），因此不会互相覆盖。

    本脚本只做三件事：
      1) 清掉当前会话里上一个版本的 PATH 条目 / IDF_* 变量 / venv / idf.py 函数；
      2) dot-source 目标版本的 EIM 激活脚本（由 eim install 自动生成）；
      3) 把版本写进 eim_idf.json 的选中项（IDE 用），并按需持久化用户级环境变量。

.PARAMETER Version
    目标版本，可写 5.4.3 / v5.4.3 / 6.0.2 / v6.0.2 / 6.1 / v6.1。

.PARAMETER EspRoot
    ESP-IDF 容器根（其下为 v<版本>\esp-idf 与共享的 tools\），默认 D:\Dev\esp。
    一般不用传：脚本会按 参数 > IDF_USE_ROOT > IDF_TOOLS_PATH > IDF_PATH 反推 > eim_idf.json > D:\Dev\esp
    的顺序自动定位，因此换机改了安装盘（bootstrap.ps1 -WorkspaceRoot）也能直接用。

.PARAMETER List
    列出本机已安装的所有 ESP-IDF 版本，并标出当前会话在用哪个。

.PARAMETER Current
    显示当前会话的 ESP-IDF 环境详情。

.PARAMETER SessionOnly
    只切换当前 PowerShell 会话，不写用户级持久环境变量。
    默认会持久化，使「新开的终端 / 重启后的 VSCode」默认落在该版本。

.PARAMETER Default
    切到「默认版本」：优先 eim_idf.json 里 idfSelectedId 指向的版本，
    否则取版本号最高的已装版本。供 VSCode 终端 profile 调用。

.EXAMPLE
    idf-use -List

.EXAMPLE
    idf-use 5.4.3

.EXAMPLE
    idf-use v6.0.2 -SessionOnly

.EXAMPLE
    idf-use -Current
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Version,
    [switch]$List,
    [switch]$Current,
    [switch]$SessionOnly,
    [switch]$Default,
    # 留空 = 自动探测（见 Resolve-EspRoot）；仅在自动探测失效时才需要手动指定
    [string]$EspRoot = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 容器根定位
# 跨机可移植性的关键：不能把 D:\Dev\esp 写死。
# bootstrap.ps1 支持 -WorkspaceRoot 换盘（无 D 盘的新机），一旦写死，切换器在新机全部失效。
# 探测顺序（命中第一个「确实是 ESP 容器根」的候选即止）：
#   1) 显式 -EspRoot
#   2) $env:IDF_USE_ROOT（bootstrap.ps1 步骤 21 写入 $PROFILE 的实际容器根，换机改盘时最可靠）
#   3) $env:IDF_TOOLS_PATH（约定就是容器根）
#   4) $env:IDF_PATH 反推：<根>\v<版本>\esp-idf → 取两级父目录
#   5) eim_idf.json 的 idfInstalled[].idfToolsPath（D 盘副本与 C 盘默认位置都看）
#   6) 兜底 D:\Dev\esp（保持旧机行为，找不到时至少给出有意义的报错路径）
function Test-EspRoot {
    param([string]$Path)

    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    return [bool](Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
                  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'esp-idf\tools\idf_tools.py') } |
                  Select-Object -First 1)
}

function Get-JsonField {
    param([string]$JsonPath, [string]$Field)

    if (-not (Test-Path -LiteralPath $JsonPath)) { return $null }
    try {
        $j = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($Field -eq 'idfToolsPath') {
            $rec = @($j.idfInstalled) | Where-Object { $_.idfToolsPath } | Select-Object -First 1
            if ($rec) { return $rec.idfToolsPath }
        }
    } catch { }
    return $null
}

function Resolve-EspRoot {
    param([string]$Explicit)

    if ($Explicit) { return $Explicit.TrimEnd('\') }

    # profile 由 bootstrap.ps1 写入的实际容器根：换机改了安装盘时，这是唯一不依赖其它环境变量的来源
    if ($env:IDF_USE_ROOT -and (Test-EspRoot -Path $env:IDF_USE_ROOT)) {
        return $env:IDF_USE_ROOT.TrimEnd('\')
    }

    $cands = New-Object System.Collections.Generic.List[string]
    if ($env:IDF_TOOLS_PATH) {
        $t = $env:IDF_TOOLS_PATH.TrimEnd('\')
        $cands.Add($t)
        # EIM 激活脚本会把 IDF_TOOLS_PATH 写成 ...\tools；此时容器根是它的父目录
        if ([System.IO.Path]::GetFileName($t) -ieq 'tools') { $cands.Add((Split-Path -Parent $t)) }
    }
    if ($env:IDF_PATH) {
        $idf = $env:IDF_PATH.TrimEnd('\')
        if ([System.IO.Path]::GetFileName($idf) -ieq 'esp-idf') {
            $cands.Add((Split-Path -Parent (Split-Path -Parent $idf)))
        }
    }
    $jsonCands = New-Object System.Collections.Generic.List[string]
    if ($env:IDF_TOOLS_PATH) { $jsonCands.Add((Join-Path $env:IDF_TOOLS_PATH 'eim_idf.json')) }
    $jsonCands.Add('D:\Dev\esp\tools\eim_idf.json')
    $jsonCands.Add('C:\Espressif\tools\eim_idf.json')
    foreach ($j in $jsonCands) {
        $p = Get-JsonField -JsonPath $j -Field 'idfToolsPath'
        if ($p) { $cands.Add($p.TrimEnd('\')) }
    }
    $cands.Add('D:\Dev\esp')

    foreach ($c in $cands) {
        if (Test-EspRoot -Path $c) { return $c }
    }
    return 'D:\Dev\esp'
}

$EspRoot = Resolve-EspRoot -Explicit $EspRoot

# ---------------------------------------------------------------- 工具函数

function Get-IdfVersions {
    param([string]$Root)

    # 先判存在：驱动器/路径不存在时 Get-ChildItem 的 -Directory 动态参数会直接报
    # 「找不到与参数名称 Directory 匹配的参数」，比「没装版本」更难懂。
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }

    $dirs = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'esp-idf\tools\idf_tools.py') }

    foreach ($d in $dirs) {
        $name = $d.Name                                  # 例如 v6.1
        $idfPath = Join-Path $d.FullName 'esp-idf'
        $venv = Join-Path $Root "tools\python\$name\venv"
        $activation = Join-Path $Root "tools\Microsoft.$name.PowerShell_profile.ps1"
        [pscustomobject]@{
            Name           = $name
            Display        = $name -replace '^[vV]', ''   # 6.1
            IdfPath        = $idfPath
            Venv           = $venv
            HasVenv        = Test-Path -LiteralPath (Join-Path $venv 'Scripts\python.exe')
            ActivationPath = $activation
            HasActivation  = Test-Path -LiteralPath $activation
        }
    }
}

function Get-CurrentVersionName {
    param([string]$Root)

    if (-not $env:IDF_PATH) { return '' }
    $norm = $env:IDF_PATH.TrimEnd('\').ToLower()
    $hit = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
           Where-Object { $norm -eq (Join-Path $_.FullName 'esp-idf').TrimEnd('\').ToLower() } |
           Select-Object -First 1
    if ($hit) { return $hit.Name }
    return ''
}

# 剔除所有「ESP-IDF 工具链」PATH 条目，但保留共享的 base python（tools\python 与 tools\python\Scripts）
function Remove-EspPathEntries {
    param([string]$Root)

    $toolsRoot = (Join-Path $Root 'tools').TrimEnd('\').ToLower()
    $prefix = $toolsRoot + '\'
    $keep = @(
        $toolsRoot,
        (Join-Path $Root 'tools\python').TrimEnd('\').ToLower(),
        (Join-Path $Root 'tools\python\Scripts').TrimEnd('\').ToLower()
    )

    $out = New-Object System.Collections.Generic.List[string]
    # 只有容器根不在 C:\Espressif 下时，才把 C:\Espressif 条目当「迁移前残留」剔除；
    # 否则会把当前要激活的环境自己删掉（换机后若确实装在 C 盘，也不该被清）。
    $killLegacy = -not ((Join-Path $Root 'tools').ToLower().StartsWith('c:\espressif'))
    foreach ($entry in ($env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $n = $entry.TrimEnd('\').ToLower()
        if ($keep -contains $n) { $out.Add($entry); continue }
        if ($n.StartsWith($prefix)) { continue }             # <容器根>\tools\... 全部剔除
        if ($killLegacy -and $n.StartsWith('c:\espressif')) { continue }
        $out.Add($entry)
    }
    $env:PATH = ($out -join ';')
}

function Clear-IdfSession {
    param([string]$Root)

    # 1) 先退出上一个版本的 venv（存在才退）
    if ($env:VIRTUAL_ENV) {
        $deact = Join-Path $env:VIRTUAL_ENV 'Scripts\deactivate.ps1'
        if (Test-Path -LiteralPath $deact) {
            try { & $deact } catch { }
        }
        [System.Environment]::SetEnvironmentVariable('VIRTUAL_ENV', $null, 'Process')
    }

    # 2) 清 PATH 中所有 ESP-IDF 工具条目
    Remove-EspPathEntries -Root $Root

    # 3) 清 IDF_* / ESP_* 变量
    #    用 .NET API 而不是 Remove-Item Env: —— 后者在变量不存在时会被安全策略 fail-closed 拦下。
    foreach ($v in @(
        'IDF_PATH', 'IDF_TOOLS_PATH', 'IDF_PYTHON_ENV_PATH',
        'IDF_COMPONENT_LOCAL_STORAGE_URL', 'IDF_CCACHE_ENABLE',
        'ESP_IDF_VERSION', 'IDF_VERSION',
        'ESP_ROM_ELF_DIR', 'OPENOCD_SCRIPTS', 'ESP_CLANG_LIBS_PATH',
        'VIRTUAL_ENV'
    )) {
        [System.Environment]::SetEnvironmentVariable($v, $null, 'Process')
    }

    # 4) 移除激活脚本注册的函数与别名（先判断存在，避免 not-found 被拦）
    foreach ($fn in @('Invoke-idfpy', 'esptool', 'esptool.py', 'espefuse', 'espefuse.py',
                      'espsecure', 'espsecure.py', 'otatool.py', 'parttool.py')) {
        if (Test-Path "Function:\$fn") { Remove-Item "Function:\$fn" -ErrorAction SilentlyContinue }
    }
    if (Test-Path 'Alias:idf.py') { Remove-Item 'Alias:idf.py' -ErrorAction SilentlyContinue }
}

function Resolve-EimExe {
    param([string]$Root)

    $json = Join-Path $Root 'tools\eim_idf.json'
    if (Test-Path -LiteralPath $json) {
        try {
            $j = Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.eimPath -and (Test-Path -LiteralPath $j.eimPath)) { return $j.eimPath }
        } catch { }
    }
    # 先信 PATH（换机后 eim 可能是任意安装位置），再退到几个常见落点
    $cmd = Get-Command eim -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\eim.exe'),
        (Join-Path $env:ProgramFiles 'EIM\eim.exe'),
        'D:\Program Files\EIM\eim.exe',
        (Join-Path $env:USERPROFILE '.espressif\eim\eim.exe')
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Set-IdfUserEnv {
    param([string]$IdfPath, [string]$VenvPath, [string]$ToolsRoot, [string]$IdfVersion, [string]$IdfVersionFull)

    [Environment]::SetEnvironmentVariable('IDF_PATH', $IdfPath, 'User')
    [Environment]::SetEnvironmentVariable('IDF_TOOLS_PATH', $ToolsRoot, 'User')
    if ($VenvPath) { [Environment]::SetEnvironmentVariable('IDF_PYTHON_ENV_PATH', $VenvPath, 'User') }
    if ($IdfVersion) { [Environment]::SetEnvironmentVariable('ESP_IDF_VERSION', $IdfVersion, 'User') }
    if ($IdfVersionFull) { [Environment]::SetEnvironmentVariable('IDF_VERSION', $IdfVersionFull, 'User') }
}

# ---------------------------------------------------------------- 动作分支

$versions = @(Get-IdfVersions -Root $EspRoot)
if ($versions.Count -eq 0) {
    Write-Warning "在 $EspRoot 下没有找到任何 ESP-IDF 安装（应有 <版本>\esp-idf\tools\idf_tools.py）。"
    Write-Host '  先执行：bootstrap.ps1 -Only 17（最新版）或 -Only 20（6.0.2 / 5.4.3）' -ForegroundColor Yellow
    Write-Host '  若装在别的盘：idf-use -List -EspRoot <容器根>，或重跑 bootstrap.ps1 -Only 21 重新部署切换器' -ForegroundColor Yellow
    return
}

$currentName = Get-CurrentVersionName -Root $EspRoot

# --- 列表
if ($List -or (-not $Version -and -not $Current -and -not $Default)) {
    Write-Host ''
    Write-Host "ESP-IDF 已安装版本（根目录 $EspRoot）" -ForegroundColor Cyan
    Write-Host ('-' * 62)
    $versions | Sort-Object Name | ForEach-Object {
        $mark = if ($_.Name -eq $currentName) { '*' } else { ' ' }
        $flags = @()
        if ($_.HasVenv) { $flags += 'venv' } else { $flags += '缺少venv' }
        if ($_.HasActivation) { $flags += '激活脚本' } else { $flags += '缺少激活脚本' }
        Write-Host ("  {0} {1,-10} {2}" -f $mark, $_.Display, ($flags -join ' / '))
        Write-Host ("      {0}" -f $_.IdfPath) -ForegroundColor DarkGray
    }
    Write-Host ('-' * 62)
    Write-Host ("  当前会话：{0}" -f $(if ($currentName) { $currentName } else { '<未激活>' })) -ForegroundColor Gray
    Write-Host '  切换：idf-use 5.4.3    只当前会话：idf-use 5.4.3 -SessionOnly' -ForegroundColor DarkGray
    Write-Host ''
    return
}

# --- 当前环境详情
if ($Current) {
    Write-Host ''
    Write-Host '当前 ESP-IDF 环境' -ForegroundColor Cyan
    Write-Host ('-' * 62)
    Write-Host ("  版本目录   : {0}" -f $(if ($currentName) { $currentName } else { '<未激活>' }))
    Write-Host ("  IDF_PATH   : {0}" -f $(if ($env:IDF_PATH) { $env:IDF_PATH } else { '<未设置>' }))
    Write-Host ("  IDF_TOOLS_PATH : {0}" -f $(if ($env:IDF_TOOLS_PATH) { $env:IDF_TOOLS_PATH } else { '<未设置>（应为容器根 ' + $EspRoot + '）' }))
    Write-Host ("  venv       : {0}" -f $(if ($env:IDF_PYTHON_ENV_PATH) { $env:IDF_PYTHON_ENV_PATH } else { '<未设置>' }))
    Write-Host ("  ESP_IDF_VERSION : {0}" -f $(if ($env:ESP_IDF_VERSION) { $env:ESP_IDF_VERSION } else { '<未设置>' }))
    Write-Host ("  python     : {0}" -f $(if (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } else { '<PATH 中无 python>' }))
    Write-Host ("  cmake      : {0}" -f $(if (Get-Command cmake -ErrorAction SilentlyContinue) { (Get-Command cmake).Source } else { '<PATH 中无 cmake>' }))
    Write-Host ('-' * 62)
    if ($env:IDF_PATH) {
        $py = if ($env:IDF_PYTHON_ENV_PATH) { Join-Path $env:IDF_PYTHON_ENV_PATH 'Scripts\python.exe' } else { $null }
        if ($py -and (Test-Path -LiteralPath $py)) {
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $ver = & $py (Join-Path $env:IDF_PATH 'tools\idf.py') --version 2>&1 |
                       Where-Object { $_ -match 'ESP-IDF v' } | Select-Object -First 1
                Write-Host ("  idf.py --version : {0}" -f $(if ($ver) { $ver } else { '<执行失败，检查上面输出>' })) -ForegroundColor Green
            } catch {
                Write-Host '  idf.py --version : <执行失败>' -ForegroundColor Yellow
            } finally {
                $ErrorActionPreference = $prevEap
            }
        }
    }
    Write-Host ''
    return
}

# --- 解析目标版本
if ($Default) {
    # 优先 eim_idf.json 的 idfSelectedId，否则取最高版本
    $target = $null
    $json = Join-Path $EspRoot 'tools\eim_idf.json'
    if (Test-Path -LiteralPath $json) {
        try {
            $j = Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json
            $sel = $j.idfInstalled | Where-Object { $_.id -eq $j.idfSelectedId } | Select-Object -First 1
            if ($sel) { $target = $versions | Where-Object { $_.Name -eq $sel.name } | Select-Object -First 1 }
        } catch { }
    }
    if (-not $target) { $target = $versions | Sort-Object Name | Select-Object -Last 1 }
} else {
    $want = $Version -replace '^[vV]', ''
    $target = $versions | Where-Object { ($_.Display -eq $want) -or ($_.Name -eq $Version) } | Select-Object -First 1
    if (-not $target) {
        Write-Warning "未安装版本 '$Version'。已装版本：$(($versions | Sort-Object Name | ForEach-Object { $_.Display }) -join ', ')"
        Write-Host '  安装：bootstrap.ps1 -Only 20' -ForegroundColor Yellow
        return
    }
}

if (-not $target.HasActivation) {
    Write-Warning "版本 $($target.Name) 缺少 EIM 激活脚本：$($target.ActivationPath)"
    Write-Host '  可用 eim 修复：eim install -p <路径> 或 eim fix（见 README 5.8）' -ForegroundColor Yellow
    return
}

# --- 执行切换
Write-Host ("切换 ESP-IDF：{0} -> {1}" -f $(if ($currentName) { $currentName } else { '<未激活>' }), $target.Name) -ForegroundColor Cyan

Clear-IdfSession -Root $EspRoot
. $target.ActivationPath

if (-not $env:IDF_PATH) {
    Write-Warning '激活脚本执行后 IDF_PATH 仍为空，切换可能失败。'
    return
}

# 保险：EIM 激活脚本会把 IDF_TOOLS_PATH 写成本版本工具目录（...\tools），
# 但 idf_tools.py（EIM 的 tools.json 用 tools/<工具名> 前缀）要求容器根，否则 export 报 no installed versions。
$env:IDF_TOOLS_PATH = $EspRoot

# EIM 生成的激活脚本里路径是正反斜杠混用（D:/Dev/esp\tools\python\...）。
# 部分工具按字符串比对路径，混用会误报：
#   WARNING: Python interpreter "..." used to start idf.py is not from installed venv "..."
# 这里统一成正斜杠转反斜杠，不改变语义、只消除误判。
foreach ($v in @('IDF_PATH', 'IDF_PYTHON_ENV_PATH', 'IDF_TOOLS_PATH')) {
    $val = [System.Environment]::GetEnvironmentVariable($v, 'Process')
    if ($val) {
        [System.Environment]::SetEnvironmentVariable($v, $val.Replace('/', '\'), 'Process')
    }
}

# 补齐 constraints：idf.py 在 $IDF_TOOLS_PATH 根目录找 espidf.constraints.v<版本>.txt，
# 而 EIM 把该文件放在 $IDF_TOOLS_PATH\tools\ 下。缺了会报
# "espidf.constraints.vX.Y.txt doesn't exist. Perhaps you've forgotten to run the install scripts"。
foreach ($c in (Get-ChildItem -LiteralPath (Join-Path $EspRoot 'tools') -Filter 'espidf.constraints.*.txt' -File -ErrorAction SilentlyContinue)) {
    $dstFile = Join-Path $EspRoot $c.Name
    if (-not (Test-Path -LiteralPath $dstFile)) {
        try { Copy-Item -LiteralPath $c.FullName -Destination $dstFile -Force } catch { }
    }
}

# 同步 EIM 选中项，让 VSCode ESP-IDF 扩展 / eim list 指向同一版本
$eim = Resolve-EimExe -Root $EspRoot
if ($eim) {
    # 原生命令写 stderr 时，在 $ErrorActionPreference='Stop' 下会变成 terminating error，
    # 这里局部放宽，避免 eim 的任何提示文字中断切换。
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # 必须显式 --esp-idf-json-path：eim 的 list/select 默认读写 C:\Espressif\tools\eim_idf.json，
        # 而 VSCode 扩展读的是 idf.eimIdfJsonPath 钉死的 D 盘那份。
        # 不指定就会出现「终端切了版本、IDE 仍认为旧版本」（实测 select 只改 C 盘、D 盘纹丝不动）。
        & $eim select $target.Name --esp-idf-json-path (Join-Path $EspRoot 'tools') 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "  已同步 eim select $($target.Name)（写入 $EspRoot\tools\eim_idf.json）" -ForegroundColor DarkGray }
        else { Write-Host "  eim select $($target.Name) 返回 $LASTEXITCODE（不影响当前会话）" -ForegroundColor DarkGray }
    } catch {
        Write-Host '  eim select 跳过（eim 调用失败）' -ForegroundColor DarkGray
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

# 持久化（默认）——让新终端 / 重启后的 VSCode 落在同一版本
if (-not $SessionOnly) {
    Set-IdfUserEnv -IdfPath $env:IDF_PATH -VenvPath $env:IDF_PYTHON_ENV_PATH `
                   -ToolsRoot $EspRoot -IdfVersion $env:ESP_IDF_VERSION -IdfVersionFull $env:IDF_VERSION
    Write-Host '  已写入用户级环境变量（新终端默认该版本）；不想持久化请加 -SessionOnly' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host ("当前版本：{0}" -f $target.Name) -ForegroundColor Green
Write-Host ("  IDF_PATH       : {0}" -f $env:IDF_PATH)
Write-Host ("  IDF_TOOLS_PATH : {0}" -f $env:IDF_TOOLS_PATH)
Write-Host ("  IDF_PYTHON_ENV : {0}" -f $env:IDF_PYTHON_ENV_PATH)
if ($env:ESP_IDF_VERSION) { Write-Host ("  ESP_IDF_VERSION: {0}" -f $env:ESP_IDF_VERSION) }
Write-Host ''
Write-Host '  验证：idf.py --version' -ForegroundColor DarkGray
