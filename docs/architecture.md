# Architecture

This document describes how Lines is structured so agents and humans can extend it without breaking invariants.

## Layout (020)

- **Root** — Single entry script (`lines.lua`). No entry scripts in `lib/`, `docs/`, `data/`, or `test/`.
- **lib/** — Reusable modules. Entry script wires them; it does not hold business logic.
- **docs/** — Human-facing documentation (this file, phases, spec).
- **data/** — Presets, fixtures, and example state (e.g. `.pset`).
- **test/** — Unit tests for logic; mock norns globals when needed.

## Module roles

- **lib/app.lua** — Orchestrator: state, UI, params, Crow; redraw metro; enc/key delegation; sequencer start/stop and Ping handling.
- **lib/state.lua** — Application state and screen navigation; pure(ish) transitions (`on_enc`, `on_key`). Uses segment, preset, sequencer; no norns/Crow APIs in transitions.
- **lib/ui.lua** — Screen drawing (128x64, grayscale). One draw path per screen (main menu, presets list, preset editor, preset sequencer, settings).
- **lib/segment.lua** — Segment data shape, defaults, validation (shape, level, time, jump, ping, cond1/cond2). No norns/Crow.
- **lib/preset.lua** — Preset = up to 8 segments; validation. No norns/Crow.
- **lib/sequencer.lua** — Per-line sequence of up to 8 presets; cursor; insert/delete/set; Ping action constants.
- **lib/crow_io.lua** — All Crow output/input: volts, slew, play_preset (segments + jumps + conditionals + on_ping). Conditionals evaluated via `lib/conditionals`.
- **lib/conditionals.lua** — Pure conditional evaluation (inputs table → boolean). Used by crow_io at segment end.

## Data flow

1. `init()` → `App.new()` → `app:init()` (params, state sync, UI, metro).
2. `enc(n, d)` / `key(n, z)` → `app:enc()` / `app:key()` → `State.on_enc()` / `State.on_key()` → state mutated, UI dirty; app handles sequencer actions, delete confirm, play/ping.
3. Metro fires → `redraw()` → `app:redraw()` → `Ui:draw()` if dirty.
4. Sequencer: CrowIo.play_preset() runs segments; at segment end, conditionals evaluated; on_preset_done advances line or stops; on_ping updates target line slot and restarts that preset.
5. `cleanup()` → `app:cleanup()` → sequencer stopped, Crow outputs zeroed, metro stopped.

## Invariants (040, 050)

- Tick/redraw loop: no blocking work; event order stable.
- State transitions: pure and testable where possible; persistence format versioned if changed.
- Jump/branch: explicit in segment (jump_to_segment, jump_to_preset_id) and conditionals (cond1/cond2 assign_to jump/ping).
- Add tests when changing sequencing, state, segment/preset validation, or conditional evaluation.
