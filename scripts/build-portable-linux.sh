#!/bin/sh
set -eu

TARGET=${1:-ionlancer}
GM2=${GM2:-gm2}
PKG_CONFIG=${PKG_CONFIG:-pkg-config}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

[ "$(uname -s 2>/dev/null || echo unknown)" = "Linux" ] || {
  echo "error: portable-linux build is Linux-only" >&2
  exit 1
}

ARCH=$(uname -m 2>/dev/null || echo unknown)
case "$ARCH" in
  x86_64|amd64) ARCH=x86_64 ;;
  *)
    echo "error: portable-linux currently targets x86_64; host architecture is $ARCH" >&2
    exit 1
    ;;
esac

command -v "$GM2" >/dev/null 2>&1 || { echo "error: gm2 not found" >&2; exit 1; }
command -v "$PKG_CONFIG" >/dev/null 2>&1 || { echo "error: pkg-config not found" >&2; exit 1; }
command -v readelf >/dev/null 2>&1 || { echo "error: readelf is required for portable ELF validation" >&2; exit 1; }
"$PKG_CONFIG" --exists sdl2 || { echo "error: SDL2 development files not found" >&2; exit 1; }

BUILDDIR=build/release
MAINOBJ="$BUILDDIR/Main.o"
OBJECTS="$BUILDDIR/RNG.o $BUILDDIR/FrameBuffer.o $BUILDDIR/Input.o $BUILDDIR/Audio.o $BUILDDIR/Visuals.o $BUILDDIR/Game.o $BUILDDIR/Platform.o"

[ -f "$MAINOBJ" ] || {
  echo "error: release objects are missing; run make release first" >&2
  exit 1
}
for obj in $OBJECTS; do
  [ -f "$obj" ] || { echo "error: missing release object: $obj" >&2; exit 1; }
done

SDL_LIBDIR=$($PKG_CONFIG --variable=libdir sdl2 2>/dev/null || true)
SDL_LIBFILE=
for candidate in "$SDL_LIBDIR/libSDL2.so" "$SDL_LIBDIR"/libSDL2-2.0.so.*; do
  if [ -f "$candidate" ] || [ -L "$candidate" ]; then
    SDL_LIBFILE=$candidate
    break
  fi
done
[ -n "$SDL_LIBFILE" ] || { echo "error: could not locate concrete SDL2 shared library" >&2; exit 1; }

DISTROOT="$ROOT/dist"
DIST="$DISTROOT/ionlancer-linux-x86_64"
LIBDIR="$DIST/lib"
rm -rf "$DIST"
mkdir -p "$LIBDIR"

SDL_STAGE="$BUILDDIR/libSDL2-portable.so"
cp -L "$SDL_LIBFILE" "$SDL_STAGE"
test -s "$SDL_STAGE"

SAFE_FLAGS=
for flag in $($PKG_CONFIG --libs sdl2); do
  case "$flag" in
    -lSDL2|-L*|-Wl,-rpath*|-Wl,-R*|-Wl,--enable-new-dtags) ;;
    *) SAFE_FLAGS="$SAFE_FLAGS $flag" ;;
  esac
done

PORTABLE_INTERP=/lib64/ld-linux-x86-64.so.2
PORTABLE_RPATH='-Wl,-rpath,$ORIGIN/lib'
OUT="$DIST/ionlancer"

printf '%s\n' 'portable linux build'

"$GM2" -fpim4 -O3 "$MAINOBJ" $OBJECTS -o "$OUT" \
  "-Wl,--dynamic-linker=$PORTABLE_INTERP" \
  "$PORTABLE_RPATH" \
  -Wl,--allow-shlib-undefined \
  $SAFE_FLAGS "$SDL_STAGE"
chmod +x "$OUT"

if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-rpath '$ORIGIN/lib' "$OUT"
elif command -v chrpath >/dev/null 2>&1; then
  chrpath -r '$ORIGIN/lib' "$OUT" >/dev/null
elif command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/elf-set-runpath.py" "$OUT" '$ORIGIN/lib'
else
  echo "error: need patchelf, chrpath, or python3 to sanitize the portable ELF RUNPATH" >&2
  exit 1
fi

SDL_SONAME=
if command -v readelf >/dev/null 2>&1; then
  SDL_SONAME=$(readelf -d "$SDL_STAGE" 2>/dev/null | sed -n 's/.*SONAME.*\[\([^]]*\)\].*/\1/p' | head -n 1)
fi
[ -n "$SDL_SONAME" ] || SDL_SONAME=libSDL2-2.0.so.0
cp -L "$SDL_STAGE" "$LIBDIR/$SDL_SONAME"

if [ -x "$ROOT/$TARGET" ] && command -v ldd >/dev/null 2>&1; then
  LDD_OUT=$(ldd "$ROOT/$TARGET" 2>/dev/null || true)
  printf '%s\n' "$LDD_OUT" | while IFS= read -r line; do
    path=$(printf '%s\n' "$line" | sed -n 's/^[[:space:]]*[^ ]*[[:space:]]*=>[[:space:]]*\([^ ]*\).*/\1/p')
    [ -n "$path" ] || continue
    [ -f "$path" ] || continue
    name=$(basename "$path")
    case "$name" in
      libm2*.so*|libgcc_s.so*|libstdc++.so*|libquadmath.so*)
        cp -L "$path" "$LIBDIR/$name"
        ;;
    esac
  done
fi

cp -a assets "$DIST/assets"
cp README.md LICENSE "$DIST/"

cat > "$DIST/run.sh" <<'RUNEOF'
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"
export LD_LIBRARY_PATH="$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ -x /lib64/ld-linux-x86-64.so.2 ]; then
  exec "$HERE/ionlancer" "$@"
fi
if command -v readelf >/dev/null 2>&1; then
  host_sh=$(command -v sh 2>/dev/null || true)
  if [ -n "$host_sh" ]; then
    host_interp=$(readelf -l "$host_sh" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' | head -n 1)
    if [ -n "$host_interp" ] && [ -x "$host_interp" ]; then
      exec "$host_interp" --library-path "$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$HERE/ionlancer" "$@"
    fi
  fi
fi
echo "error: no usable x86-64 glibc ELF loader found" >&2
exit 126
RUNEOF
chmod +x "$DIST/run.sh"

if command -v readelf >/dev/null 2>&1; then
  INTERP=$(readelf -l "$OUT" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' | head -n 1)
  [ "$INTERP" = "$PORTABLE_INTERP" ] || {
    echo "error: portable ELF has unexpected interpreter: ${INTERP:-unknown}" >&2
    exit 1
  }

  DYN=$(readelf -d "$OUT" 2>/dev/null || true)
  if printf '%s\n' "$DYN" | grep -E '/gnu/store|/home/linuxbrew|\.linuxbrew' >/dev/null 2>&1; then
    echo "error: portable ELF still contains a machine-local runtime path" >&2
    printf '%s\n' "$DYN" | grep -E '/gnu/store|/home/linuxbrew|\.linuxbrew' >&2 || true
    exit 1
  fi
  FINAL_RUNPATH=$(printf '%s\n' "$DYN" | sed -n 's/.*Library .*: \[\([^]]*\)\].*/\1/p' | grep -F '$ORIGIN' | head -n 1)
  [ "$FINAL_RUNPATH" = '$ORIGIN/lib' ] || {
    echo "error: portable ELF runtime path is not exactly \\$ORIGIN/lib: ${FINAL_RUNPATH:-missing}" >&2
    exit 1
  }
fi

mkdir -p "$DISTROOT"
(
  cd "$DISTROOT"
  tar czf ionlancer-linux-x86_64.tar.gz ionlancer-linux-x86_64
)

printf '%s\n' "built $DISTROOT/ionlancer-linux-x86_64.tar.gz"
