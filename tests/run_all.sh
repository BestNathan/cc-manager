#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$HERE"/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || fail=1
done
exit "$fail"
