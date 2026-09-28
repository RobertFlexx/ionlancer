#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GAME="$ROOT/ionlancer"
backend=auto

usage() {
  echo "usage: ./run.sh [--auto|--cocoa|--x11|--wayland]"
  echo
  echo "  --auto     let SDL2 pick the best video driver (default)"
  echo "  --cocoa    macOS native windows"
  echo "  --x11      X11 (Linux, or macOS with XQuartz installed)"
  echo "  --wayland  Wayland (Linux only)"
}

host_is_macos() {
  [ "$(uname -s 2>/dev/null || echo unknown)" = Darwin ]
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto) backend=auto ;;
    --cocoa) backend=cocoa ;;
    --x11) backend=x11 ;;
    --wayland) backend=wayland ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -x "$GAME" ] || { echo "ionlancer is not built; run: make release" >&2; exit 1; }

# macOS only has the native cocoa driver. x11/wayland there means XQuartz or a
# Wayland compositor, which is a special request, so say so instead of letting
# SDL fail with something cryptic.
if host_is_macos; then
  case "$backend" in
    wayland)
      echo "error: there is no Wayland video driver on macOS." >&2
      echo "       try: ./run.sh --auto   (or --cocoa)" >&2
      exit 2
      ;;
    x11)
      if [ ! -d /opt/X11 ]; then
        echo "error: --x11 needs XQuartz on macOS, which does not look installed." >&2
        echo "       install it with: brew install --cask xquartz" >&2
        echo "       or just run: ./run.sh --auto" >&2
        exit 2
      fi
      ;;
  esac
fi

case "$backend" in
  cocoa)
    export SDL_VIDEODRIVER=cocoa
    unset SDL_RENDER_DRIVER 2>/dev/null || true
    ;;
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

# The game reads its assets through relative paths, so the working directory
# has to be the repository root no matter where it was launched from.
cd "$ROOT"

# Linux dynamic-loader fixup. Meaningless on macOS, where the loader is the
# kernel and there is no ELF interpreter to reconcile.
if [ "$(uname -s 2>/dev/null || echo unknown)" = Linux ]; then
  game_interp=$(elf_interpreter "$GAME")
  if [ -n "$game_interp" ] && [ ! -x "$game_interp" ]; then
    host_sh=$(command -v sh 2>/dev/null || true)
    host_interp=
    [ -n "$host_sh" ] && host_interp=$(elf_interpreter "$host_sh")
    if [ -n "$host_interp" ] && [ -x "$host_interp" ]; then
      exec "$host_interp" "$GAME"
    fi
    echo "missing ELF loader: $game_interp" >&2
    exit 126
  fi
fi

exec "$GAME"
