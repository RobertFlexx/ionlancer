# IONLANCER

IONLANCER is a small arcade shooter written in GNU Modula-2 with SDL2. It runs on a 320x180 framebuffer, has a few game modes, several bosses, controller support, and a soundtrack called **Endless Endeavor** (as seen on my [youtube!](https://www.youtube.com/watch?v=IQyR7Mr_JS0))

I mostly made it because writing this kind of game in Modula-2 sounded fun.
I made it, debugged it, then uploaded it as one.
Enjoy, feel free to nitpick.

## build

You need GNU Modula-2, SDL2, `pkg-config`, and make.

```sh
./BUILD-FIRST.sh
```

Or just: 

```sh
make release
```

### finding the toolchain

You do not have to point the build at anything. `make` searches `$PATH`,
Homebrew, MacPorts, `/usr/local`, `/opt`, and the Nix and Guix stores, and
validates every candidate by actually running it. That matters more than it
sounds: package managers rename things when parallel versions are installed, so
a working compiler is often invisible to `command -v gm2`. MacPorts, for
instance, ships `gm2-mp-15` and only creates a plain `gm2` symlink once you
`port select` it. The same goes for SDL2, where a Homebrew keg that was never
`brew link`ed is still perfectly usable.

To see what it picked:

```sh
make check
```

That prints the resolved compiler, pkg-config and SDL2, then compiles and links
a throwaway Modula-2 program to prove the installation is not just present but
working.

To override the search:

```sh
make GM2=/full/path/to/gm2 release
ION_SDL2_PREFIXES=/some/prefix/lib/pkgconfig make release
```

## run

```sh
./run.sh --auto
./run.sh --x11
./run.sh --wayland
```

On macOS the native driver is `cocoa`, which is what `--auto` picks:

```sh
./run.sh --cocoa
```

Controls are shown in-game. The basics are WASD/arrows to move, Z/Space to shoot, X/Shift for pulse, P to pause, M for the menu, and F11 for fullscreen.

## macOS

Builds native (Apple Silicon or Intel) against whatever SDL2 `pkg-config` finds,
and runs straight from the repository. There is nothing macOS-specific in the
game itself, so the source is identical to the Linux build.

X11 and Wayland are Linux backends. `--wayland` is refused on macOS, and
`--x11` asks you to install XQuartz first rather than letting SDL fail with
something cryptic. Everything else behaves the same.

## sharing a build

### Linux

Don't send somebody the developer `./ionlancer` binary from a Guix or Nix, or any dynamic isolated linux distro build. Use the portable archive instead:

```sh
make portable
```

Then send:

```text
dist/ionlancer-linux-x86_64.tar.gz
```

That's the whole game, assets included.

### macOS

```sh
make portable-macos
```

Then send:

```text
dist/ionlancer-macos-arm64.tar.gz
```

Unpack it and double-click `ionlancer-macos-arm64.app`. The bundle carries its
own SDL2 and Modula-2 runtime, ad-hoc signed, so it does not need Homebrew or
MacPorts on the machine that opens it. Two details worth knowing:

- Homebrew's `sdl2` formula is [sdl2-compat](https://github.com/libsdl-org/sdl2-compat),
  a shim that loads SDL3 underneath. The bundler follows that runtime load as
  well as the ordinary link-time dependencies, so `libSDL3.dylib` travels with
  the app. Without it SDL aborts inside its own initializer.
- The game reads its assets through relative paths, so the bundle ships a tiny
  launcher that sets the working directory. That is what keeps the game itself
  free of any bundle awareness.

The build refuses to package a bundle that still points at `/opt`, `/usr/local`
or a package manager store, and it starts the finished app headlessly to prove
it works before it writes the archive.

## license

MIT.
