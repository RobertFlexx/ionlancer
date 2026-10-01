#!/usr/bin/env bash
set -euo pipefail

[[ ${MSYSTEM:-} == UCRT64 ]] || { echo 'error: use the MSYS2 UCRT64 shell' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

gm2="$root/.gm2/bin/gm2.exe"
[[ -x "$gm2" ]] || { echo 'error: run build-gm2-windows.sh first' >&2; exit 1; }
pkg-config --exists sdl2

build="$root/build/windows"
dist="$root/dist/ionlancer-windows-x86_64"
mkdir -p "$build" "$dist"

read -r -a cflags <<< "$(pkg-config --cflags sdl2)"
read -r -a libs <<< "$(pkg-config --libs sdl2)"
modules=(RNG FrameBuffer Input Audio Settings Visuals Arena Game Platform)
objects=()
gcc -O3 -c src/LanSocket.c -o "$build/LanSocket.o"
objects+=("$build/LanSocket.o")
for module in "${modules[@]}"; do
  obj="$build/$module.o"
  "$gm2" -fpim4 -I src -Wall -O3 "${cflags[@]}" -c "src/$module.mod" -o "$obj"
  objects+=("$obj")
done
"$gm2" -fpim4 -I src -Wall -O3 "${cflags[@]}" -fscaffold-main \
  -c src/Main.mod -o "$build/Main.o"
"$gm2" -fpim4 -O3 "$build/Main.o" "${objects[@]}" \
  -o "$dist/ionlancer.exe" "${libs[@]}" -lws2_32

cp -a assets "$dist/"
cp README.md LICENSE "$dist/"

# Walk PE imports so SDL2 and the compiler runtime travel with the game.
# Windows system DLLs are resolved by the OS and are not copied.
queue=("$dist/ionlancer.exe")
for ((i=0; i<${#queue[@]}; i++)); do
  image=${queue[$i]}
  while IFS= read -r dll; do
    [[ -n "$dll" ]] || continue
    [[ -f "$dist/$dll" ]] && continue
    source=
    for dir in "$MINGW_PREFIX/bin" "$root/.gm2/bin" "$root/.gm2/lib"; do
      if [[ -f "$dir/$dll" ]]; then source="$dir/$dll"; break; fi
    done
    [[ -n "$source" ]] || continue
    cp "$source" "$dist/$dll"
    queue+=("$dist/$dll")
  done < <(objdump -p "$image" | sed -n 's/^[[:space:]]*DLL Name: //p')
done

[[ -s "$dist/SDL2.dll" ]] || { echo 'error: SDL2.dll was not bundled' >&2; exit 1; }
printf 'built %s\n' "$dist"
