# Master Turtle

A unified turtle program pack for ComputerCraft / CC:Tweaked, combining
a private turtle program collection with Inksaver's GUI toolkit, behind
one launcher menu,
with crash-proof resume on the long runners and an updater that pulls
from this repo.

Two trees, pick the one matching your Minecraft version:

- `1.12.x/` for Minecraft 1.12.2 (classic ComputerCraft)
- `1.20.x/` for Minecraft 1.20+ (CC:Tweaked)

Both trees ship the same programs. The only difference: `1.20.x` also
includes `tk3.lua` (Inksaver's classic GUI toolkit), which needs modern
peripheral APIs. Note for 1.20.x: modern CC:Tweaked runs Lua 5.2 and
removed the old `disable_lua51_features` config toggle entirely; the
pack handles 5.2 internally (the quarry shims the 5.1 functions it
needs), so there is nothing to configure.

## Install

Easiest way, on a fresh turtle or computer (HTTP must be enabled in
your ComputerCraft config):

```
pastebin get piTvMqye installer
installer
```

The installer detects your version (1.12.x or 1.20.x+), downloads the
updater, and runs it. After the first install, just run `updater` to
update.

Manual alternative with wget, if you prefer:

Minecraft 1.12.2:

```
wget https://raw.githubusercontent.com/GST-4649/Master-Turtle/main/1.12.x/updater.lua updater
updater
```

Minecraft 1.20+:

```
wget https://raw.githubusercontent.com/GST-4649/Master-Turtle/main/1.20.x/updater.lua updater
updater
```

The updater installs to the current directory. It never touches your
save files (`Civil_Quarry_Restore`, `.platformer_restore`, etc.) or the
quarry's `startup` resume stub.

## Quick start

Reboot the turtle. The launcher menu appears (via `startup.lua`):

- Up/Down moves, Enter runs, Q quits. Mouse works on advanced computers.
- Programs that need dimensions show a prompt first; fill in what you
  know and leave the rest blank (the program will ask).
- Entries tagged `[LOOP]` run until you stop them: press Q or Ctrl+T.
  The stop is graceful; long runners save their progress so you can
  resume later.
- When a program exits you return to the menu.

You can also run any program directly from the shell, e.g.
`quarry -dim 16 16 10` or `platformer -length 20 -width 12 -mode walls`.

## Programs

### Quarry

`quarry`: the massive variable-size quarry (civilwargeeky's lineage,
working copy v3.6.4.5). Digs a rectangular pit, sorts ores,
returns home when done or when out of fuel.

Dimensions: `-dim [length] [width] [height]`, e.g.
`quarry -dim 16 16 10`. Without it, the quarry prompts.

Full option flags (same names as the original design):

| Flag | Meaning |
|---|---|
| `-dim L W H` | quarry size in blocks |
| `-default` | skip all prompts, use defaults |
| `-invert [t/f]` | quarry upward instead of downward |
| `-oreQuarry [t/f]` | mine only ores, ignore common blocks |
| `-oldOreQuarry [t/f]` | legacy ore detection |
| `-blacklist [file]` | extra blocks to treat as non-ore |
| `-restore` / `-resume` | resume from the save file |
| `-autoResume` | reinstall the `startup` stub and resume on boot |
| `-atChest` | tell a resuming turtle it is already at home |
| `-chest [side]` | drop-off chest side (top/bottom/front/left/right) |
| `-enderChest [true\|slot]` | use an ender chest for drop-off |
| `-doRefuel [t/f]` | burn found coal/planks for fuel |
| `-doCheckFuel [t/f]` | check fuel usage as it digs |
| `-uniqueExtras [n]` | inventory slots reserved for low-stack items |
| `-rednet [t/f]` | rednet progress reports |
| `-sendChannel` / `-receiveChannel [n]` | rednet channels |
| `-GPS [force]` | use GPS for position on resume |
| `-startY [n]` | current Y, for bedrock detection |
| `-startupRename` / `-startupName [file]` | manage the resume stub |
| `-extraDropItems` | drop listed extra items |
| `-dumpCompareItems [t/f]` | dump before comparing chests |

Resume: the quarry writes `Civil_Quarry_Restore` as it works and can
restart exactly where it left off after a reboot or crash, with no GPS
and no extra mods. See "Resume" below. While a quarry run is active it
installs an extensionless `startup` stub that takes boot precedence and
auto-resumes (with a 5-second abort window); when our `startup.lua`
boots without that stub but finds the save, it offers the resume.

### Platformer (builder)

`platformer`: was a floor clearer, now a real builder (v6.1). Lays
blocks in a rectangle, one layer at a time, snake pattern.

Options (CLI args or interactive prompts, quarry-style):

- `-length N` `-width N`: footprint, `-height N`: layers (default 1)
- `-mode M`: `floor` (solid slab), `walls` (perimeter only),
  `solid` (everything), `hollow` (solid top and bottom, walls between),
  `roof` (see below)
- `-inverted`: build downward from the turtle instead of upward

Roof mode: the turtle starts at any level. Give `-height N` as blocks-up;
the turtle ascends N blocks, lays one flat roof over the footprint, then
descends back to its start. With `-inverted`, it places the ceiling
upward from the start level instead (no climbing).

Examples: a 20x12 wall ring 4 high:
`platformer -length 20 -width 12 -mode walls -height 4`.
A hollow 8x8x5 room: `platformer -length 8 -width 8 -mode hollow -height 5`.
A 16x16 floor: `platformer -length 16 -width 16 -mode floor`.
A roof 6 blocks up over 10x10: `platformer -length 10 -width 10 -mode roof -height 6`.

Resume: progress is saved per layer to `.platformer_restore`; a run
interrupted mid-build resumes on the layer it left off. A `startup`
stub auto-resumes on boot (5-second abort window).

### Cropper (auto farmer)

`cropper`: farms a crop field: harvests mature crops, replants,
deposits to a chest behind it. Args: `-length N -width N` (field size),
or it prompts. Resume via `.cropper_restore`.

### Cluster scanner

`cluster`: AE2 quartz cluster scanner. Walks a grid breaking stone to
expose certus quartz. Args: `-length N -width N -wait N` (wait seconds
between sweeps). Runs until stopped.

### Filler

`filler`: fills a volume with falling blocks (sand/gravel). Args:
`-length N -width N`, or it prompts. Resume via `.filler_restore`.

### Vacuum

`vacuum`: floor sweeper: walks a grid sucking up loose items.
Args: `-length N -width N`, or it prompts. Runs until stopped.

### TRMP (trump)

`trump`: layered wall builder, snake pattern. Args: `-length N`
(wall length, X), `-height N`, `-depth N` (thickness), or it prompts.

### Framer

`framer`: builds a hollow room shell (or edge frame) of size N.
Arg: `-size N`, or it prompts.

### ChopChop, Cranker, Attacker, Cobble miner

`chopchop`: chops trees, replants saplings. Runs until stopped.
`cranker`: turns a crank (e.g. Create mod). Runs until stopped.
`attack`: auto-attacks mobs; prompts for weapon and refuel options.
Runs until stopped.
`cobble`: infinite cobble miner; dumps to chests. Runs until stopped.

### Refuelers and utilities

`buckRef`: refuels from any filled bucket (lava, etc.).
`lavaRefuel`: refuels while parked on a lava lake.
`flint`: turns gravel into flint.
`go`: interactive WASD turtle driver.
`data`: inspects the block/item in front, above, or below.
`b`/`d`/`f`/`u`: move back/down/forward/up N blocks; add any second
arg to dig through, e.g. `f 10 d`. `f` also takes `+`/`-` to dig
above/below while moving.
`l`/`r`: turn left/right N times. `p`: place block. `x`: dig.

### Toolkit v3 (1.20.x only)

`tk3`: Inksaver's classic GUI toolkit: build projects (tree farm,
spawner farm, quarry, tunnels, etc.) from a menu. Needs 1.20+.

### AI Chat (optional)

`cc-ai`: chat with an AI from the turtle (RareMojo/cc-ai, MIT). Needs
the Python server running somewhere reachable; see
`optional/cc-ai/SERVER_SETUP.md`. First run walks through setup.

### Updater

`updater`: reinstalls/updates this pack from GitHub. Run it after a
release to pull the latest.

## Resume

Long runners save progress so a reboot or crash does not lose work:

- `quarry`: `Civil_Quarry_Restore` (full state snapshot; the crown
  jewel, preserved exactly as shipped). Resume with
  `quarry -resume`, or let the `startup` stub do it on boot.
- `platformer`: `.platformer_restore` (per-layer progress).
- `filler`: `.filler_restore`. `cropper`: `.cropper_restore`.
  `cluster`: `.cluster_restore`.

All but the quarry share `lib/Resume.lua`: save a table, load it back,
install/remove a `startup` stub that re-runs the program with `-resume`
after a 5-second abort window. The quarry keeps its own original
resume code untouched.

## Dimensions

Programs whose working size depends on your build ask for it at start,
either as command-line args or interactively: quarry (`-dim`),
platformer (`-length -width -height -mode -inverted`), cropper,
cluster, filler, vacuum (`-length -width`), trump
(`-length -height -depth`), framer (`-size`). The launcher prompts for
these before running.

Programs with fixed-by-mechanics sizes stay hardcoded: `flint` (one
gravel at a time), `buckRef`/`lavaRefuel` (the turtle's own fuel tank),
`go`/`data` (single interaction), movement commands (you give N each
time).

## Files

- `master.lua`: the launcher; `startup.lua` boots it.
- `scenes/`: launcher screens (Launcher, Dimensions, CCAI) plus the
  Toolkit v3 scenes it loads (MainMenu, GetItems, Help, TaskOptions, Quit).
- `lib/`: shared libraries, including `lib/Resume.lua`.
- `optional/cc-ai/`: the optional AI chat module and server setup.
- `updater.lua`: installer/updater for this repo.
