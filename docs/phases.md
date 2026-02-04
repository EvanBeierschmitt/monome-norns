# Phases

Phase goals and done criteria for development handoffs. Use one agent per phase; at phase end, confirm the checklist before starting the next.

## Part A (done)

- **Spec cleanup:** spec.md has TOC and consistent headings (Introduction, Concepts, Norns controls, Main menu, Preset Sequencer, Presets list, Preset Editor, Settings). No change to technical meaning.

---

## Phase 1 — Data model, Preset Editor, basic Crow (done)

**Goals:** Create/edit presets with segments (shape, level, time, jump); play one preset on one line with contours on Crow; no sequencer, no conditionals, no Ping.

**Done criteria:**

- [x] lib/segment.lua: default(), validate(), shapes(), level_modes(), clamp_level.
- [x] lib/preset.lua: new(), validate(), max_segments(); preset = up to 8 segments.
- [x] lib/state.lua: screens (main_menu, presets_list, preset_editor, preset_sequencer, settings); main menu E1/K3; presets list E2/K3; preset editor E1/E2/E3 (Time, Level mode, Level, Shape, Jump); K1 system-reserved on norns.
- [x] lib/crow_io.lua: output_volts(), start_segment(), play_preset() with jumps; no clock sync (time in seconds).
- [x] lib/ui.lua: draw per screen (main menu, presets list, preset editor, settings, preset sequencer placeholder).
- [x] lib/app.lua: params (line_count, voltage_range, ext_clock, run, quantize); enc/key delegation; K3 long-press delete preset with confirm; single-line play from Preset Editor (K3).
- [x] lines.lua: script name Lines.

---

## Phase 2 — Preset Sequencer and Ping (done)

**Goals:** Per-line sequence of up to 8 presets; Edit/Copy/Paste/Delete/Add via E2/E3/K3; play/stop/restart; Ping to change another line's preset from a segment.

**Done criteria:**

- [x] lib/sequencer.lua: new(), max_slots(), cursor_info(), insert_preset(), delete_preset(), set_preset(), PING_*.
- [x] state.sequences per line; preset_sequencer_cursor, preset_sequencer_action_index, sequencer_running.
- [x] Preset Sequencer screen: E1 line, E2 cursor (between vs on preset), E3 action; K3 execute (Edit, Copy, Paste, Delete, Add); play/stop at end of sequence.
- [x] Segment: ping_line, ping_action; crow_io.play_preset(..., on_ping); app sequencer_ping() to inc/dec/reset target line slot and restart.
- [x] App: handle_sequencer_k3(), sequencer_start(), sequencer_line_done(), sequencer_stop(); return from Presets list to add preset to sequencer (sequencer_add_preset).

---

## Phase 3 — Conditionals and polish (done)

**Goals:** Two conditional jump slots per segment (assignable to Jump or Ping); evaluate at segment end; polish (preset name, docs).

**Done criteria:**

- [x] lib/conditionals.lua: comparisons(), input_sources(), evaluate(condition, inputs).
- [x] Segment: cond1, cond2 (assign_to, input, comparison, value; optional jump/ping target fields); default_condition(), validate cond1/cond2.
- [x] crow_io.play_preset(..., get_inputs): at segment end evaluate cond1/cond2; if met, use conditional's jump or ping instead of default.
- [x] README, docs/architecture.md, CHANGELOG updated; docs/phases.md (this file) with phase goals and checklists.

**Optional polish (later):** Main menu icons; Preset Sequencer contour thumbnails; Preset Editor crosshatch/grey-out for conditionals (K1 system-reserved; use params or other key); preset name bottom-right when preset selected; Crow CV input wiring for get_inputs (cv1/cv2, line voltages).
