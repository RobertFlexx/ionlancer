#!/usr/bin/env bash
set -euo pipefail

# MSYS2 UCRT64 does not ship GNU Modula-2. Build its GCC frontend and runtime
# from a pinned upstream release, then cache the private installation in CI.
[[ ${MSYSTEM:-} == UCRT64 ]] || { echo 'error: use the MSYS2 UCRT64 shell' >&2; exit 1; }
for tool in gcc g++ make flex bison m4 patch sha512sum; do
  command -v "$tool" >/dev/null || { echo "error: missing $tool" >&2; exit 1; }
done

root=$(cd "$(dirname "$0")/.." && pwd)
prefix="$root/.gm2"
if [[ -x "$prefix/bin/gm2.exe" ]]; then
  "$prefix/bin/gm2.exe" --version
  exit 0
fi

version=15.2.0
sha512=89047a2e07bd9da265b507b516ed3635adb17491c7f4f67cf090f0bd5b3fc7f2ee6e4cc4008beef7ca884b6b71dffe2bb652b21f01a702e17b468cca2d10b2de
work="$root/build/windows-toolchain"
mkdir -p "$work"
cd "$work"

archive="gcc-$version.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://gcc.gnu.org/pub/gcc/releases/gcc-$version/$archive" -o "$archive"
fi
printf '%s  %s\n' "$sha512" "$archive" | sha512sum -c -
if [[ ! -d "gcc-$version" ]]; then tar -xf "$archive"; fi
if ! grep -q 'freopen (NameOfFile, "w", stdout)' "gcc-$version/gcc/m2/tools-src/mklink.c"; then
  patch --directory "gcc-$version" -p1 < "$root/scripts/patches/gcc-15-mklink-windows.patch"
fi
mkdir -p obj
cd obj

# GCC 16 is the current MSYS2 host compiler. Its C++20 char8_t default is
# incompatible with GCC 15's bundled libcody, whose u8 literals expect char.
export CXXFLAGS='-O2 -fno-char8_t'

"../gcc-$version/configure" \
  --prefix="$prefix" \
  --with-native-system-header-dir=/ucrt64/include \
  --with-gmp=/ucrt64 --with-mpfr=/ucrt64 --with-mpc=/ucrt64 \
  --with-isl=/ucrt64 \
  --enable-languages=c,m2 \
  --disable-bootstrap --disable-multilib --disable-nls \
  --disable-werror --disable-symvers \
  --enable-threads=posix
make -j "$(nproc)"
make install
"$prefix/bin/gm2.exe" --version
