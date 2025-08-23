#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [REPEAT_COUNT]"
  echo "  REPEAT_COUNT: positive integer (default 1)"
}

# Parse args
if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

repeat="${1:-1}"
if ! [[ "$repeat" =~ ^[0-9]+$ ]] || [[ "$repeat" -le 0 ]]; then
  echo "Error: REPEAT_COUNT must be a positive integer." >&2
  usage
  exit 1
fi

# Go to repo root
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$repo_root"

mkdir -p test

today="$(date +%F)"
branch="$(git rev-parse --abbrev-ref HEAD)"

# Helper: generate 50 random words
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
        len = int(4 + rand()*5)
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

# Ensure upstream exists or set it on first push
ensure_push() {
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    git push
  else
    git push -u origin "$branch"
  fi
}

for (( i=1; i<=repeat; i++ )); do
  # Base filename for today; add a suffix if it already exists (to avoid clobbering)
  outfile="test/test-${today}.txt"
  if [[ -e "$outfile" ]]; then
    # Add time + sequence to guarantee uniqueness across rapid iterations
    outfile="test/test-${today}-$(date +%H%M%S)-$i.txt"
  fi

  generate_words 50 > "$outfile"
  echo "Wrote: $outfile"

  git add -A
  git commit -m "Add $(basename "$outfile") with 50 random words (commit $i/$repeat)"
  ensure_push
done

echo "Done: created $repeat file(s), committed, and pushed."
