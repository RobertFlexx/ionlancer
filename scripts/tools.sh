#!/bin/sh
# Toolchain discovery for IONLANCER.
#
# GNU Modula-2 and SDL2 end up in wildly different places depending on how you
# got them: distro packages, Homebrew, MacPorts, Nix, Guix, or a `./configure
# --prefix=$HOME/something` from source. Distributions also rename things when
# parallel versions are installed, which is why this exists at all: MacPorts
# ships `gm2-mp-15` and only creates a plain `gm2` symlink once you `select` it,
# so a perfectly good compiler is invisible to `command -v gm2`.
#
# Usable two ways:
#   . scripts/tools.sh && ion_resolve_toolchain   (library, POSIX)
#   ./scripts/tools.sh gm2|pkg-config|sdl2|check  (CLI, prints a path)
#
# Environment escape hatches, all optional:
#   GM2=<path>           use exactly this compiler
#   PKG_CONFIG=<path>    use exactly this pkg-config
#   ION_SDL2_PREFIXES    colon separated extra prefixes to search for SDL2

ION_TOOLS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------

ion_os() {
  case $(uname -s 2>/dev/null || echo unknown) in
    Darwin) echo macos ;;
    Linux)  echo linux ;;
    *)      echo other ;;
  esac
}

ion_arch() {
  case $(uname -m 2>/dev/null || echo unknown) in
    x86_64|amd64)          echo x86_64 ;;
    arm64|aarch64)         echo arm64 ;;
    *)                     uname -m 2>/dev/null || echo unknown ;;
  esac
}

# Echo a path only when it is an executable file.
ion_is_exec() {
  [ -n "${1:-}" ] && [ -x "$1" ] && [ ! -d "$1" ]
}

# Version numbers as a numerically sortable key, e.g. `gm2-mp-15` -> `015`.
# Uses plain `sort` with `-t. -k<n>,n` because BSD sort (macOS) has no -V.
ion_version_key() {
  printf '%s' "$1" | awk -F'[^0-9]+' '
    { out = ""; seen = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "") continue
        seen++
        v = $i + 0
        if (v < 100) v = sprintf("%03d", v); else v = sprintf("%d", v)
        out = (out == "") ? v : out "." v
      }
      if (out == "") out = "000"
      print out }
  '
}

# Pull a version out of a compiler filename, ignoring the target triple and
# MacPorts' `-mp-` marker.
#   gm2                                -> (none)
#   gm2-mp-15                          -> 15
#   aarch64-apple-darwin27-gm2-mp-15   -> 15
#   gm2-14.2.0                         -> 14.2.0
ion_name_version() {
  basename -- "$1" \
    | sed -e 's/^.*-gm2//' -e 's/^gm2//' -e 's/^-*mp-*//' \
    | sed -n 's/^-*\([0-9][0-9.]*\)$/\1/p'
}

# A candidate is only useful if it actually runs as gm2.
ion_looks_like_gm2() {
  ion_is_exec "$1" || return 1
  "$1" --version >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# prefixes
# ---------------------------------------------------------------------------

# Homebrew can live in several places, especially when Apple Silicon and
# Intel Homebrew are both installed. `brew --prefix` is authoritative when a
# brew binary exists, so ask it first and fall back to the well known paths.
ion_homebrew_prefixes() {
  if command -v brew >/dev/null 2>&1; then
    brew --prefix 2>/dev/null || true
  fi
  for p in /opt/homebrew /usr/local/Homebrew /home/linuxbrew/.linuxbrew; do
    [ -d "$p" ] && echo "$p"
  done
}

# pkgconfig directories worth probing even when they are not on the default
# search path. Unlinked kegs (a `brew install` that never ran `brew link`)
# are the common real-world failure here.
#
# These use find rather than shell globs on purpose: an unmatched glob is
# harmless in POSIX sh but a hard error in zsh, and this file gets sourced.
ion_pkgconfig_dirs() {
  for prefix in $(ion_homebrew_prefixes) /opt/local /usr/local; do
    for d in lib/pkgconfig lib64/pkgconfig share/pkgconfig; do
      [ -d "$prefix/$d" ] && echo "$prefix/$d"
    done
  done

  # Homebrew versioned kegs and per-formula `opt` symlinks.
  for prefix in $(ion_homebrew_prefixes); do
    for tree in Cellar opt; do
      [ -d "$prefix/$tree" ] || continue
      find "$prefix/$tree" -maxdepth 3 -type d -name pkgconfig 2>/dev/null
    done
  done

  # Debian/Fedora multiarch plus the plain system directories.
  for tree in /usr/lib /usr/lib64 /usr/share; do
    [ -d "$tree" ] || continue
    find "$tree" -maxdepth 2 -type d -name pkgconfig 2>/dev/null
  done
}

# Directories that may contain a gm2 driver.
ion_gm2_dirs() {
  for prefix in $(ion_homebrew_prefixes) /opt/local /usr/local /opt/homebrew; do
    for d in bin gm2/bin libexec/bin; do
      [ -d "$prefix/$d" ] && echo "$prefix/$d"
    done
  done

  # gcc libexec trees, where several distros park the driver.
  for tree in /usr/lib/gcc /usr/libexec/gcc; do
    [ -d "$tree" ] || continue
    find "$tree" -maxdepth 3 -type d 2>/dev/null
  done
  for prefix in $(ion_homebrew_prefixes) /opt/local /usr/local; do
    [ -d "$prefix/lib/gcc" ] || continue
    find "$prefix/lib/gcc" -maxdepth 3 -type d 2>/dev/null
  done

  # Nix and Guix keep everything in versioned store paths.
  for store in /nix/store /gnu/store; do
    [ -d "$store" ] || continue
    find "$store" -maxdepth 3 -type d -name bin -path '*gcc*' 2>/dev/null
  done
}

# Executable gm2-ish files in a directory, as one path per line. Symlinks are
# included because `port select` and `brew link` both create them.
ion_gm2_candidates_in() {
  [ -n "${1:-}" ] && [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 \( -type f -o -type l \) -perm -u+x -name '*gm2*' 2>/dev/null
}

# ---------------------------------------------------------------------------
# resolvers
# ---------------------------------------------------------------------------

# Echo the best gm2 driver path, or nothing.
# Returns 0 on success, 2 if an explicit $GM2 was rejected, 1 if none found.
#
# Order of preference:
#   1. $GM2 verbatim (explicit user intent, validated but never second-guessed)
#   2. a plain `gm2` reachable from PATH
#   3. anything else that validates, newest version first
ion_resolve_gm2() {
  if [ -n "${GM2:-}" ] && [ "$GM2" != gm2 ]; then
    if ion_looks_like_gm2 "$GM2"; then
      echo "$GM2"
      return 0
    fi
    echo "ionlancer: GM2 is set to '$GM2' but that is not a working gm2" >&2
    return 2
  fi

  command -v gm2 >/dev/null 2>&1 && ion_looks_like_gm2 "$(command -v gm2)" && {
    command -v gm2
    return 0
  }

  # Broad sweep. Collect first, validate later, so one bad candidate is cheap.
  found=''
  for dir in $(ion_gm2_dirs); do
    for candidate in $(ion_gm2_candidates_in "$dir"); do
      case "$candidate" in
        *.dylib|*.so|*.a|*.d) continue ;;
      esac
      found="$found
$candidate"
    done
  done

  [ -n "$found" ] || return 1

  # Version-sorted, newest first. A path with no embedded version sorts as
  # oldest, which is the right tie-breaker: prefer an explicit version match.
  # Version keys are dot separated decimals, so `sort -t. -k<n>,n` sorts them
  # numerically on both GNU and BSD sort.
  echo "$found" | sort -u | while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    printf '%s %s\n' "$(ion_version_key "$(ion_name_version "$candidate")")" "$candidate"
  done | sort -r -t. -k1,1 -k2,2 -k3,3 | while IFS= read -r line; do
    candidate=${line#* }
    if ion_looks_like_gm2 "$candidate"; then
      echo "$candidate"
      break
    fi
  done
}

# Echo a working pkg-config (or pkgconf) path.
ion_resolve_pkg_config() {
  if [ -n "${PKG_CONFIG:-}" ] && [ "$PKG_CONFIG" != pkg-config ]; then
    if ion_is_exec "$PKG_CONFIG"; then
      echo "$PKG_CONFIG"
      return 0
    fi
    echo "ionlancer: PKG_CONFIG is set to '$PKG_CONFIG' which is not executable" >&2
    return 1
  fi

  for name in pkg-config pkgconf; do
    found=$(command -v "$name" 2>/dev/null) || continue
    if [ -n "$found" ]; then
      echo "$found"
      return 0
    fi
  done
  return 1
}

# Add one candidate directory to the SDL2 search path list, but only if it
# really exists, really carries an SDL2 .pc file, and is not listed already.
ion_add_sdl2_dir() {
  [ -n "$1" ] || return 0
  [ -d "$1" ] || return 0
  [ -f "$1/sdl2.pc" ] || return 0
  case ":$ion_sdl2_additions:" in
    *":$1:"*) return 0 ;;
  esac
  ion_sdl2_additions="$ion_sdl2_additions${ion_sdl2_additions:+:}$1"
  return 0
}

# Echo the PKG_CONFIG_PATH additions needed for `pkg-config sdl2` to work.
# Prints nothing when the default search path already finds SDL2, so the
# common case stays a no-op.
ion_resolve_sdl2_search_path() {
  pkg_config=$1
  [ -n "$pkg_config" ] || return 0

  "$pkg_config" --exists sdl2 2>/dev/null && return 0

  ion_sdl2_additions=''

  # $ION_SDL2_PREFIXES is colon separated, like PKG_CONFIG_PATH itself, so it
  # has to be split on colons. Handing the whole string to pkg-config as one
  # path would quietly find nothing.
  ion_saved_ifs=$IFS
  IFS=':'
  for dir in ${ION_SDL2_PREFIXES:-}; do
    ion_add_sdl2_dir "$dir"
  done
  IFS=$ion_saved_ifs

  for dir in $(ion_pkgconfig_dirs); do
    ion_add_sdl2_dir "$dir"
  done

  additions=$ion_sdl2_additions

  [ -n "$additions" ] || return 0

  # Confirm the additions actually resolve before handing them back, so we
  # never pollute PKG_CONFIG_PATH with a guess.
  # ${VAR:-} rather than $VAR: this file is sourced by scripts running under
  # `set -u`, and PKG_CONFIG_PATH is usually not set at all on a fresh shell.
  saved=${PKG_CONFIG_PATH:-}
  PKG_CONFIG_PATH="$additions${saved:+:$saved}"
  export PKG_CONFIG_PATH
  if "$pkg_config" --exists sdl2 2>/dev/null; then
    echo "$additions"
  fi
  if [ -n "$saved" ]; then
    PKG_CONFIG_PATH=$saved
    export PKG_CONFIG_PATH
  else
    unset PKG_CONFIG_PATH
  fi
  return 0
}

# Full toolchain resolution. Sets ION_GM2 / ION_PKG_CONFIG / ION_SDL2_PATH
# and exports PKG_CONFIG_PATH. Returns non-zero with a human readable reason
# if something is genuinely missing.
ion_resolve_toolchain() {
  ION_GM2=$(ion_resolve_gm2)
  case $? in
    0) ;;
    2) return 1 ;;
    *)
      echo "ionlancer: no working GNU Modula-2 compiler (gm2) found." >&2
      cat >&2 <<'EOF'

  Searched $PATH, Homebrew, MacPorts, /usr/local, /opt, Nix and Guix stores.

  Install it with one of:
    brew install gm2                  # if your Homebrew has a gm2 formula
    port install gm2 && port select --set gm2
    ./configure && make && sudo make install   # from gm2 source

  Or point IONLANCER at one explicitly:
    make GM2=/full/path/to/gm2
EOF
      return 1
      ;;
  esac

  ION_PKG_CONFIG=$(ion_resolve_pkg_config) || {
    echo "ionlancer: pkg-config not found." >&2
    cat >&2 <<'EOF'

  Install it with one of:
    brew install pkg-config
    port install pkgconf
    (Debian/Ubuntu) sudo apt install pkg-config
EOF
    return 1
  }

  ION_SDL2_PATH=$(ion_resolve_sdl2_search_path "$ION_PKG_CONFIG")
  if [ -n "$ION_SDL2_PATH" ]; then
    PKG_CONFIG_PATH="$ION_SDL2_PATH${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PKG_CONFIG_PATH
  fi

  "$ION_PKG_CONFIG" --exists sdl2 2>/dev/null || {
    echo "ionlancer: SDL2 development files not found (pkg-config sdl2)." >&2
    cat >&2 <<'EOF'

  Install it with one of:
    brew install sdl2
    port install sdl2
    (Debian/Ubuntu) sudo apt install libsdl2-dev
    (Fedora) sudo dnf install SDL2-devel

  If SDL2 lives somewhere unusual, add its pkgconfig directory:
    ION_SDL2_PREFIXES=/some/prefix/lib/pkgconfig make release
EOF
    return 1
  }

  export ION_GM2 ION_PKG_CONFIG ION_SDL2_PATH
  return 0
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

ion_tools_usage() {
  cat <<'EOF'
usage: scripts/tools.sh <command>

  gm2         print the resolved GNU Modula-2 compiler path
  pkg-config  print the resolved pkg-config path
  sdl2        print the resolved SDL2 version
  check       print the full resolved toolchain
  deps        resolve everything, print nothing, non-zero if anything is missing
  probe       like deps, and also verify gm2 can compile and link a program
EOF
}

# Prove the compiler actually works, not just that it answers --version.
# A gm2 install missing its Modula-2 runtime is a real and confusing failure.
ion_tools_probe() {
  ion_resolve_toolchain || return 1

  probe_dir=${TMPDIR:-/tmp}/ionlancer-probe.$$
  rm -rf "$probe_dir"
  mkdir -p "$probe_dir" || return 1
  trap 'rm -rf "$probe_dir"' EXIT INT TERM

  cat > "$probe_dir/probe.mod" <<'PROBEEOF'
MODULE Probe;
VAR i : INTEGER;
BEGIN i := 20; i := i + 22; IF i = 42 THEN END END Probe.
PROBEEOF

  if ! "$ION_GM2" -c "$probe_dir/probe.mod" -o "$probe_dir/probe.o" >"$probe_dir/log" 2>&1; then
    echo "ionlancer: $ION_GM2 is present but cannot compile Modula-2." >&2
    sed 's/^/  /' "$probe_dir/log" >&2
    echo "  the GNU Modula-2 runtime (libgm2) is probably missing;" >&2
    echo "  reinstall the compiler from the source tree you built it from." >&2
    return 1
  fi

  if ! "$ION_GM2" -fscaffold-main "$probe_dir/probe.mod" -o "$probe_dir/probe" >>"$probe_dir/log" 2>&1; then
    echo "ionlancer: $ION_GM2 compiles but cannot link an executable." >&2
    sed 's/^/  /' "$probe_dir/log" >&2
    return 1
  fi

  return 0
}

ion_tools_main() {
  case "${1:-}" in
    gm2)
      gm2_path=$(ion_resolve_gm2) || return 1
      printf '%s\n' "$gm2_path"
      ;;
    pkg-config|pkgconfig)
      ion_resolve_pkg_config || return 1
      ;;
    sdl2)
      pkg_config=$(ion_resolve_pkg_config) || return 1
      ION_SDL2_PATH=$(ion_resolve_sdl2_search_path "$pkg_config")
      [ -n "$ION_SDL2_PATH" ] && export PKG_CONFIG_PATH="$ION_SDL2_PATH${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
      "$pkg_config" --modversion sdl2 2>/dev/null || return 1
      ;;
    check)
      ion_resolve_toolchain || return 1
      printf 'os           %s (%s)\n' "$(ion_os)" "$(ion_arch)"
      printf 'gm2          %s\n' "$ION_GM2"
      printf 'gm2 version  %s\n' "$("$ION_GM2" --version 2>/dev/null | head -n 1)"
      printf 'pkg-config   %s\n' "$ION_PKG_CONFIG"
      printf 'SDL2         %s\n' "$("$ION_PKG_CONFIG" --modversion sdl2 2>/dev/null || echo missing)"
      printf 'SDL2 cflags  %s\n' "$("$ION_PKG_CONFIG" --cflags sdl2 2>/dev/null || echo missing)"
      printf 'SDL2 libs    %s\n' "$("$ION_PKG_CONFIG" --libs sdl2 2>/dev/null || echo missing)"
      if [ -n "$ION_SDL2_PATH" ]; then
        printf 'SDL2 path    %s (added to PKG_CONFIG_PATH)\n' "$ION_SDL2_PATH"
      fi
      ;;
    -h|--help|help|'')
      ion_tools_usage
      ;;
    deps)
      ion_resolve_toolchain || return 1
      ;;
    probe)
      ion_tools_probe
      ;;
    *)
      echo "unknown command: $1" >&2
      ion_tools_usage >&2
      return 2
      ;;
  esac
}

if [ "${ION_TOOLS_SOURCED:-}" != 1 ]; then
  ion_tools_main "$@"
  exit $?
fi
