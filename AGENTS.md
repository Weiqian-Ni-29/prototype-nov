# 开发工作流

本游戏在同一个固定的本机工作区开发，使用仓库的主检出目录。功能、修复、重构和开发文档都在这里编辑、运行、测试和提交。每个新需求先同步远端主分支，再在此工作区从最新的 `origin/main` 创建任务分支。

## 开始新需求

在固定工作区的仓库根目录执行以下 PowerShell 命令。将 `short-task-name` 换成当前需求的唯一短名。

```powershell
$taskSlug = 'short-task-name'
$workingChanges = git status --porcelain
if ($LASTEXITCODE -ne 0) { throw '请在 Git 仓库中执行。' }
if ($workingChanges) { throw '工作区有未提交改动，请先保存当前任务。' }

git fetch origin refs/heads/main:refs/remotes/origin/main
if ($LASTEXITCODE -ne 0) { throw '未能同步 origin/main，请解决同步问题后重试。' }

git switch -c "dev/$taskSlug" origin/main
if ($LASTEXITCODE -ne 0) { throw '未能创建任务分支，请检查分支名。' }
```

- 新需求复用这个工作区并使用独立任务分支。续做已有需求时，在同一目录切回该任务的分支。
- 切换分支前检查并保存已有改动。遇到同步失败或分支冲突时，先解决原因再开始新需求。
- 需要提交 PR 时，从任务分支向 `main` 发起。
