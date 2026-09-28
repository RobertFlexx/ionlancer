#!/bin/sh
set -eu

# Package a macOS .app bundle that carries its own SDL2 and Modula-2 runtime,
# so it can be handed to somebody who has neither Homebrew nor MacPorts.
#
# Like the Linux portable target this reuses an existing `make release` binary
# rather than relinking, because the job here is packaging, not compiling.
# The one thing it cannot avoid is the working directory: the game loads its
# assets through relative paths, so a launcher script fixes that up instead of
# making the game aware of bundles.

TARGET=${1:-ionlancer}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

command -v install_name_tool >/dev/null 2>&1 || {
  echo "error: install_name_tool not found (Xcode command line tools are required)" >&2
  exit 1
}
command -v otool >/dev/null 2>&1 || {
  echo "error: otool not found (Xcode command line tools are required)" >&2
  exit 1
}

[ "$(uname -s 2>/dev/null || echo unknown)" = Darwin ] || {
  echo "error: portable-macos build is macOS-only" >&2
  exit 1
}

ARCH=$(uname -m 2>/dev/null || echo unknown)
case "$ARCH" in
  x86_64) ARCH=x86_64 ;;
  arm64)  ARCH=arm64 ;;
  *)
    echo "error: portable-macos currently targets x86_64 and arm64; host architecture is $ARCH" >&2
    exit 1
    ;;
esac

[ -f "$TARGET" ] && [ -x "$TARGET" ] || {
  echo "error: $TARGET is not built; run 'make release' first" >&2
  exit 1
}
[ -d assets ] || { echo "error: assets/ is missing" >&2; exit 1; }

APP="$ROOT/dist/ionlancer-macos-$ARCH.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" \
         "$APP/Contents/Resources/Frameworks" "$APP/Contents/Resources/assets"

printf '%s\n' 'portable macos build'

# ---------------------------------------------------------------------------
# embed the shared library closure
# ---------------------------------------------------------------------------

# The real binary deliberately does not live in Contents/MacOS. That directory
# is reserved for the single designated bundle executable, because codesign
# only signs code it recognises there and anything extra comes out unsigned.
BINARY="$APP/Contents/Resources/bin/ionlancer"
cp "$TARGET" "$BINARY"
chmod u+w "$BINARY"
chmod +x "$BINARY"

FRAMEWORKS="$APP/Contents/Resources/Frameworks"

# Where the game binary lives before packaging, for resolving @executable_path
# while walking a library that has not been bundled yet.
EXE_SOURCE_DIR=$(dirname -- "$TARGET")

# Absolute dylib references we are willing to embed. Anything under /usr/lib or
# /System ships with the OS and must be left alone. A reference whose basename
# matches the image itself is that image's LC_ID_DYLIB, not a real dependency.
embeddable_deps() {
  self=$(basename -- "$1")
  otool -L "$1" 2>/dev/null | tail -n +2 | awk '{ print $1 }' | while IFS= read -r dep; do
    case "$dep" in
      ''|/System/*|/usr/lib/*|@*) continue ;;
    esac
    [ -f "$dep" ] || continue
    [ "$(basename -- "$dep")" = "$self" ] && continue
    echo "$dep"
  done
}

# Names of libraries an image expects to dlopen at runtime. These are invisible
# to otool, and sdl2-compat is a real example: it is a shim that pulls SDL3 in
# on first use, so a bundle carrying only the LC_LOAD_DYLIB closure aborts
# inside SDL's own initializer.
dlopen_siblings() {
  strings -a "$1" 2>/dev/null | grep -o 'lib[A-Za-z0-9._+-]*\.dylib' 2>/dev/null | sort -u
}

# The raw LC_RPATH entries of a Mach-O image.
image_rpaths() {
  otool -l "$1" 2>/dev/null | awk '
    $0 ~ /cmd LC_RPATH/ { getline; getline; if ($1 == "path") print $2 }
  '
}

# Locate a dlopen'd sibling. It is normally a file sitting next to the library
# that wants it, but Homebrew splits related kegs apart: sdl2-compat finds SDL3
# through an @loader_path rpath that walks out of its own keg and back down
# into the sdl3 keg, so the rpath has to be followed too. Returns non-zero when
# the name is not resolvable, which is how optional probes such as SDL3's
# OpenGL and Vulkan lookups stay optional.
find_sibling() {
  img=$1
  src_dir=$2
  name=$3

  if [ -f "$src_dir/$name" ]; then
    printf '%s\n' "$src_dir/$name"
    return 0
  fi

  for rp in $(image_rpaths "$img"); do
    case "$rp" in
      @loader_path/*)    cand="$src_dir/${rp#@loader_path/}" ;;
      @executable_path/*) cand="$EXE_SOURCE_DIR/${rp#@executable_path/}" ;;
      @rpath/*)          cand="$src_dir/${rp#@rpath/}" ;;
      /*)                cand="$rp" ;;
      *)                 cand="$src_dir/$rp" ;;
    esac
    if [ -f "$cand/$name" ]; then
      printf '%s\n' "$cand/$name"
      return 0
    fi
  done
  return 1
}

# Canonical path, used to avoid bundling the same library twice under two names
# (a versioned dylib and its unversioned symlink are one file).
canonical() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1" 2>/dev/null || printf '%s\n' "$1"
  else
    dir=$(dirname -- "$1")
    base=$(basename -- "$1")
    canonical_dir=$(CDPATH= cd -- "$dir" 2>/dev/null && pwd -P)
    if [ -n "$canonical_dir" ]; then
      printf '%s/%s\n' "$canonical_dir" "$base"
    else
      printf '%s\n' "$1"
    fi
  fi
}

# Copy a library into Frameworks/ and set BUNDLED_NAME to the name it got.
# BUNDLED_NEW is 1 only when this call actually copied something, which is what
# keeps the walk from re-queueing a library it has already handled.
#
# With no second argument the name is the source basename and an already
# bundled library is reused, which keeps a versioned dylib and its unversioned
# symlink from being copied twice. Passing an explicit name pins it, because
# for a dlopen'd library the name is part of the contract: SDL2 asks for
# libSDL3.dylib specifically, so bundling it as libSDL3.0.dylib would not help.
#
# This deliberately sets variables instead of echoing: the bookkeeping has to
# survive, and a command substitution would run it in a subshell.
BUNDLED_NAME=
BUNDLED_NEW=0
bundle_one() {
  src=$1
  want=${2:-}
  canon=$(canonical "$src")
  BUNDLED_NEW=0

  if [ -z "$want" ]; then
    for seen_entry in $SEEN; do
      if [ "${seen_entry#*=}" = "$canon" ]; then
        BUNDLED_NAME=${seen_entry%%=*}
        return 0
      fi
    done
    want=$(basename -- "$src")
  fi

  BUNDLED_NAME=$want
  if [ ! -f "$FRAMEWORKS/$want" ]; then
    cp -L "$src" "$FRAMEWORKS/$want"
    chmod u+w "$FRAMEWORKS/$want" 2>/dev/null || true
    BUNDLED_NEW=1
  fi
  SEEN="$SEEN $want=$canon"
}

# Breadth-first walk over both link-time and dlopen'd dependencies. bin/ sits
# next to Frameworks/, so @loader_path covers every reference in the bundle and
# no LC_RPATH entry is needed, which keeps this working on a stock macOS
# install.
#
# The work list lives in a file rather than a variable: a pipe or command
# substitution would run the loop in a subshell and throw away everything it
# discovered. A queue line is "<bundled_path>|<canonical_source>", and '|'
# cannot occur in a path.
QUEUE_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t ionlancer)
trap 'rm -rf "$QUEUE_DIR"' EXIT INT TERM
QUEUE="$QUEUE_DIR/queue"
NEXT="$QUEUE_DIR/next"

printf '%s|%s\n' "$BINARY" "$(canonical "$TARGET")" > "$QUEUE"
SEEN=
depth=0
while [ -s "$QUEUE" ] && [ "$depth" -lt 16 ]; do
  : > "$NEXT"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    image=${entry%%|*}
    src_dir=$(dirname -- "${entry#*|}")

    # Only ever rewrite files that live inside the bundle. Everything else is a
    # shared library somebody else installed, and silently repointing a
    # Homebrew or MacPorts install would be a genuinely nasty surprise.
    case "$image" in
      "$APP"/*) ;;
      *)
        echo "error: refusing to modify $image, which is outside the bundle" >&2
        exit 1
        ;;
    esac

    if [ "$image" = "$BINARY" ]; then
      rebase='@loader_path/../Frameworks'
    else
      rebase='@loader_path'
    fi

    for dep in $(embeddable_deps "$image"); do
      bundle_one "$dep"
      if [ "$BUNDLED_NEW" = 1 ]; then
        printf '%s|%s\n' "$FRAMEWORKS/$BUNDLED_NAME" "$(canonical "$dep")" >> "$NEXT"
      fi
      install_name_tool -change "$dep" "$rebase/$BUNDLED_NAME" "$image" 2>/dev/null || {
        echo "error: could not rebase $dep in $image" >&2
        exit 1
      }
    done

    for name in $(dlopen_siblings "$image"); do
      src=$(find_sibling "$image" "$src_dir" "$name") || continue
      bundle_one "$src" "$name"
      if [ "$BUNDLED_NEW" = 1 ]; then
        printf '%s|%s\n' "$FRAMEWORKS/$BUNDLED_NAME" "$(canonical "$src")" >> "$NEXT"
      fi
    done
  done < "$QUEUE"
  mv "$NEXT" "$QUEUE"
  depth=$((depth + 1))
done

if [ -s "$QUEUE" ]; then
  echo "error: shared library closure is deeper than 16 levels, refusing to guess" >&2
  exit 1
fi

# Make each embedded library identify itself by location rather than by the
# path it happened to be built at, and drop its runpath. Every reference in the
# bundle now resolves through @loader_path, and leaving an rpath behind would
# let a copied library quietly load a different copy from the build machine.
for lib in "$FRAMEWORKS"/*.dylib; do
  [ -f "$lib" ] || continue
  base=$(basename -- "$lib")
  install_name_tool -id "@loader_path/$base" "$lib" 2>/dev/null || {
    echo "error: could not set the install name of $base" >&2
    exit 1
  }
  for rp in $(image_rpaths "$lib"); do
    install_name_tool -delete_rpath "$rp" "$lib" 2>/dev/null || true
  done
done

# The game binary picks up a runpath from whatever toolchain built it, which on
# a MacPorts host points at /opt/local/lib/gcc. Nothing in the bundle needs it.
for rp in $(image_rpaths "$BINARY"); do
  install_name_tool -delete_rpath "$rp" "$BINARY" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# bundle layout
# ---------------------------------------------------------------------------

cp -a assets/. "$APP/Contents/Resources/assets/"
cp README.md LICENSE "$APP/Contents/Resources/"

# The game reads these by relative path at startup, so an empty or missing
# assets directory is a silently broken bundle rather than a build error.
for required in assets/ionlancer_theme.s16 assets/ionlancer_theme.vis; do
  [ -s "$APP/Contents/Resources/$required" ] || {
    echo "error: $required did not make it into the bundle" >&2
    exit 1
  }
done

VERSION=$(cat VERSION 2>/dev/null || echo 0)
cat > "$APP/Contents/Info.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>IONLANCER</string>
  <key>CFBundleDisplayName</key>
  <string>IONLANCER</string>
  <key>CFBundleIdentifier</key>
  <string>dev.ionlancer.IONLANCER</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleExecutable</key>
  <string>IONLANCER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
</dict>
</plist>
PLISTEOF

# Bundle executable. Launching from Finder gives a working directory of "/",
# and the game reads assets/... relatively, so anchor it to Contents/Resources.
# This is why the launcher exists at all: it keeps that relative-asset
# assumption out of the game itself.
cat > "$APP/Contents/MacOS/IONLANCER" <<'LAUNCHEOF'
#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RESOURCES="$HERE/../Resources"
cd "$RESOURCES"
exec "$RESOURCES/bin/ionlancer" "$@"
LAUNCHEOF
chmod +x "$APP/Contents/MacOS/IONLANCER"

cat > "$APP/Contents/Resources/run.sh" <<'RUNEOF'
#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"
exec "$HERE/bin/ionlancer" "$@"
RUNEOF
chmod +x "$APP/Contents/Resources/run.sh"

# ---------------------------------------------------------------------------
# signing
# ---------------------------------------------------------------------------
# install_name_tool invalidates any existing signature, and arm64 refuses to
# execute unsigned code, so this step is not optional.

sign_ok=1
if command -v codesign >/dev/null 2>&1; then
  # Embedded libraries first, then the game binary, then the bundle itself.
  # The bundle seal has to be written last or it invalidates the inner ones.
  for lib in "$FRAMEWORKS"/*.dylib; do
    [ -f "$lib" ] || continue
    codesign --force --sign - "$lib" >/dev/null 2>&1 || sign_ok=0
  done
  codesign --force --sign - "$BINARY" >/dev/null 2>&1 || sign_ok=0
  codesign --force --sign - "$APP" >/dev/null 2>&1 || sign_ok=0
  if [ "$sign_ok" -eq 1 ]; then
    codesign --verify --strict "$APP" >/dev/null 2>&1 || {
      echo "error: the finished bundle failed codesign verification" >&2
      exit 1
    }
  else
    echo "warning: ad-hoc signing failed; the bundle may not launch on arm64" >&2
  fi
else
  echo "error: codesign not found (Xcode command line tools are required)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------
# A bundle that still points at /opt or /usr/local is not portable, it just
# happens to work on the machine that built it. Runpaths count too: a leftover
# one silently loads a different copy of a library on somebody else's Mac.

STRAY=$(otool -L "$BINARY" "$FRAMEWORKS"/*.dylib 2>/dev/null \
  | sed -n 's/^[[:space:]]*\(.*\.dylib\) (compatibility.*/\1/p' \
  | grep -E '^/opt/|^/usr/local/|/home/linuxbrew|\.linuxbrew|^/nix/|^/gnu/store' || true)
if [ -n "$STRAY" ]; then
  echo "error: bundle still references machine-local shared libraries:" >&2
  printf '%s\n' "$STRAY" | sed 's/^/  /' >&2
  exit 1
fi

for image in "$BINARY" "$FRAMEWORKS"/*.dylib; do
  [ -f "$image" ] || continue
  stray_rp=$(image_rpaths "$image" | grep -E '^/|/home/linuxbrew|\.linuxbrew' || true)
  if [ -n "$stray_rp" ]; then
    echo "error: $(basename -- "$image") still has a machine-local runpath:" >&2
    printf '%s\n' "$stray_rp" | sed 's/^/  /' >&2
    exit 1
  fi
done

# Prove the bundle is self-contained before shipping it. The dummy video and
# audio drivers keep this headless, and a couple of seconds is enough to reach
# the main loop or crash trying.
#
# `exec` matters: without it $! is a subshell waiting on the game rather than
# the game itself, the kill lands on the subshell, and the following wait blocks
# forever on a process that is still happily running.
(
  cd "$APP/Contents/Resources" || exit 1
  SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy exec "$BINARY"
) >"$QUEUE_DIR/smoke.log" 2>&1 &
BUNDLE_PID=$!

sleep 2
if kill -0 "$BUNDLE_PID" 2>/dev/null; then
  kill -TERM "$BUNDLE_PID" 2>/dev/null || true
  # The game is a game loop with no idle exit, so insist that it goes away.
  n=0
  while kill -0 "$BUNDLE_PID" 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -KILL "$BUNDLE_PID" 2>/dev/null || true
  wait "$BUNDLE_PID" 2>/dev/null || true
else
  wait "$BUNDLE_PID" 2>/dev/null || true
  echo "error: the bundled game exited immediately instead of running" >&2
  cat "$QUEUE_DIR/smoke.log" >&2
  exit 1
fi

mkdir -p "$ROOT/dist"
(
  cd "$ROOT/dist"
  rm -f "ionlancer-macos-$ARCH.tar.gz"
  tar czf "ionlancer-macos-$ARCH.tar.gz" "ionlancer-macos-$ARCH.app"
)

printf '%s\n' "built $ROOT/dist/ionlancer-macos-$ARCH.tar.gz"
