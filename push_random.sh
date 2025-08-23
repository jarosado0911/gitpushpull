#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [REPEAT_COUNT]"
  echo "  REPEAT_COUNT: positive integer (default 1)"
}

# Parse args
if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage; exit 0
fi
repeat="${1:-1}"
if ! [[ "$repeat" =~ ^[0-9]+$ ]] || [[ "$repeat" -le 0 ]]; then
  echo "Error: REPEAT_COUNT must be a positive integer." >&2
  usage; exit 1
fi

# Go to repo root
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$repo_root"

# Ensure GitHub CLI is available and authenticated (needed for PR + merge)
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI 'gh' is required. Install from https://cli.github.com/." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "Error: 'gh' is not authenticated. Run: gh auth login" >&2
  exit 1
fi

# --- Ensure we're on the development branch ---
if git show-ref --verify --quiet refs/heads/development; then
  git checkout development
elif git ls-remote --exit-code --heads origin development >/dev/null 2>&1; then
  git checkout -b development --track origin/development
else
  git checkout -b development
fi

branch="$(git rev-parse --abbrev-ref HEAD)"

# --- Pull latest on development at the very beginning ---
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git pull --rebase --autostash 2>/dev/null || git -c rebase.autoStash=true pull --rebase
else
  echo "No upstream set for '$branch' yet; skipping initial pull."
fi

mkdir -p test
today="$(date +%F)"

# Helper: generate N random words
generate_words() {
  local n="$1"
  if command -v shuf >/dev/null 2>&1 && [[ -f /usr/share/dict/words ]]; then
    shuf -n "$n" /usr/share/dict/words | tr '\n' ' ' | sed 's/ *$/\n/'
  elif command -v gshuf >/dev/null 2>&1 && [[ -f /usr/share/dict/words ]]; then
    gshuf -n "$n" /usr/share/dict/words | tr '\n' ' ' | sed 's/ *$/\n/'
  else
    awk -v N="$n" '
      function randword(  len,i,chars,w) {
        chars="abcdefghijklmnopqrstuvwxyz"
        len = int(4 + rand()*5)  # 4..8
        w=""
        for (i=1;i<=len;i++) w = w substr(chars, int(rand()*26)+1, 1)
        return w
      }
      BEGIN {
        srand()
        for (i=1;i<=N;i++) printf "%s%s", randword(), (i<N?" ":"\n")
      }
    '
  fi
}

ensure_push() {
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    git push
  else
    git push -u origin "$branch"
  fi
}

open_or_get_pr_number() {
  # Try to find an open PR from development -> main
  local pr_num
  pr_num="$(gh pr list --head "$branch" --base main --state open --json number -q '.[0].number' || true)"
  if [[ -z "${pr_num}" ]]; then
    # Create a PR (uses current branch as head)
    local title="Merge ${branch} into main - $(date '+%Y-%m-%d %H:%M:%S')"
    local body="Automated PR created by script."
    gh pr create --base main --head "$branch" --title "$title" --body "$body" >/dev/null
    # Retrieve its number
    pr_num="$(gh pr view --json number -q .number)"
  fi
  echo "$pr_num"
}

merge_pr() {
  local pr_num="$1"
  # Attempt a standard merge commit
  gh pr merge "$pr_num" --merge --admin --yes || {
    echo "Error: Failed to merge PR #$pr_num. Check branch protection, required checks, or conflicts." >&2
    exit 1
  }
}

for (( i=1; i<=repeat; i++ )); do
  # Unique filename per iteration
  outfile="test/test-${today}.txt"
  if [[ -e "$outfile" ]]; then
    outfile="test/test-${today}-$(date +%H%M%S)-$i.txt"
  fi

  generate_words 50 > "$outfile"
  echo "Wrote: $outfile"

  git add -A
  git commit -m "Add $(basename "$outfile") with 50 random words (development, commit $i/$repeat)"
  ensure_push

  # --- Open PR -> main, merge it, then pull on development ---
  pr_num="$(open_or_get_pr_number)"
  echo "Opened/Found PR #$pr_num from '$branch' to 'main'."
  merge_pr "$pr_num"
  echo "Merged PR #$pr_num."

  # Pull development again after merge
  git pull --rebase --autostash 2>/dev/null || git -c rebase.autoStash=true pull --rebase
done

echo "Done on branch '$branch': created $repeat file(s), each committed, PR'd to main, merged, and pulled."
