# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- **K1 system-reserved:** On norns, K1 always opens the system menu and is never delivered to the script. Lines uses K2/K3 only; delete preset via **PARAMETERS** (lines → Delete preset → yes). Coarse step in Preset Editor via params only. All keys (K2, K3) are handled **immediately** on press (no long-press) so E1/E2/E3 and K2/K3 work as before in every screen.
- **UI (070):** Rossum-style 3-tier layout (status, content, footer); brightness hierarchy (hint 4, unselected 8, title 12, selected 15). Main menu: K3 enter, K2 back. K1 is system-reserved on norns (opens system menu); script uses K2/K3 only. Presets list: "+ Create New Preset" row, scroll 0..#presets, K3 long-press delete; footer n/total. Preset Sequencer: title "Preset Sequencer" only; preset name right-aligned in footer. Preset Editor and Settings: two-column label left, value right-aligned. Coarse step in Preset Editor via params (K1+E3 not available). docs/ui.md added; spec and README updated.

## [0.2.0] - 2025-02-03

- **Lines** script implemented per spec (spec.md).
- **Part A:** Spec reorganized with TOC and headings (Introduction, Concepts, Norns controls, Main menu, Preset Sequencer, Presets list, Preset Editor, Settings).
- **Phase 1:** Data model (segment, preset), Preset Editor (E1 segment, E2 param, E3 value), basic Crow output (play_preset with jumps), main menu and navigation, Settings (lines, voltage range, Ext Clock/Run/Quantize stubbed), Presets list (add, edit, delete with K3 long-press confirm). K1 system-reserved; K3 long-press for delete.
- **Phase 2:** Preset Sequencer per line (up to 8 presets), E1 line / E2 cursor / E3 action, K3 Edit/Copy/Paste/Delete/Add; play/stop/restart at end of sequence; Ping (segment ping_line/ping_action) to increment/decrement/reset another line's preset slot; crow_io.play_preset on_ping callback; sequencer start/stop and line_done/ping in app.
- **Phase 3:** Conditionals (lib/conditionals.lua); segment cond1/cond2 (assign_to jump/ping, input, comparison, value); crow_io evaluates conditionals at segment end and overrides jump/ping when met; README, docs/architecture.md, CHANGELOG updated; docs/phases.md added.

## [0.1.0] - 2025-02-03

- Initial repo skeleton: lines.lua (single entry), lib/, docs/, data/, test/, README, CHANGELOG.
- Skeleton aligned with repo rules (000–060).
- Entry script wires `lib/app`; logic in `lib/state`, `lib/ui`.
- Pure Lua tests in `test/` for state logic.
