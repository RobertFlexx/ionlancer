#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe_dir=build/quality-probe
mkdir -p "$probe_dir"
gm2=$(./scripts/tools.sh gm2)
pkg_config=$(./scripts/tools.sh pkg-config)
sdl_flags=$($pkg_config --cflags sdl2)
sdl_libs=$($pkg_config --libs sdl2)
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror $sdl_flags -c tests/Runtime.c -o "$probe_dir/Runtime.o"
for module in QualityProbe GameplayProbe NoThemeProbe; do
  "$gm2" -fpim4 -I src -I tests -Wall -fsoft-check-all $sdl_flags -c -fscaffold-main \
    "tests/$module.mod" -o "$probe_dir/$module.o"
  "$gm2" -fpim4 "$probe_dir/$module.o" "$probe_dir/Runtime.o" \
    build/debug/LanSocket.o build/debug/RNG.o build/debug/FrameBuffer.o \
    build/debug/Input.o build/debug/Audio.o build/debug/Settings.o build/debug/Visuals.o \
    build/debug/Arena.o build/debug/Game.o build/debug/Platform.o -o "$probe_dir/$module" $sdl_libs
  prefs_dir=$(mktemp -d "$PWD/$probe_dir/prefs.XXXXXX")
  if [ "$module" = NoThemeProbe ]; then
    (cd "$probe_dir" && ./NoThemeProbe)
  else
    ION_TEST_PREFS="$prefs_dir/" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
      "$probe_dir/$module"
  fi
done
echo 'Settings, keyboard/controller navigation, shuffle coverage, and audio buses passed'
python3 tests/probe_audio.py
python3 tests/probe_gameplay.py
