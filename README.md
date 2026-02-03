# monome-norns

A norns script skeleton that matches the repo rules so Cursor agents start in a **correct-by-default** environment.

## Layout

- **main.lua** — Entry point; wires modules, minimal logic.
- **lib/** — Reusable Lua modules (state, UI, app). Logic lives here.
- **docs/** — Human documentation (architecture, UI, presets).
- **data/** — Presets, fixtures, example state (e.g. `.pset` files).
- **test/** — Pure Lua unit tests; mock norns globals when needed.

## Running on norns

Copy this folder to `~/dust/code/<scriptname>/` and run from the SELECT menu. Requires norns `include()` and standard callbacks (`init`, `enc`, `key`, `redraw`, `cleanup`).

## Running tests (desktop Lua)

From the repo root:

```bash
lua test/run.lua
```

Tests target logic in `lib/` (e.g. state transitions) and mock norns where required.

## Docs

- [Architecture](docs/architecture.md) — Module roles and boundaries.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
