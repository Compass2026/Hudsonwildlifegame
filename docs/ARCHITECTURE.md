# Architecture

The one rule everything else follows:

> **Gameplay systems must never depend on presentation.**
> Presentation may depend on gameplay. Nothing may depend on a specific asset.

If you remember nothing else: a gameplay system is not allowed to know what a
mesh, a material, a `Camera3D` or a `Control` is. The headless test suite exists
to keep us honest — it exercises every rule that decides what the player can
conclude, with no window and no 3D at all.

---

## Layers

```
core/          Vocabulary shared by everything. Signals, enums, settings.
data/          Schemas (Resource classes) + content (species, investigations).
systems/       Gameplay. No nodes-with-visuals, no screen space, no assets.
presentation/  Everything you can see or click. Disposable by design.
scenes/        Composition roots. The only place that knows what THIS build is.
tests/         Headless verification of gameplay rules.
```

### Who may talk to whom

```
presentation ──reads──▶ systems ──reads──▶ data
      │                    │
      └──────emits/listens─┴──────▶ EventBus ◀── everything
```

- Systems communicate through **EventBus** (`core/event_bus.gd`) and through
  data objects. They do not hold references to each other's nodes.
- Signal payloads are **data**, never nodes. A `Node` in a signal is a leak.
- Presentation subscribes to EventBus and queries systems. It never gets asked
  a gameplay question.

---

## The systems

| System | Autoload | Responsibility |
|---|---|---|
| `core/event_bus.gd` | `EventBus` | Every cross-system signal |
| `core/game_settings.gd` | `Settings` | Accessibility and preferences |
| `systems/time/game_clock.gd` | `GameClock` | Day, hour, light level, decay timebase |
| `systems/database/species_database.gd` | `SpeciesDB` | Loads species + investigations |
| `systems/environment/environment_system.gd` | `EnvironmentSystem` | Ground height and substrate |
| `systems/evidence/evidence_system.gd` | `EvidenceSystem` | Registry, ageing, case strength |
| `systems/identification/identification_system.gd` | `IdentificationSystem` | Ranking, evidence standards, verdicts |
| `systems/investigation/investigation_system.gd` | `InvestigationSystem` | Objectives, filing reports |
| `systems/notebook/field_notebook.gd` | `FieldNotebook` | The player's record |

Non-autoload gameplay classes: `AnimalBrain`, `AnimalController`,
`AnimalSpawner`, `TrackEmitter`, `TrackExaminer`, `FieldCamera`, `Substrate`.

---

## Four seams that make replacement cheap

**1. Art → `SpeciesData.visual_scene`.**
One `PackedScene` field. If it is null the game builds a primitive stand-in from
`placeholder_color`, `body_length_m` and `shoulder_height_m`. Dropping in a
rigged model is a one-line change to a JSON file. `PlaceholderFactory` is
imported by presentation only.

**2. Terrain → the EnvironmentSystem provider interface.**
Anything that implements

```gdscript
func height_at(x: float, z: float) -> float
func substrate_at(pos: Vector3) -> Substrate
func world_extent() -> float
```

can be the world. Today it is a procedural mesh (`PrototypeValley`). Tomorrow it
can be a sculpted heightmap or a streaming terrain plugin. Gameplay never
notices, because gameplay only ever asked those three questions.

**3. Animals → brain / body / view.**
`AnimalBrain` is a `RefCounted` with no engine dependencies; it takes a
dictionary describing the world and returns an intention. `AnimalController` is
a thin body that carries out the intention. The view is a child node built from
species data. You can unit-test behaviour, change the renderer, or drive the
same brain from a future population simulation.

**4. UI → EventBus listeners.**
`HUD`, `ExaminePanel` and `NotebookUI` hold no state. They read systems on open
and re-read on `notebook_updated`. Replace them wholesale without touching a
gameplay file.

---

## Evidence, in three pieces

Understanding this is understanding the game.

**Truth vs observation.** `EvidenceRecord` stores `truth` (what really made it,
what it really measured) and `observed` (what the player managed to read).
`source_species_id` is ground truth and must never be shown. Misidentification
is possible precisely because these are different fields.

**Condition and decay.** Sign is created with a `condition` from the ground it
was made on (`Substrate.retention`), the animal's own feet
(`TrackProfile.clarity_bias` — a lynx's furred foot blurs its own print), and
the weather. It then decays on a half-life scaled by substrate persistence.
Trails genuinely go cold.

**Case strength vs fit.** Two separate questions, deliberately kept apart:

- *Fit* — `IdentificationSystem.rank()` — how well does the evidence match each
  species, weighted by how likely that species is to be here at all.
- *Standard* — `SpeciesData.evidence_standard` — how much evidence a claim of
  this species requires before the game will call it confirmed.

Repeats of one evidence type give sharply diminishing returns
(`EvidenceSystem.case_strength`). Twenty tracks are not twenty proofs. Breadth
of independent evidence is what builds a case.

---

## Provenance is load-bearing

`ContentProvenance.Kind` is `REAL`, `HISTORICAL` or `SPECULATIVE`. Species and
investigations both carry one, and the UI is required to display it. Fictional
discoveries are labelled as fictional in the verdict text itself, not just in a
menu. This is not decoration — it is why the game can run speculative
rediscovery scenarios without polluting real conservation information.

---

## Adding things

**A species** — one JSON file in `data/species/`. No code.

**An investigation** — one JSON file in `data/investigations/`. No code, unless
it needs a genuinely new kind of objective, which is one enum entry and one
branch in `InvestigationSystem._is_satisfied`.

**A map** — a new provider implementing the three-method interface, plus a
composition root scene like `scenes/main.gd` that says which animals live there.

**An evidence type** — an entry in `EvidenceKind.Type` plus its reliability and
half-life. Whatever produces it emits it; everything downstream already works.

---

## Not built yet (and where each will attach)

| System | Where it plugs in |
|---|---|
| Save / load | Each system gains `save_state()` / `load_state()`; a `SaveSystem` autoload walks them |
| Weather | Drives `EnvironmentSystem.ground_condition` and `Substrate`; `AnimalBrain` reads it from `ctx` |
| Populations / ecosystem | Owns `AnimalSpawner` and decides who exists; brains are unchanged |
| Trail cameras | An `EvidenceKind.TRAIL_CAM` producer that runs while the player is elsewhere |
| Audio | An EventBus listener. It should need zero changes elsewhere |
| Dialogue | A system emitting objectives and briefings into `InvestigationSystem` |
| Equipment / inventory | `FieldCamera` is the template: pure logic, presentation calls it |
