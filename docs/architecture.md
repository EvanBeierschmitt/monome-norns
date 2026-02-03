# Architecture

This document describes how the script is structured so agents and humans can extend it without breaking invariants.

## Layout (020)

- **Root** — Single entry script (`main.lua`). No entry scripts in `lib/`, `docs/`, `data/`, or `test/`.
- **lib/** — Reusable modules. Entry script wires them; it does not hold business logic.
- **docs/** — Human-facing documentation (this file, UI, presets, etc.).
- **data/** — Presets, fixtures, and example state (e.g. `.pset`).
- **test/** — Unit tests for logic; mock norns globals when needed.

## Module roles

- **lib/app.lua** — Orchestrator: creates state, UI, params; starts redraw metro; delegates `enc`/`key` to state and marks UI dirty.
- **lib/state.lua** — Application state and pure(ish) transitions (`on_enc`, `on_key`). No norns APIs; easy to unit test.
- **lib/ui.lua** — Screen drawing (128x64, grayscale). Reads from state; no allocations in hot path.

## Data flow

1. `init()` → `App.new()` → `app:init()` (params, UI, metro).
2. `enc(n, d)` / `key(n, z)` → `app:enc()` / `app:key()` → `State.on_enc()` / `State.on_key()` → state mutated, UI marked dirty.
3. Metro fires → `redraw()` → `app:redraw()` → `Ui:draw()` if dirty.
4. `cleanup()` → `app:cleanup()` → metro stopped.

## Invariants (040, 050)

- Tick/redraw loop: no blocking work; event order stable.
- State transitions: pure and testable where possible; persistence format versioned if changed.
- Add tests when changing sequencing, state, or persistence logic.
