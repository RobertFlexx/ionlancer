#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
probe_dir=build/lan-probe
mkdir -p "$probe_dir"

gm2=$(./scripts/tools.sh gm2)
pkg_config=$(./scripts/tools.sh pkg-config)
sdl_flags=$($pkg_config --cflags sdl2)
sdl_libs=$($pkg_config --libs sdl2)

"${CC:-cc}" -O2 -c tests/ProbeEnv.c -o "$probe_dir/ProbeEnv.o"
for module in LanProbe LanWire LanReceive; do
  "$gm2" -fpim4 -I src -I tests -Wall $sdl_flags -c -fscaffold-main \
    "tests/$module.mod" -o "$probe_dir/$module.o"
  "$gm2" -fpim4 "$probe_dir/$module.o" "$probe_dir/ProbeEnv.o" \
    build/release/LanSocket.o build/release/RNG.o build/release/FrameBuffer.o \
    build/release/Input.o build/release/Audio.o build/release/Visuals.o \
    build/release/Arena.o -o "$probe_dir/$module" $sdl_libs
done

"${CC:-cc}" -shared -fPIC -Wall -Wextra -Werror src/LanSocket.c -o "$probe_dir/liblan.so"
python3 tests/probe_socket.py "$probe_dir/liblan.so"

"$probe_dir/LanProbe" &
host_pid=$!
ION_PROBE_GUEST=1 "$probe_dir/LanProbe" &
guest_pid=$!

host_status=0
guest_status=0
wait "$host_pid" || host_status=$?
wait "$guest_pid" || guest_status=$?
if [ "$host_status" -ne 0 ] || [ "$guest_status" -ne 0 ]; then
  echo "LAN probe failed: host=$host_status guest=$guest_status" >&2
  exit 1
fi
echo "LAN probe passed: co-op, versus reset, and mode mismatch"

"$probe_dir/LanWire" &
wire_pid=$!
wire_status=0
python3 tests/probe_wire.py || wire_status=$?
wait "$wire_pid" || wire_status=$?
if [ "$wire_status" -ne 0 ]; then
  echo "LAN sound probe failed: status=$wire_status" >&2
  exit 1
fi

python3 tests/probe_snapshot.py "$probe_dir/LanReceive"
