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

# --- Ensure we're on the development branch ---
if git show-ref --verify --quiet refs/heads/development; then
  git checkout development
elif git ls-remote --exit-code --heads origin development >/dev/null 2>&1; then
  git checkout -b development --track origin/development
else
  git checkout -b development
fi

branch="$(git rev-parse --abbrev-ref HEAD)"

# --- PULL AT THE VERY BEGINNING (on development) ---
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  # Pull latest; auto-stash if supported
  if ! git pull --rebase --autostash; then
    # Fallback for older git without --autostash
    git -c rebase.autoStash=true pull --rebase
  fi
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
done

echo "Done on branch '$branch': created $repeat file(s), committed, and pushed."
