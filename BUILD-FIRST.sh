#!/bin/sh
set -eu
cd "$(dirname "$0")"
find . -type f -exec touch {} +
make clean
case "$(uname -s 2>/dev/null || true):$(uname -m 2>/dev/null || true)" in
  Linux:x86_64|Linux:amd64) make portable ;;
  *) make release ;;
esac
printf '\ndone\n'
