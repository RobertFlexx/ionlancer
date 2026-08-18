#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GAME="$ROOT/ionlancer"
backend=auto

usage() {
  echo "usage: ./run.sh [--auto|--x11|--wayland]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto) backend=auto ;;
    --x11) backend=x11 ;;
    --wayland) backend=wayland ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -x "$GAME" ] || { echo "ionlancer is not built" >&2; exit 1; }

case "$backend" in
  x11)
    export SDL_VIDEODRIVER=x11
    export SDL_RENDER_DRIVER=software
    export SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR=0
    ;;
  wayland)
    export SDL_VIDEODRIVER=wayland
    unset SDL_RENDER_DRIVER 2>/dev/null || true
    ;;
  auto)
    unset SDL_VIDEODRIVER 2>/dev/null || true
    unset SDL_RENDER_DRIVER 2>/dev/null || true
    ;;
esac

elf_interpreter() {
  elf=$1
  if command -v patchelf >/dev/null 2>&1; then
    patchelf --print-interpreter "$elf" 2>/dev/null || true
  elif command -v readelf >/dev/null 2>&1; then
    readelf -l "$elf" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' | head -n 1
  fi
}

if [ "$(uname -s 2>/dev/null || echo unknown)" = Linux ]; then
  game_interp=$(elf_interpreter "$GAME")
  if [ -n "$game_interp" ] && [ ! -x "$game_interp" ]; then
    host_sh=$(command -v sh 2>/dev/null || true)
    host_interp=
    [ -n "$host_sh" ] && host_interp=$(elf_interpreter "$host_sh")
    if [ -n "$host_interp" ] && [ -x "$host_interp" ]; then
      cd "$ROOT"
      exec "$host_interp" "$GAME"
    fi
    echo "missing ELF loader: $game_interp" >&2
    exit 126
  fi
fi

cd "$ROOT"
exec "$GAME"
