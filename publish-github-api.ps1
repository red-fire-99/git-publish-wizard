# ============================================================
#  GitHub 一键发布向导（Windows / PowerShell）
#
#  两条发布通道：
#    A) git push 通道  —— publish-github.ps1    （网络正常时最直接）
#    B) GitHub API 通道 —— publish-github-api.ps1 + publish-via-api.mjs
#                          （github.com 连不通、但 api.github.com 可用时）
#
#  设计要点:
#    - 全中文提问，每项都有默认值，可直接回车
#    - Token 只在内存中使用一次，不写入任何文件或 .git/config
#    - API 通道生成的 commit SHA 与本地完全一致，网络恢复后可正常 fetch/pull/push
#    - 账号可自动探测（origin 远程地址 / git noreply 邮箱），不硬编码任何人
# ============================================================
param(
  [string]$User = '',            # GitHub 用户名（留空=自动探测或询问）
  [string]$Repo = '',            # 仓库名（留空=询问）
  [string]$Visibility = 'public',
  [string]$Description = '',
  [string]$Topics = 'windows,powershell,git,github,publish',
  [string]$RepoDir = ''          # 要发布的 git 仓库目录（默认=本脚本所在目录）
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = if ($RepoDir) { (Resolve-Path -LiteralPath $RepoDir).Path } else { $here }
$node = @((Join-Path $repoDir 'node\node.exe'), (Join-Path $here 'node\node.exe'), 'node') |
  Where-Object { $_ -eq 'node' -or (Test-Path $_) } | Select-Object -First 1
if (-not (Test-Path $node)) { Write-Host '缺少便携 Node.js，请先运行 launcher\setup.cmd' -ForegroundColor Red; exit 1 }

function Call-Api {
  param([string]$Method, [string]$Uri, $Body, $Headers)
  $h = $Headers
  $params = @{ Method = $Method; Uri = $Uri; Headers = $h; TimeoutSec = 25 }
  if ($null -ne $Body) {
    $params['ContentType'] = 'application/json; charset=utf-8'
    $params['Body'] = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5 -Compress))
  }
  Invoke-RestMethod @params
}

# ---------- 步骤 0: 识别 GitHub 账号与仓库名（能自动识别就自动） ----------
$gitProbe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitProbe) {
  foreach ($c in @("$env:USERPROFILE\dev-tools\mingit\cmd\git.exe", "$env:ProgramFiles\Git\cmd\git.exe")) {
    if (Test-Path $c) { $gitProbe = $c; break }
  }
}
$guessUser = ''
if ($gitProbe) {
  try {
    $u = (& $gitProbe -C $repoDir remote get-url origin 2>$null | Select-Object -First 1)
    if ($u -and $u -match 'github\.com[:/]+([\w.-]+)/') { $guessUser = $Matches[1] }
    if (-not $guessUser) {
      $m = (& $gitProbe -C $repoDir config user.email 2>$null | Select-Object -First 1)
      if ($m -and $m -match '^([\w.-]+)@users\.noreply\.github\.com$') { $guessUser = $Matches[1] }
    }
  } catch { }
}
if (-not $User) {
  $tip = if ($guessUser) { "GitHub 用户名（直接回车 = $guessUser）" } else { 'GitHub 用户名' }
  $User = Read-Host $tip
  if (-not $User) { $User = $guessUser }
}
if (-not $User) { Write-Host '缺少 GitHub 用户名，已取消。' -ForegroundColor Red; exit 1 }
if (-not $Repo) {
  $defaultRepo = Split-Path -Leaf $repoDir
  $Repo = Read-Host "仓库名（直接回车 = $defaultRepo）"
  if (-not $Repo) { $Repo = $defaultRepo }
}
Write-Host ("  目标: $User/$Repo    本地目录: $repoDir")

Write-Host '=== 1/4  检查网络与仓库 ===' -ForegroundColor Cyan
try {
  Invoke-RestMethod -Uri 'https://api.github.com/rate_limit' -Headers @{ 'User-Agent' = 'check' } -TimeoutSec 10 | Out-Null
  Write-Host 'api.github.com 可访问'
} catch {
  Write-Host ('api.github.com 不可访问: ' + $_.Exception.Message) -ForegroundColor Red
  Write-Host '本通道依赖 API，请先确保 api.github.com 能连通（或配置代理）。'
  exit 1
}

Write-Host ''
Write-Host '=== 2/4  填写 Token ===' -ForegroundColor Cyan
Write-Host '打开 https://github.com/settings/tokens/new'
Write-Host 'Note 随便填，Expiration 选 30 days，勾选 repo，Generate token 后复制（只显示一次）'
$sec = Read-Host '粘贴 Token（输入不可见，直接粘贴后回车）' -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $sec).Password
if (-not $token) { Write-Host '未提供 Token，已取消。' -ForegroundColor Red; exit 1 }
$headers = @{ 'User-Agent' = 'git-publish-wizard'; 'Authorization' = "Bearer $token"; 'Accept' = 'application/vnd.github+json' }
$api = "https://api.github.com/repos/$User/$Repo"

Write-Host ''
Write-Host '=== 3/4  准备远端仓库 ===' -ForegroundColor Cyan
$repoInfo = $null
try { $repoInfo = Call-Api -Method 'GET' -Uri $api -Headers $headers } catch { }
if (-not $repoInfo) {
  Write-Host "远端仓库不存在，正在创建 $User/$Repo ..."
  $repoInfo = Call-Api -Method 'POST' -Uri 'https://api.github.com/user/repos' -Headers $headers `
    -Body @{ name = $Repo; description = $Description; private = ($Visibility -eq 'private'); auto_init = $false; has_wiki = $false }
  Write-Host ('已创建: ' + $repoInfo.html_url) -ForegroundColor Green
} else {
  Write-Host ('远端仓库已存在: ' + $repoInfo.html_url)
}
# 空仓库无法直接使用 Git Data API（返回 409），先建一个占位提交
$commits = @()
try { $commits = @(Call-Api -Method 'GET' -Uri "$api/commits?per_page=1" -Headers $headers) } catch { }
if ($commits.Count -eq 0) {
  Write-Host '远端为空仓库，先创建占位提交（稍后会被正式历史替换）...'
  $ph = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('placeholder'))
  Call-Api -Method 'PUT' -Uri "$api/contents/.gitkeep" -Headers $headers `
    -Body @{ message = 'chore: 初始化仓库'; content = $ph; branch = 'main' } | Out-Null
  Write-Host '占位提交已创建。'
}
if ($Topics) {
  try {
    Call-Api -Method 'PUT' -Uri "$api/topics" -Headers $headers `
      -Body @{ names = @($Topics -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } | Out-Null
    Write-Host 'Topics 已设置'
  } catch { Write-Host ('Topics 设置失败: ' + $_.Exception.Message) -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '=== 4/4  同步提交历史（blob / tree / commit / 分支） ===' -ForegroundColor Cyan
$env:GITHUB_TOKEN = $token
& $node (Join-Path $here 'publish-via-api.mjs') --repo "$User/$Repo" --repo-dir "$repoDir"
$code = $LASTEXITCODE
$env:GITHUB_TOKEN = $null
$token = $null

if ($code -ne 0) { Write-Host '发布失败，请把上面的错误信息发出来。' -ForegroundColor Red; exit 1 }
Write-Host ''
Write-Host '✔ 发布完成' -ForegroundColor Green
Write-Host ('  仓库: https://github.com/' + $User + '/' + $Repo)
Write-Host ''
Write-Host '提醒: Token 只在本次运行内存中使用；若曾粘贴到聊天/脚本里，请到'
Write-Host '      https://github.com/settings/tokens 撤销它。'
