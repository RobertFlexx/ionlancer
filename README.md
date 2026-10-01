# IONLANCER

IONLANCER is a pixel-art arcade shooter written in GNU Modula-2 with SDL2. It runs on a 320x180 framebuffer. The expanded game has five playable ships, seven run modifiers, seven modes, eleven enemy types, eight bosses, and nine selectable in-game soundtracks. The official soundtrack, **[Endless Endeavor](https://www.youtube.com/watch?v=IQyR7Mr_JS0)**, plays on the title screen and is available in the hangar.

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

Controls are shown in-game. Left/right selects a mode, up/down selects a ship,
and X/Shift opens the hangar. M opens the controller-aware controls guide from
the title. In the hangar, up/down chooses a row and left/right
changes the ship, modifier, or music. During play, WASD/arrows move, Z/Space
shoots, X/Shift uses a charged pulse, P pauses, M returns to the menu, and F11
toggles fullscreen. On macOS,
Command+Enter and Control+Command+F also toggle fullscreen. The picture stays
centered and keeps its pixel art aspect ratio when the window changes size.

F2 opens settings from any screen. Click the controller's left stick to open
the same menu. Up/down selects a row, left/right adjusts it, and X/the west
face button switches between Audio and Display. Escape/the east face button
closes it. Audio has separate master, music, weapon, impact, alert/pickup, and
menu sound volumes. Display offers fullscreen, integer pixel scaling, screen
shake, hit flashes, and Restore Defaults. Changes apply immediately and are
saved in SDL's per-user preferences directory. Opening settings pauses a solo
run; closing it returns to the pause screen so you can resume when ready.

Controllers can be connected or disconnected while the game is running. The on-screen
button prompts follow the last device used and show Xbox, PlayStation, or Nintendo
symbols when SDL identifies the controller. Generic pads use SDL's A/B/X layout.

| Action | Controller |
| --- | --- |
| Move and select mode | D-pad or either stick |
| Fire and confirm | South face button or right trigger |
| Pulse | West, east, or north face button; either bumper or left trigger |
| Pause and resume | Start/Options/+ |
| Return to title | Back/View/Share button; east face button in menus |
| Toggle fullscreen | Right stick click |
| Settings | Left stick click |

On the title screen, the D-pad or either stick changes modes with left/right
and ships with up/down. The west face button opens the hangar. In the hangar,
up/down picks a row and left/right changes its choice. The game displays button
art for the last controller family used. Back/View/Share opens the controls
guide on the title screen.

The title, pause, and result screens also accept the south face button to confirm
and the east face button to go back. The east face button activates pulse during
play.

## game modes

| Mode | Objective |
| --- | --- |
| Campaign | Fight through eight chapters and 24 sectors, each ending in a different boss. |
| Endless | Survive escalating waves and chase a high score. |
| Boss Rush | Face all eight bosses without ordinary waves. |
| Gauntlet | Faster waves and a boss every two waves. |
| Time Attack | Score as much as possible in four minutes. |
| LAN Co-op | Two pilots share eight survival waves, two bosses, and a pulse-powered revive. |
| LAN Versus | Duel in a best of five match, with a three-minute match clock. |

The hangar offers Ironwing (balanced), Kestrel (fast fire), Bastion (extra hull
and shield), Specter (pulse specialist), and Comet (heavy shots). Its seven
modifiers trade power for a cost: Standard, Overdrive, Fortify, Siphon, Bounty,
Nova, and Focus Lens. The eight synth tracks are Ion Drift, Neon Chase, Aster
Bloom, Event Horizon, Afterburn, Solar Wake, Crystal Circuit, and Starlight
Relay. Each shuffled playlist plays every synth track once before reshuffling,
and avoids repeating the last song across playlist boundaries. Endless
Endeavor joins one in every four playlists as a rare bonus (about 3% of automatic
track selections). The hangar can explicitly choose any opening track, which
is consumed from that playlist. Hangar previews do not consume songs.
Music rotates after boss fights, between LAN waves or rounds, and after 75
seconds of active play so quieter stretches also give the roster a turn.

The synth arrangements retain their arcade instrumentation, with softer note
attacks and releases, corrected high-intensity pad playback, and a gentle
limiter for loud peaks. Music and sound effects retain their timing when muted.

Enemy drops now include shields, rapid fire, triple shots, repairs, pulse
energy, score caches, and brief invulnerability. The campaign's chapter cards
and changing nebula colors mark your progress through its eight boss fights.

### LAN play

Both players need the same game version and access to each other on a local
network. The host selects **LAN Co-op** or **LAN Versus**, chooses **Host game**,
and presses Connect. The guest selects the same mode, switches to **Join host
IP**, enters the host's IPv4 address, and presses Connect. The game uses UDP
port **37177**. Each player brings their own ship and modifier from the hangar.

Type an address with the number keys and periods, or use left/right to choose
an octet and up/down to change it with a controller. Hold the right bumper (or
Ctrl on a keyboard) while pressing up/down to change an octet by ten. The west
face button switches between hosting and joining; the east face button returns
to the title. The host controls the match simulation and sends snapshots to
the guest. If the connection briefly drops, the game waits for the same guest
to reconnect. Co-op pilots can spend a full pulse to revive a fallen teammate;
versus pilots earn pulse from hits. P/Start pauses or resumes the LAN match;
opening settings also pauses both players while keeping the connection alive.
Each pilot must release their own pause before play resumes. Brief reconnects
preserve the match and the pilot's original ship and modifier. Versus gives each ship three hull before
modifier costs, and the first pilot to win three rounds wins the match.

Version 2.1 uses LAN protocol v3; both pilots must use this version. The UDP
bridge checks packet sizes, allowed values, peer addresses, and lobby modes.
The guest validates snapshot fields before applying them, and old or duplicate
sequences cannot update controls or extend the connection timeout. LAN play
is intended for a trusted local network; it does not authenticate or encrypt peers.

Run `make test-lan` to exercise two local pilots, mode switching, guest handoff,
sound packets, shared pause, replay timeouts, reconnects, malformed packets,
snapshot validation, and sequence wrap. Run `make test-quality` for settings,
keyboard/controller navigation, shuffle coverage, audio isolation, soundtrack
levels, and deterministic gameplay checks against the previous version.

## macOS

Builds native (Apple Silicon or Intel) against whatever SDL2 `pkg-config` finds,
and runs straight from the repository. Fullscreen can be switched with
Command+Enter, Control+Command+F, F11, or the right stick button.

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
# or dist/ionlancer-linux-aarch64.tar.gz on ARM64
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

### Windows

The release workflow builds an x86_64 Windows zip with GNU Modula-2 and SDL2
under MSYS2 UCRT64. The zip includes the executable, assets, and required DLLs.
The same zip is launched on a Windows ARM64 runner as a compatibility check;
Windows ARM64 uses x64 app emulation for this build.

## releases

Pushing a tag matching `v*` builds native macOS archives for Apple Silicon and
Intel, portable Linux archives for ARM64 and x86_64, and a Windows x86_64 zip.
The workflow only publishes a GitHub release after every package passes its
headless launch check, including the Windows ARM64 compatibility check. Each
release includes SHA-256 checksums. Pushing to `main` or starting the workflow
manually builds and checks the packages without publishing a release.

## license

MIT.
