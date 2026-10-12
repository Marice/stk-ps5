# SuperTuxKart for the PlayStation 5

A port of [SuperTuxKart](https://supertuxkart.net) 1.5 to native PS5
homebrew. It runs as an installed title (`PPSA69421`) and renders through the
[PS5 OpenGL SDK](https://github.com/blackbearreloaded/ps5-opengl).

> **Alpha.** This is a first test build. It runs at 60 fps on the tested
> console, but expect bugs. Network play is switched off, and the options
> screen can crash after some navigation. Please report problems as an issue
> in this repository, with `stk.log` from the title folder attached.

## What works

Tested on the console:

- Story mode (the overworld) and single races, at about 60 fps
- Dynamic lighting (the advanced renderer) at 1920x1080
- The DualSense, with a racing-game button layout (see below)
- Music and sound effects
- The first player is named after your PS5 account

Grand Prix, battle, soccer and the other modes are untested.

## Known issues

- **No network play.** Starting the online code ends the process during its
  start-up on the console, so internet access is switched off. Online races,
  add-on downloads and news are not available. LAN play is not tested.
- **The options screen can crash** after navigating in it for a while. Graphics
  and sound settings are fixed in this build for that reason.
- **Text input** uses SuperTuxKart's own on-screen keyboard; the PS5 system
  keyboard does not appear.
- **The first load of a track takes a while.** Later loads are quicker.
- Tested on one console, firmware 13.60, with ShadowMountPlus.

## Installing

1. Download `PPSA69421.zip` from the latest release.
2. Extract it and copy the `PPSA69421` folder to `/data/homebrew/` on the
   console (for example over FTP), or install it with
   [ProsperoStore](https://github.com/blackbearreloaded/ProsperoStore).
3. Let ShadowMountPlus register the title, then start SuperTuxKart from the
   home screen.

The game keeps its settings, saves and log inside the title folder:
`.config/supertuxkart/`, `.local/share/supertuxkart/` and `stk.log`.

## Controls

| Button | In a race | In menus |
| --- | --- | --- |
| Cross | Accelerate | Confirm |
| Square | Brake and reverse | |
| Circle | Use item | Back |
| Triangle | Look back | |
| L1 | Nitro | |
| R1 | Drift | |
| Touchpad | Rescue the kart | |
| Options | Pause | |
| Left stick or D-pad | Steer | Move |

## Building

You need Linux or WSL, the
[PS5 payload SDK](https://github.com/ps5-payload-dev/sdk) at
`/opt/ps5-payload-sdk`, a PacBrew sysroot with SDL2 and the game's libraries,
the `ps5-native-tool` converter from the
[native app boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate),
and a PS5 OpenGL SDK (see below).

```sh
git clone https://github.com/supertuxkart/stk-code.git
git -C stk-code checkout 5e7a54420a2748ae5a5e743555dd00ddf513302d
git -C stk-code apply ../patches/stk-code.patch
./build.sh            # configure, build, convert, sign; writes pkg/PPSA69421/
./tools/package.sh    # dist/PPSA69421.zip and its sha256
```

`pkg/PPSA69421/data/` must hold the asset tree of the SuperTuxKart 1.5
release; `build.sh` also writes the folder manifest (`dirs.txt`) from it.
`PS5_PAYLOAD_SDK`, `PACBREW`, `PS5_NATIVE_TOOL` and `PS5_OPENGL_SDK` override
where things are looked for. `./upload.sh` copies the title folder to the
console over FTP, and `./log.sh` reads `stk.log` back.

### The OpenGL SDK

The release build links an SDK built from upstream `main` with per-draw
profiling turned off; the 1.0.1 release ran the 3D scenes at a fraction of
the frame rate. The branch `stk-no-profile` of
[Marice/ps5-opengl](https://github.com/Marice/ps5-opengl) makes that build on
GitHub Actions.

## How the port works

The changes to SuperTuxKart are in `patches/stk-code.patch`, against upstream
commit `5e7a5442`. The rest of this repository adapts the build and the
platform:

| File | What it does |
| --- | --- |
| `ps5-gl.cmake` | Targets for the OpenGL SDK and SDL2, the system modules, link flags and `--wrap` replacements |
| `ps5-posix.c` | POSIX calls a title cannot use: no environment, no working directory, no folder listing. Replaced with an emulated working directory, a folder manifest, `stat`-based `access` and `realpath`, and crash reporting |
| `ps5-support.c` | Opens `stk.log`, sets the heap size, reports frame rate and memory |
| `ps5-heap.c` | The OpenGL SDK's allocator, which takes memory from direct memory |
| `ps5-crt.cpp`, `ps5-cpp-runtime.cpp` | Entry point and C++ runtime glue from the native app boilerplate |
| `ps5-pie.ld` | The memory layout the console's loader accepts |
| `tools/make-backgrounds.py` | Home screen backgrounds (BC7 DDS) |

Inside the game, the main changes are: the screen comes from EGL instead of
SDL's video driver; shader uniforms and vertex attribute locations are read
from the shader source, because the driver cannot list them (reported as
[ps5-opengl#9](https://github.com/blackbearreloaded/ps5-opengl/issues/9));
instance data uses 32-bit integers the driver can fetch; and logs are written
buffered, because many small writes to the title folder are very slow.

## Licences and credits

- The port's own files are GPL-3.0-or-later (`LICENSE`), like SuperTuxKart's
  code.
- SuperTuxKart: code GPL-3.0-or-later, data under the licences listed in its
  data files. See [supertuxkart.net](https://supertuxkart.net) and the
  `CREDITS` file in `data/`.
- PS5 OpenGL SDK and native app boilerplate: GPL-3.0-or-later, by
  BlackBearReloaded.
- The home screen background is the menu background of SuperTuxKart's
  cartoon-forest skin (`data/skins/cartoon-forest/background.jpg`),
  copyright 2018-2020 LCP and QwertyChouskie, licensed CC-BY-SA 4.0.

SuperTuxKart is developed by the SuperTuxKart team. This port is not
affiliated with or endorsed by them or by Sony.
