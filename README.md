# Hudson Wildlife

A wildlife exploration, tracking, research and conservation game built in
Godot 4 with GDScript.

You are a field researcher. You go into wild places to find out what is actually
there — by reading ground, following sign, and being honest about how far your
evidence goes.

**Milestone 1 (this build): The Ridgeline Report.** A small headwater drainage
in the southwestern Adirondacks. A volunteer reports a large grey cat with black
ear tufts. Bobcats are common here and are routinely reported as lynx. Find out
what is using that drainage.

---

## Running it

1. Install **Godot 4.3 or newer** (standard build, not .NET) from
   <https://godotengine.org/download>.
2. `git clone` this repository.
3. Open the Godot project manager → **Import** → select `project.godot` → **Import & Edit**.
4. Press **F5**.

First import takes a moment while Godot builds its `.godot/` cache. That folder
is gitignored.

Verified on Godot 4.3 stable (Linux).

### Headless tests

```bash
godot --headless --path . res://tests/test_runner.tscn   # gameplay rules
godot --headless --path . res://tests/smoke_test.tscn    # boots the real scene
```

Both exit non-zero on failure. `test_runner` runs the whole evidence and
identification chain with no graphics at all — that is the architectural
guarantee, not just a convenience. `smoke_test` boots the actual game scene
headless and checks the world answers gameplay queries, the animals are laying
down sign, and nothing has been handed to the player for free.

---

### Browser build

A Web export is committed under `web/` and deployed to Vercel, so you can try
the prototype without installing anything. It is a convenience, not the target
platform — desktop loads faster, runs better, and gives you a console.

To rebuild it after changing the game, bump `BUILD` in `core/build_info.gd`
(it is shown in the HUD, so you can always tell which build is running) and run:

```bash
tools/export_web.sh /path/to/godot
```

Then commit `web/` — Vercel deploys it automatically and a plain reload picks it
up.

**Do not just export and copy.** Godot always emits `index.wasm` and
`index.pck`, and those names never change between builds. A browser that cached
them once keeps serving the old game no matter how often you reload — and
because `index.html` revalidates while the pack does not, players end up running
a *new page against an old pack*. That bit us for real: a build shipped, the
page updated, and the game did not.

`tools/export_web.sh` renames the pack, wasm and loader after the build
(`hudson-m1.6.pck`, …) and repoints `index.html` at them, so a new build
requests URLs the browser has never seen. Caching then cannot pin anyone to an
old build. `web/vercel.json` also sets revalidating rather than `immutable`
headers as a second line of defence — note it rejects unknown top-level keys, so
there is nowhere in it to put a comment.

The export preset is committed (`export_presets.cfg`). It uses the
no-threads template, so the build needs no cross-origin isolation headers and
will run on any static host. Note that the browser build uses the Compatibility
renderer (WebGL 2) while desktop uses Forward+, so lighting looks slightly
different; no gameplay system is aware of the difference.

## Controls

| Key | Action |
|---|---|
| `WASD` | Move |
| `Shift` | Move slowly (you notice much more) |
| `C` | Crouch |
| `E` | Examine the sign in front of you |
| `F` | Raise / stow the field camera |
| Mouse wheel | Zoom (camera raised) |
| Left mouse | Shutter |
| `Tab` | Open / close the field notebook |
| `Esc` | Close an open panel, or release the mouse |

The notebook opens on the briefing when the investigation starts. Close it with
`Tab`, `Esc`, or the button at its foot — you cannot walk while a panel is up.

---

## How to play the first investigation

Read the briefing when the notebook opens, then close it with `Tab`.

Walk north from camp and **follow the creek**. Tracks only register where the
ground takes them — creek mud holds a print, ledge rock and leaf litter mostly
do not. Move at walking pace or slower; sprinting past a trail is a real way to
miss it.

When you find sign, press `E`. You will get measurements, an error margin, and a
list of what could not be read. You will not be told the species. Open the
notebook's **Field guide** tab and compare: lynx prints run 8–11.5 cm wide,
bobcat 4–6 cm, and a soft-ground bobcat print spreads and reads larger than it
is. That ambiguity is the game.

Photograph the animal if you can get one — distance, light, cover and your own
movement all show up in the image. Then return to camp and file.

**Inconclusive is a legitimate result and the game treats it as one.** Claiming
a lynx on thin evidence gets you told, in detail, why it does not hold.

---

## Layout

```
core/          Event bus, settings, shared enums
data/          Schemas + content (species and investigations as JSON)
systems/       Gameplay logic — no graphics, no assets, no screen space
presentation/  World, player, UI, placeholder art — all replaceable
scenes/        Composition root
tests/         Headless system tests
docs/          Architecture notes
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for how the layers are kept
apart and where future systems attach.

---

## Real, historical, speculative

The game mixes real conservation science with invented scenarios, so every piece
of content declares which it is, and the interface shows it.

- **REAL** — species facts, conservation status, tracking characteristics and
  regional history are drawn from published sources, listed in the field guide.
- **HISTORICAL** — a scenario set at a stated past date.
- **SPECULATIVE** — invented. Labelled `FICTIONAL / SPECULATIVE` wherever it
  appears, including in the verdict text.

Nothing you conclude in this game is a scientific record. The game says so
itself when you file a report.

---

## Adding a species

Create `data/species/your_species.json`, copy the shape of
`data/species/bobcat.json`, and it is in the game — field guide entry,
identification scoring, evidence standard, AI behaviour and a placeholder body,
with no code changes. Add art later by pointing `presentation.visual_scene` at a
scene file.
