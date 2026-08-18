#!/bin/sh
set -eu

MODE=${1:-release}
TARGET=${2:-ionlancer}
GM2=${GM2:-gm2}
PKG_CONFIG=${PKG_CONFIG:-pkg-config}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

command -v "$GM2" >/dev/null 2>&1 || { echo "error: gm2 not found" >&2; exit 1; }
command -v "$PKG_CONFIG" >/dev/null 2>&1 || { echo "error: pkg-config not found" >&2; exit 1; }
"$PKG_CONFIG" --exists sdl2 || { echo "error: SDL2 development files not found (pkg-config sdl2)" >&2; exit 1; }

SDL_CFLAGS=$($PKG_CONFIG --cflags sdl2)
SDL_PKG_LIBS=$($PKG_CONFIG --libs sdl2)
SDL_LIBDIR=$($PKG_CONFIG --variable=libdir sdl2 2>/dev/null || true)
SDL_LIBFILE=

find_sdl_file() {
  [ -n "$SDL_LIBDIR" ] || return 1

  case $(uname -s 2>/dev/null || echo unknown) in
    Darwin)
      for candidate in "$SDL_LIBDIR/libSDL2.dylib" "$SDL_LIBDIR"/libSDL2-2.0.*.dylib; do
        if [ -f "$candidate" ] || [ -L "$candidate" ]; then
          SDL_LIBFILE=$candidate
          return 0
        fi
      done
      ;;
    *)
      for candidate in "$SDL_LIBDIR/libSDL2.so" "$SDL_LIBDIR"/libSDL2-2.0.so.*; do
        if [ -f "$candidate" ] || [ -L "$candidate" ]; then
          SDL_LIBFILE=$candidate
          return 0
        fi
      done
      ;;
  esac
  return 1
}

find_sdl_file || true

elf_interpreter() {
  elf=$1
  if command -v patchelf >/dev/null 2>&1; then
    patchelf --print-interpreter "$elf" 2>/dev/null || true
    return 0
  fi
  if command -v readelf >/dev/null 2>&1; then
    readelf -l "$elf" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' | head -n 1
    return 0
  fi
  return 0
}

HOST_INTERP=
DYNAMIC_LINKER_FLAG=
if [ "$(uname -s 2>/dev/null || echo unknown)" = "Linux" ]; then
  HOST_SH=$(command -v sh 2>/dev/null || true)
  if [ -n "$HOST_SH" ]; then
    HOST_INTERP=$(elf_interpreter "$HOST_SH")
  fi
  if [ -n "$HOST_INTERP" ] && [ -x "$HOST_INTERP" ]; then
    DYNAMIC_LINKER_FLAG="-Wl,--dynamic-linker=$HOST_INTERP"
  else
    HOST_INTERP=
  fi
fi

case "$MODE" in
  release)
    OPTFLAGS="-O3"
    OUT="$TARGET"
    ;;
  aggressive)
    OPTFLAGS="-O3 -flto -fm2-whole-program"
    OUT="$TARGET"
    ;;
  debug)
    OPTFLAGS="-O0 -g -fsoft-check-all"
    OUT="$TARGET-debug"
    ;;
  *)
    echo "error: unknown build mode: $MODE" >&2
    exit 2
    ;;
esac

BUILDDIR="build/$MODE"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"

COMMON="-fpim4 -I src -Wall $SDL_CFLAGS"
MODULES="RNG FrameBuffer Input Audio Visuals Game Platform"
OBJECTS=

printf '%s\n' "== IONLANCER gcc16-ready-28: $MODE =="

for module in $MODULES; do
  obj="$BUILDDIR/$module.o"
  "$GM2" $COMMON $OPTFLAGS -c "src/$module.mod" -o "$obj"
  OBJECTS="$OBJECTS $obj"
done

MAINOBJ="$BUILDDIR/Main.o"
"$GM2" $COMMON $OPTFLAGS -c -fscaffold-main src/Main.mod -o "$MAINOBJ"

link_normal() {
  "$GM2" -fpim4 $OPTFLAGS "$MAINOBJ" $OBJECTS -o "$OUT" $DYNAMIC_LINKER_FLAG $SDL_PKG_LIBS
}

stage_sdl() {
  [ -n "$SDL_LIBFILE" ] || return 1
  case $(uname -s 2>/dev/null || echo unknown) in
    Darwin) SDL_STAGE_FILE="$BUILDDIR/libSDL2-link.dylib" ;;
    *)      SDL_STAGE_FILE="$BUILDDIR/libSDL2-link.so" ;;
  esac

  cp -L "$SDL_LIBFILE" "$SDL_STAGE_FILE"
  test -s "$SDL_STAGE_FILE" || {
    echo "error: staged SDL2 library is empty" >&2
    return 1
  }
}

make_staged_flags() {
  SDL_AUX_FLAGS=
  for flag in $SDL_PKG_LIBS; do
    if [ "$flag" != "-lSDL2" ]; then
      SDL_AUX_FLAGS="$SDL_AUX_FLAGS $flag"
    fi
  done
}

link_staged() {
  stage_sdl || {
    echo "error: normal SDL2 link failed and no concrete SDL2 shared library could be staged" >&2
    return 1
  }
  make_staged_flags

  ELF_ALLOW=
  case $(uname -s 2>/dev/null || echo unknown) in
    Linux) ELF_ALLOW="-Wl,--allow-shlib-undefined" ;;
  esac

  "$GM2" -fpim4 $OPTFLAGS "$MAINOBJ" $OBJECTS -o "$OUT" $DYNAMIC_LINKER_FLAG $SDL_AUX_FLAGS $ELF_ALLOW "$SDL_STAGE_FILE"
}

if link_normal; then
  :
else
  rm -f "$OUT"
  printf '%s\n' 'SDL2 link retry' >&2
  link_staged
fi

if [ "$(uname -s 2>/dev/null || echo unknown)" = "Linux" ]; then
  GAME_INTERP=$(elf_interpreter "./$OUT")
  if [ -n "$GAME_INTERP" ]; then
    if [ ! -x "$GAME_INTERP" ]; then
      echo "error: linked executable names a missing ELF interpreter: $GAME_INTERP" >&2
      exit 1
    fi
  fi
fi

if [ "$(uname -s 2>/dev/null || echo unknown)" = "Linux" ] && command -v ldd >/dev/null 2>&1; then
  if LDD_OUT=$(ldd "./$OUT" 2>&1); then
    :
  else
    echo "error: ldd could not inspect the linked executable:" >&2
    printf '%s\n' "$LDD_OUT" >&2
    exit 1
  fi
  if printf '%s\n' "$LDD_OUT" | grep -F "not found" >/dev/null 2>&1; then
    echo "error: linked successfully, but runtime shared libraries are missing:" >&2
    printf '%s\n' "$LDD_OUT" | grep -F "not found" >&2 || true
    exit 1
  fi
fi

printf '%s\n' "built $OUT"
