# git-publish-wizard · GitHub 一键发布向导（Windows）

把本地一个已经是 git 仓库的文件夹，**双击 + 回答几个问题**就发布到 GitHub。
全程中文提问，每项都有默认值，不懂 git 也能用。

## 两种发布通道

| 通道 | 入口 | 适用场景 |
| --- | --- | --- |
| git push 通道 | `publish-github.cmd` | 网络正常，能连 `github.com` |
| **GitHub API 通道** | `publish-github-api.cmd` | `github.com:443` 连不通（国内常见），但 `api.github.com` 可用 |

## 快速开始

1. 确认目标文件夹已经是 git 仓库（有 `.git` 目录）。
   如果还不是：装 [Git for Windows](https://git-scm.com/download/win) → 在该目录执行一次
   `git init` 并至少提交一次。
2. 双击 `publish-github.cmd`（网络正常）或 `publish-github-api.cmd`（网络受限）。
3. 按提示走：
   - 提交身份（名字 / 邮箱；没有就填，建议用 `<用户名>@users.noreply.github.com`）
   - GitHub 用户名（能自动探测则直接回车）
   - 仓库名（默认取文件夹名）
   - 公开 `public` / 私有 `private`
   - 选 `A` 用 Token 全自动建仓库，或选 `B` 自己在网页建空仓库
     （**不要勾选** README / .gitignore / license）
4. 看到 `✔ 发布成功` 即可。

## 关于 Token

- 在 <https://github.com/settings/tokens/new> 生成：Note 随便填，Expiration 选一个期限，
  勾选 **repo**。
- **只在内存里用一次**：不会写入任何文件，也不会写进 `.git/config`。
- 用完建议去 <https://github.com/settings/tokens> 撤销；若你曾把它粘贴到聊天/脚本里，**务必撤销**。
- 完全不想用 Token？用 GitHub Desktop（`File → Open existing repository` → `Publish`）也能发布。

## API 通道是怎么绕过网络限制的

GitHub 的两套入口是独立的：

- **git 通道**：`github.com`（git 协议 / HTTPS smart HTTP）—— 国内经常连不通；
- **API 通道**：`api.github.com`（REST + Git Data API）—— 通常可访问。

本工具的 API 通道用 Git Data API 依次创建 `blob` → `tree` → `commit` → 分支引用。
关键在于**用与本地 git 完全相同的内容、作者时间与时区构造对象**，因此算出的对象哈希
（blob / tree / commit SHA）与本地仓库完全相同 —— 网络恢复后可以正常
`git fetch` / `git pull` / `git push`，不会出现「历史分叉、只能强推」。

## 常用参数

```powershell
# 指定目标仓库目录（默认为脚本所在目录）
powershell -File publish-github.ps1 -RepoDir C:\path\to\your\project

# 预填参数（非交互场景）
powershell -File publish-github.ps1 -User octocat -RepoName my-tool `
        -DisplayName "Your Name" -Email you@example.com -Visibility private

# 只做离线自检（把当前提交推到临时本地裸仓库，验证 git 链路，不联网）
powershell -File publish-github.ps1 -SelfTest

# API 通道底层脚本也可单独使用（需要 Node.js）
$env:GITHUB_TOKEN = 'ghp_xxx'
node publish-via-api.mjs --repo octocat/my-tool --repo-dir C:\path\to\project [--dry-run]
```

## 常见问题

- **push 一直不动 / 22 秒后超时** → 你的网络到 `github.com` 不通，改用 `publish-github-api.cmd`。
- **提示远程仓库不是空的** → GitHub 上已存在的仓库有内容。删掉重建（新建时不要勾任何初始化选项），或改推到一个新仓库名。
- **API 返回 409** → 目标仓库是空仓库时 Git Data API 不可用；本工具会自动先建一个占位提交再同步，通常无需手动处理。
- **想撤回发布** → 在 GitHub 仓库 Settings → Danger Zone → Delete repository。

## 免责声明与许可

非官方工具，与 GitHub 无关。请确认你有权发布所发布的代码与内容，并遵守各上游许可证。
本项目以 **MIT** 许可发布，见 [LICENSE](LICENSE)。
