<# 
  Save as: push_random.ps1
  Usage:
    pwsh ./push_random.ps1             # 1 cycle
    pwsh ./push_random.ps1 -Repeat 3   # 3 cycles
#>

param(
  [int]$Repeat = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Repeat -le 0) { throw "Repeat must be a positive integer." }

function Invoke-Git([Parameter(Mandatory)][string[]]$Args) {
  & git @Args
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Args -join ' ') failed (exit $LASTEXITCODE)."
  }
}

function Invoke-Gh([Parameter(Mandatory)][string[]]$Args) {
  & gh @Args
  if ($LASTEXITCODE -ne 0) {
    throw "gh $($Args -join ' ') failed (exit $LASTEXITCODE)."
  }
}

# Ensure tools
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found in PATH." }
if (-not (Get-Command gh  -ErrorAction SilentlyContinue)) { throw "GitHub CLI 'gh' not found. Install: https://cli.github.com/" }
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw "'gh' not authenticated. Run: gh auth login" }

# Move to repo root
$repoRoot = (& git rev-parse --show-toplevel).Trim()
Set-Location $repoRoot

# Ensure we're on 'development'
& git show-ref --verify --quiet refs/heads/development
$localDev = ($LASTEXITCODE -eq 0)
if ($localDev) {
  Invoke-Git @('checkout','development')
} else {
  & git ls-remote --exit-code --heads origin development *> $null
  if ($LASTEXITCODE -eq 0) {
    Invoke-Git @('checkout','-b','development','--track','origin/development')
  } else {
    Invoke-Git @('checkout','-b','development')
  }
}

$branch = (& git rev-parse --abbrev-ref HEAD).Trim()

# Initial pull (if upstream exists)
& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' *> $null
if ($LASTEXITCODE -eq 0) {
  # Try with --autostash, fallback for older Git
  & git pull --rebase --autostash 2>$null
  if ($LASTEXITCODE -ne 0) {
    Invoke-Git @('-c','rebase.autoStash=true','pull','--rebase')
  }
} else {
  Write-Host "No upstream for '$branch' yet; skipping initial pull."
}

# Ensure test/ exists
New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot 'test') | Out-Null
$today   = Get-Date -Format 'yyyy-MM-dd'

function New-RandomWord([int]$Length) {
  $letters = 'a'..'z'
  -join (1..$Length | ForEach-Object { $letters[ (Get-Random -Min 0 -Max $letters.Length) ] })
}
function Get-RandomWords([int]$Count) {
  -join (1..$Count | ForEach-Object { New-RandomWord (Get-Random -Min 4 -Max 9) }) -replace '(?<=\w)(?=\w)',' '
}

function Ensure-Push([string]$Branch) {
  & git rev-parse --abbrev-ref --symbolic-full-name '@{u}' *> $null
  if ($LASTEXITCODE -eq 0) {
    Invoke-Git @('push')
  } else {
    Invoke-Git @('push','-u','origin',$Branch)
  }
}

function Get-OrCreatePRNumber([string]$Head,[string]$Base='main') {
  $prJson = (& gh pr list --head $Head --base $Base --state open --json number)
  if ($LASTEXITCODE -eq 0 -and $prJson) {
    $prs = $prJson | ConvertFrom-Json
    if ($prs -and $prs.Count -ge 1) { return $prs[0].number }
  }
  $title = "Merge $Head into $Base - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  Invoke-Gh @('pr','create','--base',$Base,'--head',$Head,'--title',$title,'--body','Automated PR created by script.')
  $viewJson = (& gh pr view --json number)
  (($viewJson | ConvertFrom-Json).number)
}

function Merge-PR([int]$Number) {
  # Try merge commit; --admin allows bypass where you have permission
  & gh pr merge $Number --merge --admin --yes
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to merge PR #$Number. Check required reviews/checks/branch protection."
  }
}

for ($i = 1; $i -le $Repeat; $i++) {
  # Unique filename per iteration
  $baseOut = Join-Path $repoRoot "test/test-$today.txt"
  if (Test-Path $baseOut) {
    $suffix  = "$(Get-Date -Format 'HHmmss')-$i"
    $outfile = Join-Path $repoRoot "test/test-$today-$suffix.txt"
  } else {
    $outfile = $baseOut
  }

  $content = Get-RandomWords 50
  Set-Content -Path $outfile -Value $content
  Write-Host "Wrote: $outfile"

  Invoke-Git @('add','-A')
  $msg = "Add $(Split-Path $outfile -Leaf) with 50 random words (development, commit $i/$Repeat)"
  Invoke-Git @('commit','-m', $msg)

  Ensure-Push -Branch $branch

  # Open PR to main, merge it, then pull in development
  $prNum = Get-OrCreatePRNumber -Head $branch -Base 'main'
  Write-Host "Opened/Found PR #$prNum from '$branch' to 'main'."
  Merge-PR -Number $prNum
  Write-Host "Merged PR #$prNum."

  # Pull latest on development after merge
  & git pull --rebase --autostash 2>$null
  if ($LASTEXITCODE -ne 0) {
    Invoke-Git @('-c','rebase.autoStash=true','pull','--rebase')
  }
}

Write-Host "Done on branch '$branch': created $Repeat file(s), each committed, PR'd to main, merged, and pulled."
