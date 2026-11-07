# 开发工作流

本仓库的主分支是 `main`，远端为 `origin`。每个新需求都必须先同步远端主分支，再从最新的 `origin/main` 创建专用分支和独立 Git worktree。功能、修复、重构和开发文档都遵循此流程。

## 开始新需求

在任一现有仓库工作目录中执行以下 PowerShell 命令。将 `short-task-name` 换成当前需求的唯一短名。

```powershell
$taskSlug = 'short-task-name'
$repoRoot = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { throw '请在 Git 仓库中执行。' }
$worktreePath = Join-Path (Split-Path -Parent $repoRoot) "prototype-nov-$taskSlug"

git fetch origin refs/heads/main:refs/remotes/origin/main
if ($LASTEXITCODE -ne 0) { throw '未能同步 origin/main，请解决同步问题后重试。' }

git worktree add -b "dev/$taskSlug" "$worktreePath" origin/main
if ($LASTEXITCODE -ne 0) { throw '未能创建任务 worktree，请检查分支名和目录是否已存在。' }

Set-Location -LiteralPath $worktreePath
```

- 新需求的编辑、运行、测试和提交都在该需求的 worktree 内进行。续做同一需求时回到它原有的 worktree。
- 遇到同步失败或分支、目录冲突时先处理原因。每个新需求使用新分支和新目录，保留已有工作区及其未提交改动。
- 需要提交 PR 时，从任务分支向 `main` 发起。完成后先核对 worktree 状态，再清理已结束且无未提交改动的工作区。
