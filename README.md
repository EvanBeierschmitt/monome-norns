# Lines

A norns script for Crow: sequencable function generators that drive CV contours with segments, presets, a preset sequencer, conditionals, and Ping (internal line-to-line triggers). Inspired by the Rossum Electro Control Forge.

## Layout

**Runtime (norns):** everything needed to run the script lives in **lines/**.

- **lines/lines.lua** — Single entry point (norns expects &lt;foldername&gt;.lua); wires modules, init/enc/key/redraw/cleanup.
- **lines/lib/** — Reusable Lua modules: app, state, ui, segment, preset, sequencer, crow_io, conditionals.
- **lines/data/** — Presets, fixtures, example state (e.g. `.pset` files).

**Development (repo root only, not deployed):** coding and docs stay outside **lines/**.

- **docs/** — Human documentation (architecture, phases, spec).
- **test/** — Pure Lua unit tests; mock norns globals when needed.
- **scripts/** — Sync script to push **lines/** to norns.
- **.cursor/rules/** — Editor rules (`.mdc`); for coding, not for running the script.
- **spec.md**, **README.md**, **CHANGELOG.md** — Spec and project docs.

## Running on norns

Copy the **lines/** folder to **~/dust/code/lines/** on your norns (folder name **lines**; entry file **lines.lua**). Run from SELECT > lines > K3. Requires norns `include()`, Crow (for CV), and standard callbacks (`init`, `enc`, `key`, `redraw`, `cleanup`).

**Deploy and live QA:** Use the sync script and optional warmreload mod so code changes are reflected immediately. See [Deploy](docs/deploy.md).

## Running tests (desktop Lua)

From the repo root:

```bash
lua test/run.lua
```

(or `lua5.4 test/run.lua` / `lua5.3 test/run.lua` if `lua` is not in PATH). Tests target logic in `lib/` (segment, preset, state) and mock norns `include()` where required.

## Docs

- [Architecture](docs/architecture.md) — Module roles and data flow.
- [Deploy](docs/deploy.md) — Load script onto norns and live-sync for QA (sync script, warmreload).
- [UI](docs/ui.md) — Page list, encoder/key mapping, confirm flows, coarse/fine (070).
- [Phases](docs/phases.md) — Phase goals and done criteria for development handoffs.
- [Spec](spec.md) — Concepts, main menu, Preset Sequencer, Presets list, Preset Editor, Settings.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
