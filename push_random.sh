#!/usr/bin/env bash
set -euo pipefail

# Go to the repo root (fails if not inside a git repo)
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$repo_root"

# Ensure test/ exists
mkdir -p test

# Date-based filename (add a time suffix if today's file already exists)
today="$(date +%F)"
outfile="test/test-${today}.txt"
if [[ -e "$outfile" ]]; then
  outfile="test/test-${today}-$(date +%H%M%S).txt"
fi

# Generate 50 random "words"
generate_words() {
  local n="$1"
  if command -v shuf >/dev/null 2>&1 && [[ -f /usr/share/dict/words ]]; then
    # Linux: dictionary + shuf
    shuf -n "$n" /usr/share/dict/words | tr '\n' ' ' | sed 's/ *$/\n/'
  elif command -v gshuf >/dev/null 2>&1 && [[ -f /usr/share/dict/words ]]; then
    # macOS with coreutils: gshuf
    gshuf -n "$n" /usr/share/dict/words | tr '\n' ' ' | sed 's/ *$/\n/'
  else
    # Portable fallback: random 4–8 letter tokens
    awk -v N="$n" '
      function randword(  len,i,chars,w) {
        chars="abcdefghijklmnopqrstuvwxyz"
        len = int(4 + rand()*5)   # 4..8
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

# Write the file
generate_words 50 > "$outfile"
echo "Wrote: $outfile"

# Add, commit, push
git add -A
git commit -m "Add $(basename "$outfile") with 50 random words"

# Push (set upstream if not set)
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git push
else
  git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
fi

echo "Pushed commit containing $outfile"

