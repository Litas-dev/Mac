#!/usr/bin/env bash
set -euo pipefail

out="${1:-server-tree.txt}"
start="$(pwd)"

root="$start"
i=0
while [ "$i" -lt 12 ]; do
  if [ -d "$root/.git" ]; then
    break
  fi
  if [ "$root" = "/" ]; then
    break
  fi
  root="$(cd "$root/.." && pwd)"
  i="$((i + 1))"
done
if [ ! -d "$root/.git" ]; then
  root="$start"
fi

{
  echo "date: $(date -Is 2>/dev/null || date)"
  echo "host: $(hostname)"
  echo "start: $start"
  echo "repo_root_guess: $root"
  echo
  echo "== repo_root ls =="
  ls -la "$root" 2>/dev/null || true
  echo
  echo "== find docker/caddy/nginx files (maxdepth 6) =="
  find "$root" -maxdepth 6 -type f \( \
    -name Dockerfile -o \
    -name docker-compose.yml -o \
    -name docker-compose.yaml -o \
    -name Caddyfile -o \
    -name caddyfile -o \
    -name nginx.conf \
  \) -print 2>/dev/null || true
  echo
  echo "== find known app folders (maxdepth 6) =="
  find "$root" -maxdepth 6 -type d \( -name kivana-api -o -name pf-desktop -o -name website \) -print 2>/dev/null || true
  echo
  echo "== find git roots (maxdepth 4) =="
  find "$root" -maxdepth 4 -type d -name .git -print 2>/dev/null || true
} > "$out"

printf 'Wrote %s\n' "$out"
