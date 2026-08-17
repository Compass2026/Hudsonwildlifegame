# Handoff

Written for the next coding agent picking this project up cold. It covers what
the project is, how it is put together, how to build and ship it, and — most
usefully — the specific ways it has broken before, because several of them are
invisible to the test suite unless you know to look.

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) as well. That file explains
*why* the layering is the way it is and is the authority on it; this file is the
operational side. [`README.md`](README.md) is written for a human player.

---

## 1. What this is

A wildlife exploration, tracking and conservation-research game in **Godot 4.7.1
Standard** (not .NET) and GDScript. You play a field researcher: explore,
observe, find sign, track, identify, document, report.

The design constraint that shapes everything: **the player must not be able to
simply walk up to an animal.** They find evidence, interpret it, and reason
about it. Tracking is deliberately not "follow the glowing footprints".

The current milestone is *The Ridgeline Report* — a headwater drainage with a
common bobcat and a rare Canada lynx in it. Both leave four-toed clawless prints
in the same mud. Telling them apart from their sign is the whole game.

### Rules that are not up for casual revision

These came from the project owner and are load-bearing:

- **Gameplay never depends on presentation.** Not a stylistic preference — the
  headless test suite exercises every rule that decides what the player may
  conclude, with no window and no 3D. Breaking the seam breaks the tests.
- **No giant scripts.** Independent systems that talk through signals and data
  objects. Signal payloads are data, never `Node`s.
- **Content provenance is mandatory.** Every species and scenario declares
  `REAL`, `HISTORICAL` or `SPECULATIVE`, and the UI must show it. An extinct
  species must never be presented as currently living, and a fictional
  discovery must never read as a real scientific record.
- **Evidence has to be unequal.** A blurry photo is not a clear one; one
  eyewitness is not proof; a footprint may narrow the field without settling it.
  Rare species demand more.
- **False leads are required.** Not every investigation succeeds, and
  "inconclusive" is a legitimate, supported outcome.
- **Animals behave like animals** and produce evidence naturally as they move.
  Sign is a by-product of simulated behaviour, not something sprinkled on a map.

---

## 2. Folders

```
core/          Vocabulary shared by everything: EventBus, settings, enums,
               input map (registered in code, so project.godot stays mergeable),
               build stamp
data/schemas/  Resource classes: SpeciesData, TrackProfile, BehaviorProfile,
               InvestigationData
data/species/  One JSON per species. Adding a species is a JSON file, no code
data/investigations/  One JSON per scenario
systems/       Gameplay. No meshes, no Controls, no screen space, no assets
presentation/  Everything visible or clickable. Disposable by design
scenes/        Composition root — the only place that knows what THIS build is
tests/         Headless suites plus the screenshot harness
tools/         export_web.sh
web/           The committed browser build that Vercel serves
docs/          ARCHITECTURE.md
```

`web/` carries a `.gdignore` so the engine does not import the exported build
back into the project as source assets.

## 3. Gameplay systems

Autoloads, registered in `project.godot`:

| Autoload | File | Responsibility |
|---|---|---|
| `EventBus` | `core/event_bus.gd` | Every cross-system signal |
| `Settings` | `core/game_settings.gd` | Accessibility and preferences |
| `GameClock` | `systems/time/game_clock.gd` | Day, hour, light level, decay timebase |
| `SpeciesDB` | `systems/database/species_database.gd` | Loads species and investigations from JSON |
| `EnvironmentSystem` | `systems/environment/environment_system.gd` | Ground height and substrate, via a provider |
| `EvidenceSystem` | `systems/evidence/evidence_system.gd` | Registry, ageing, case strength |
| `IdentificationSystem` | `systems/identification/identification_system.gd` | Ranking, evidence standards, verdicts |
| `InvestigationSystem` | `systems/investigation/investigation_system.gd` | Objectives, filing reports |
| `FieldNotebook` | `systems/notebook/field_notebook.gd` | The player's record |

Non-autoload gameplay classes: `AnimalBrain`, `AnimalController`,
`AnimalSpawner`, `TrackEmitter`, `TrackExaminer`, `FieldCamera`, `Substrate`.

Three ideas you need before changing anything in `systems/`:

**Truth vs observation.** `EvidenceRecord` holds `truth` (what really made it)
and `observed` (what the player managed to read). `source_species_id` is ground
truth and **must never be shown to the player** — misidentification is only
possible because these are separate fields. If you surface it in UI you have
deleted the game.

**Fit is a product, not an average.** `IdentificationSystem.rank()` multiplies
likelihood by prior across evidence. It was briefly normalised into a geometric
mean, which made evidence stop accumulating — four good tracks scored the same
as one. Do not reintroduce averaging.

**Case strength is separate from fit.** `EvidenceSystem.case_strength()` applies
`pow(0.55, n)` diminishing returns per repeat of a kind, so twenty tracks are not
twenty proofs. Breadth of independent evidence is what builds a case.
`SpeciesData.evidence_standard` then says how much a claim of *that* species
requires. Rare animals demand more, which is the mechanical expression of the
design rule above.

## 4. Controls

Defined in `core/input_actions.gd`, registered at runtime.

| Key | Action |
|---|---|
| `WASD` / arrows | Move |
| `Shift` | Move slowly (you notice much more) |
| `C` | Crouch |
| `E` | Examine the sign in front of you |
| `F` | Raise / stow the field camera |
| Mouse wheel | Zoom (camera raised) |
| Left mouse | Shutter |
| `Tab` | Open / close the field notebook |
| `Esc` | Close an open panel, or release the mouse |

---

## 5. Building and testing

```bash
# Gameplay rules, no graphics at all
godot --headless --path . res://tests/test_runner.tscn    # 14 checks

# Boots the real game scene headless
godot --headless --path . res://tests/smoke_test.tscn     # 31 checks
```

Both exit non-zero on failure. Run both before every commit.

**Headless cannot see rendering faults.** Three of the worst bugs this project
has had were invisible to it. For anything visual use the screenshot harness:

```bash
xvfb-run -a -s "-screen 0 1280x720x24" \
  env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
  godot --path . --rendering-driver opengl3 --resolution 1280x720 \
    res://tests/screenshot.tscn
```

It prints where the PNGs landed. `--rendering-driver opengl3` is Compatibility,
which is what the browser runs — prefer it when checking anything that has to
work in the Web build. Under llvmpipe this renders at roughly 3 fps, so each
shot takes several seconds; **that is normal, not a hang.** A real hang is
almost always an error thrown inside `_ready()`, which aborts the coroutine
before `get_tree().quit()` is ever reached, and the process then sits until the
timeout. If a screenshot run appears to stall, look for a script error first.

Note this container has no Vulkan, so **Forward+ (the desktop default) cannot be
exercised here** — only Compatibility. Desktop-specific rendering needs checking
on real hardware.

## 6. Web export

```bash
tools/export_web.sh /path/to/godot     # defaults to `godot` on PATH
```

Bump `BUILD` in `core/build_info.gd` first. It is shown in the HUD corner, and
it is the only way to tell a refreshed page from a cached one.

The script exports, renames every produced file except the page and its icons to
`hudson-<BUILD>.*`, repoints `index.html`, verifies the patch took, and copies
the result into `web/`.

**Why the renaming exists.** Godot always emits `index.wasm` / `index.pck`.
Those names never change between builds, so a browser that cached them once
keeps serving the old game forever, and because `index.html` revalidates while
the pack does not, players end up running a *new page against an old pack*. This
happened for real, twice. Version-stamped filenames make it structurally
impossible: a new build requests URLs the browser has never seen.

**Do not turn the rename back into a hardcoded list of extensions.** The engine
resolves its sidecars through `locate_file("godot.<suffix>")` →
`<executable>.<suffix>`, so all of them must move together. Godot 4.7 added
`index.audio.position.worklet.js`; the old fixed list missed it, the engine
requested the versioned name, and the resulting 404 was silent. The script now
renames everything and then asserts that every `locate_file` name referenced by
the loader exists on disk, so the next added sidecar fails the build loudly.

## 7. Vercel deployment

Vercel serves the committed `web/` directory — there is no build step on
Vercel's side, it publishes static files straight from the repo.

The workflow is:

1. Bump `BUILD` in `core/build_info.gd`.
2. Run `tools/export_web.sh`.
3. Commit the changed `web/` contents.
4. Push. Vercel deploys automatically; a plain reload picks it up.

Pushing a non-production branch produces a **preview** deployment, which is the
right way to check a risky change without touching what players are using.

`web/vercel.json` sets revalidating (not `immutable`) cache headers as a second
line of defence behind the filename stamping. Two things to know about it:
it must live in the directory Vercel serves, and **Vercel rejects unknown
top-level keys** — adding a `$comment` key once failed the deployment before the
build even started, so there is nowhere in that file to leave a note.

---

## 8. Known issues and traps

Ordered by how much time they will cost you.

**The browser has a draw-call ceiling and fails silently.** Roughly 1200
`MeshInstance3D` nodes kills the *entire* 3D pass in WebGL2 — no error, no
warning, just nothing drawn — while the same scene is fine on desktop at 2015.
This killed the Web build three separate times: once from one material per
track, once from four unique meshes per tree, once from sheer node count. **Draw
calls are the metric that actually bites.** Anything numerous — tracks, trees,
shrubs, rocks — must go in a `MultiMesh` with shared meshes and materials.
`smoke_test.gd` budgets draw calls (≤400), unique meshes (≤150) and unique
materials (≤60); current build sits at 125 / 69 / 31. If you add scenery, watch
those numbers.

**Godot's front face is the CLOCKWISE winding.** Get it backwards and the
surface is culled from every angle a player can stand at: it exists, has a
correct AABB, passes every geometry assertion, and draws nothing. The creek
water was invisible for exactly this reason while its geometry tested perfectly.
Compare any new hand-built surface against the terrain in
`prototype_valley.gd`, which is wound correctly. `smoke_test.gd` now asserts the
water faces the same way as the ground.

**Fog will eat the sky.** `Environment.fog_sky_affect` defaults to `1.0` and the
sky is at infinite depth, so exponential fog saturates it into one flat sheet.
Godot 4.3's Compatibility renderer did not apply fog to the sky at all, so this
only appeared on the 4.7 upgrade. It is pinned to `0.0` in `_build_sky()`.

**Tab is also Godot's built-in `ui_focus_next`.** A focused button swallows it.
Since movement is blocked while a panel is open, that soft-locked the player
completely. The notebook now claims the key in `_input` with
`set_input_as_handled()`, there is a visible close button, and movement is gated
on `EventBus.ui_modal_changed` rather than on mouse-capture state. There is a
regression test; keep it.

**`set_anchors_preset()` alone does not size a Control** under a `CanvasLayer`.
The HUD sat at size (0,0), so everything anchored to the screen centre laid out
around the origin — the camera viewfinder showed up as a white box in the corner.
Set anchors *and* offsets. Tested by "the HUD fills the viewport".

**`look_at()` rewrites the whole basis and discards scale.** Aim first, scale
last, or your object floats away from where you put it. This is what broke the
tent's guy lines.

**Physics engine is pinned.** `project.godot` sets
`physics/3d/physics_engine="GodotPhysics"`. Godot 4.6 made Jolt the default for
newly created projects; the player's walk speed, step height and slope limits
are tuned against GodotPhysics. Moving to Jolt is a deliberate decision with
re-tuning attached, not something to let happen by upgrade drift.

**Export template version must match the editor version** exactly, or the Web
export fails. If you change engine version, fetch matching templates.

**Do not commit `tests/_shot*`-style throwaway debug scenes.** Use
`tests/screenshot.tscn`, which is a permanent, documented harness.

---

## 9. Design decisions worth not re-litigating

- **Placeholder art is intentional.** `SpeciesData.visual_scene` is the single
  art hook; when it is null the game builds a primitive stand-in from
  `placeholder_color`, `body_length_m` and `shoulder_height_m`. Real models drop
  in by pointing that field at a scene. Do not scatter art references anywhere
  else.
- **Tracks are generated per species from `TrackProfile`** — foot shape, heel
  and toe proportions, toe spread, edge softness. A lynx leaves a broad round
  print blurred by its own foot fur; a bobcat leaves a crisper one at about half
  the width. Shape, not just size, carries the identification, and the field
  guide text depends on that being true.
- **The rare animal is found by tracking, not by wandering.** The investigation
  uses a `photograph_species` objective, so only a usable photograph of the lynx
  completes it. A photograph of the bobcat is still filed as evidence but does
  not finish the job — **and the game does not tell the player which one they
  got.** Working that out is the point. Do not add a "correct species" hint.
- **ACES tonemapping, colour adjustments off.** Adjustments need a post-process
  pass that is not dependable on the Compatibility renderer the browser uses.
- **The input map is built in code** (`core/input_actions.gd`) so `project.godot`
  stays small and mergeable.
- **Terrain noise is damped toward the creek bed.** The channel is 7 m deep and
  the hillside noise was ±14 m, so the noise simply drowned the carve and the
  true low point wandered metres off the centre line. Water needs its bed to
  actually be the lowest ground.

---

## 10. Branches

- `claude/wildlife-game-godot-dhuswb` — the working production branch; this is
  what has been deployed to players.
- `upgrade/godot-4.7.1` — the 4.3 → 4.7.1 engine migration.

The upgrade branch is verified (45/45 headless checks, rendering confirmed on
Compatibility, Web build driven in a real headless Chromium with no console
errors and no failed requests) but is deliberately **not merged**. Merging is
the project owner's call.
