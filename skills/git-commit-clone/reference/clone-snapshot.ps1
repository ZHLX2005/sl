# clone-snapshot.ps1 — 创建项目快照（浅克隆 --depth=1）
# 用法: powershell -ExecutionPolicy Bypass -File clone-snapshot.ps1
# 自动: 被 post-commit hook 调用
# 手动: Claude skill "run" 命令调用

param(
    [int]$KeepSnapshots = 10
)

$ErrorActionPreference = "Stop"

# ── 检测项目根目录 ──────────────────────────────
$ProjectRoot = git rev-parse --show-toplevel 2>$null
if (-not $ProjectRoot) {
    Write-Host "[git-commit-clone] ERROR: not in a git repository"
    exit 1
}

# ── 收集快照元数据 ──────────────────────────────
$CommitHash = git rev-parse --short HEAD
$CommitMsg = git log -1 --pretty=%s
# 清理特殊字符
$CommitMsg = [regex]::Replace($CommitMsg, '[^\w\s-]', '')
if ($CommitMsg.Length -gt 80) { $CommitMsg = $CommitMsg.Substring(0, 80) }

$Timestamp = Get-Date -Format "yyyy-MM-dd"
$SnapshotName = "${Timestamp}-${CommitHash}"
$SnapshotDir = Join-Path $ProjectRoot ".claude\rep\project\$SnapshotName"
$IndexDir = Join-Path $ProjectRoot ".claude\rep\project"

# ── 跳过重复 ────────────────────────────────────
$MetaFile = Join-Path $SnapshotDir ".snapshot-meta.json"
if (Test-Path $SnapshotDir) -and (Test-Path $MetaFile) {
    Write-Host "[git-commit-clone] Snapshot already exists: $SnapshotName, skip"
    exit 0
}

New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null

# ── 浅克隆 ──────────────────────────────────────
Write-Host "[git-commit-clone] Creating snapshot: $SnapshotName"
try {
    git clone --depth 1 "file:///${ProjectRoot}" $SnapshotDir 2>&1 | Out-Null
}
catch {
    Write-Host "[git-commit-clone] WARNING: shallow clone failed, retrying..."
    if (Test-Path $SnapshotDir) { Remove-Item -Recurse -Force $SnapshotDir }
    git clone --depth 1 "file:///${ProjectRoot}" $SnapshotDir 2>&1 | Out-Null
}

# ── 写入快照元数据 ──────────────────────────────
$RemoteUrl = git remote get-url origin 2>$null
$MetaContent = @{
    id          = $CommitHash
    timestamp   = (Get-Date -Format "o")
    commit_short = $CommitHash
    commit_msg  = $CommitMsg
    remote_url  = $RemoteUrl
    path        = ".claude/repo/project/$SnapshotName"
}

$MetaContent | ConvertTo-Json | Set-Content -Path $MetaFile -Encoding UTF8

# ── 更新全局索引 ────────────────────────────────
$IndexFile = Join-Path $IndexDir "snapshots.json"
$LogFile = Join-Path $IndexDir "snapshots.log"

$LogEntry = "$(Get-Date -Format 'o') ${CommitHash} ${CommitMsg}"
Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8

if (Test-Path $IndexFile) {
    $Index = Get-Content $IndexFile -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $Index = @()
}

$NewEntry = @{
    id           = $CommitHash
    timestamp    = (Get-Date -Format "o")
    commit_short = $CommitHash
    commit_msg   = $CommitMsg
    path         = ".claude/repo/project/$SnapshotName"
}
$Index += $NewEntry
$Index | ConvertTo-Json -Depth 10 | Set-Content -Path $IndexFile -Encoding UTF8

Write-Host "[git-commit-clone] Snapshot saved: $SnapshotDir"

# ── 自动清理（保留最近 N 个） ──────────────────
$SnapDirs = Get-ChildItem -Path $IndexDir -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}-' } | Sort-Object Name
$Total = $SnapDirs.Count

if ($Total -gt $KeepSnapshots) {
    $ToDelete = $Total - $KeepSnapshots
    Write-Host "[git-commit-clone] Auto-pruning ${ToDelete} old snapshots (keep=${KeepSnapshots})"
    $SnapDirs | Select-Object -First $ToDelete | ForEach-Object {
        Remove-Item -Recurse -Force $_.FullName
    }

    # 重建索引
    $Remaining = Get-ChildItem -Path $IndexDir -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}-' } | Sort-Object Name -Descending
    $Rebuilt = @()
    foreach ($dir in $Remaining) {
        $metaFile = Join-Path $dir.FullName ".snapshot-meta.json"
        if (Test-Path $metaFile) {
            $meta = Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $Rebuilt += $meta
        }
    }
    $Rebuilt | ConvertTo-Json -Depth 10 | Set-Content -Path $IndexFile -Encoding UTF8
}
