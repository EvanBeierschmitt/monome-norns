# Lines UI

Rossum-style 3-tier layout and encoder/key mapping (070). Screen is 128x64 grayscale.

## Page list

- **Main menu** — E1 select item, K3 enter, K2 back. (K1 is system-reserved on norns and opens system menu; script uses K2/K3 only.)
- **Preset Sequencer** — Per-line sequence of presets; E1 line, E2 slot, E3 action, K3 do; play/stop top-right; preset name footer right; K2 back.
- **Presets list** — "+ Create New Preset" + preset list; E2 scroll, K3 add/edit; delete via PARAMETERS (Delete preset → yes); K2 back.
- **Preset Editor** — Two-column: label left, value right-aligned; E1 segment, E2 param, E3 value; K2 back. Coarse step via params (K1+E3 not available; K1 is system-reserved).
- **Settings** — Two-column fields; E2 field, E3 value; K2 back.
- **Delete confirm** — Modal: "Delete preset?"; K3 confirm, K2 cancel.

## Encoder / key mapping (global)

- **E1** — Context / line / segment (main menu selection, sequencer line, editor segment).
- **E2** — Move selection (presets list row, sequencer slot, editor parameter, settings field).
- **E3** — Edit selected value or choose action (fine step). Coarse step in Preset Editor via params (K1 is system-reserved).
- **K1** — System-reserved on norns; always opens system menu. Script does not receive K1.
- **K2** — Back / cancel. Short press = back; from any sub-page returns to main menu. On delete confirm, K2 cancels.
- **K3** — Enter / commit / perform action. Main menu: K3 enters selected item. Presets list: K3 add or edit. Preset Sequencer: K3 execute action or play/stop. Delete confirm (if shown): K3 confirm or K2 cancel.

## Confirm flows

- **Delete preset:** Via PARAMETERS → **lines** → **Delete preset** set to **yes** (deletes the selected preset on Presets list immediately). Or use the "Delete preset?" modal (K3 confirm, K2 cancel) if that flow is triggered.

## Coarse / fine

- **Preset Editor:** E3 = fine (time ±1, level ±0.1). Coarse (time ±10, level ±0.5) via params; K1 is system-reserved so K1+E3 is not available.
