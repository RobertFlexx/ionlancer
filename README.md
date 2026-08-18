# IONLANCER

IONLANCER is a small arcade shooter written in GNU Modula-2 with SDL2. It runs on a 320x180 framebuffer, has a few game modes, several bosses, controller support, and a soundtrack called **Endless Endeavor** (as seen on my [youtube!](https://www.youtube.com/watch?v=IQyR7Mr_JS0))

I mostly made it because writing this kind of game in Modula-2 sounded fun.

## build

You need GNU Modula-2, SDL2, `pkg-config`, and make.

```sh
./BUILD-FIRST.sh
```

Or just: 

```sh
make release
```

## run

```sh
./run.sh --auto
./run.sh --x11
./run.sh --wayland
```

Controls are shown in-game. The basics are WASD/arrows to move, Z/Space to shoot, X/Shift for pulse, P to pause, M for the menu, and F11 for fullscreen.

## sharing a Linux build

Don't send somebody the developer `./ionlancer` binary from a Guix or Nix, or any dynamic isolated linux distro build. Use the portable archive instead:

```sh
make portable
```

Then send:

```text
dist/ionlancer-linux-x86_64.tar.gz
```

That's the whole game, assets included.

## license

MIT.
