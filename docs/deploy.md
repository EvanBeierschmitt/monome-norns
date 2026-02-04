# Deploying Lines to norns

Get the script onto your norns device and have code changes reflected quickly for QA.

## One-time setup

### 1. Connect norns to your computer

- **WiFi:** Connect norns to the same WiFi as your Mac/PC. The device is usually reachable at **norns.local** (or use its IP from norns WiFi menu).
- **SSH/SFTP:** User **we**, default password **sleep** (change if you’ve set one).
- **File access:** Use Samba (File Share), SFTP, or the sync script below.

### 2. Copy the script to norns

Scripts live in **~/dust/code/** on norns. The folder name is the script name; the main file must be **&lt;foldername&gt;.lua**.

- **Option A — Sync script (recommended):** From the repo root, run:
  ```bash
  ./scripts/sync-to-norns.sh
  ```
  This copies the repo into **~/dust/code/lines/** on norns (see [Sync script](#sync-script) below).

- **Option B — Manual copy:** Copy the **lines/** folder (including **lines.lua**, **lib/**, **data/**) to **~/dust/code/lines/** on norns via Samba, SFTP, or USB. The file **lines.lua** is the entry point norns looks for when you select "lines" in the menu.

### 3. Run the script on norns

On the device: **SELECT** (E1) → choose **lines** → **K3** to run. The script name in the menu comes from the **scriptname** comment in **lines.lua**.

**Using Lines (params-based):** On norns, **K1 is system-reserved** and always opens the system menu; the script never receives K1. Lines is built to work via **PARAMETERS** when enc/keys don’t reach the script. After starting (SELECT → lines → K3), press **K1** → **E1** to PARAMETERS → **K3** (open). Under the **lines** section use **Menu** (E3: 1–4), **Enter menu** (E3 to yes), **Back** (E3 to yes), and **Delete preset** (E3 to yes to delete the selected preset on the Presets list). **K2** leaves PARAMETERS and returns to the script screen; the script reads params on each redraw. If enc/keys do reach the script, E1/K2/K3 work as usual (K3 enter/edit, K2 back).
---

## Immediate reflection of code changes (live QA)

To avoid copying by hand every time, use one of these:

### Option 1: warmreload mod (recommended)

[warmreload](https://github.com/schollz/warmreload) is a norns mod that reloads the current script whenever a file under **dust/code** changes.

1. **Install the mod:** In Maiden (browser: **http://norns.local**), open the REPL and run:
   ```text
   ;install https://github.com/schollz/warmreload
   ```
2. **Enable it:** On norns, go to **SYSTEM > MODS**, select **warmreload**, turn **E2** until you see **+**, then restart norns.
3. **Use it:** Run **lines** from SELECT. Then:
   - **Edit on norns:** Edit files in Maiden and save → script reloads automatically.
   - **Edit on your Mac/PC:** Run the sync script (or rsync) to push changes to norns → warmreload sees the updated files and reloads the script.

So: sync from your repo (e.g. `./scripts/sync-to-norns.sh`) whenever you save; if warmreload is enabled and Lines is the active script, it will reload and you see changes immediately.

### Option 2: Sync script only (no mod)

1. Run the sync script whenever you want to push changes:
   ```bash
   ./scripts/sync-to-norns.sh
   ```
2. On norns, **re-run the script:** SELECT → **lines** → K3 (or leave and re-enter the script). Changes are applied after you reload.

### Option 3: Watch and sync (live sync without warmreload)

From the repo root, sync whenever a file changes (requires **fswatch** on macOS, or **inotifywait** on Linux):

```bash
# macOS (install fswatch: brew install fswatch)
fswatch -o . | xargs -n1 -I{} ./scripts/sync-to-norns.sh

# After each sync, re-select the script on norns (SELECT > lines > K3)
```

Combine with **warmreload** so you don’t have to re-select: sync on save + warmreload = automatic reload.

---

## Sync script

The repo includes **scripts/sync-to-norns.sh** (see below). It:

- rsyncs the repo to **we@norns.local:~/dust/code/lines/**
- Excludes **.git**, **test/**, **.cursor**, **\*.pdf**, and other non-runtime files

**Usage:** From repo root, with norns on WiFi and reachable as **norns.local**:

```bash
chmod +x scripts/sync-to-norns.sh
./scripts/sync-to-norns.sh
```

To use a different host or user, set **NORNS_HOST** and **NORNS_USER**:

```bash
NORNS_HOST=192.168.1.100 NORNS_USER=we ./scripts/sync-to-norns.sh
```

---

## Troubleshooting

- **Use "Lines" (the folder), not "Lines/Main":** Run **SELECT > Lines > K3**. If you see both "Lines" and "Lines/Main", the correct script is **Lines** (the top-level entry). "Lines/Main" is a nested script and is not this app; it may show a black screen.
- **"Lines" shows an error:** The script now shows the first part of the error on screen and "See Maiden for full msg". Open **Maiden** (http://norns.local) to see the full stack trace. Fix the cause (e.g. sync again so **lib/** is complete, or connect Crow if required) and re-run.
- **Script not in SELECT menu:** Ensure the folder on norns is **~/dust/code/lines/** and it contains **lines.lua** and **lib/**. Norns lists folders under **dust/code/**; the main file must be **lines.lua** for the "lines" folder.
- **Stuck on main menu (E1/K2/K3 do nothing):** Try **K1** once (opens system menu), then **K2** (closes system menu and returns to script). On some norns setups, input stays on the system layer until you do this; after K2, E1 and K3 may start working. If they still don't: the script cannot force norns to deliver enc/key. Use **Maiden from a computer** (see below).
- **E1/K2/K3 don't work (arrow doesn't move, K3 doesn't select):** See **If enc/key don't work** below.
- **If enc/key don't work:** The script re-registers enc/key on every redraw. On the main menu, a debug line shows **"input ok"** when enc/key were received recently, or **"No input: open norns.local"** when none for 5+ seconds. If you see "input ok" when you turn E1 or press K2/K3, the script is receiving input; if you always see "No input", norns is not delivering enc/key (try **K1 then K2** above; firmware; or disable mods). **Maiden REPL (recommended when keys don't work):** On a computer, open **http://norns.local** (or your norns IP). In Maiden, open the **REPL**. Run these to navigate without hardware: `params:set("lines_menu_sel", 1)` (1=Preset Sequencer, 2=Presets, 3=Preset Editor, 4=Settings), then `params:set("lines_menu_enter", 2)` to enter that menu; `params:set("lines_back", 2)` to go back. The script reads params on each redraw, so the screen updates within a second. To use **PARAMETERS** on the device: press **K1** → **E1** to PARAMETERS → **K3**; under **lines** set Menu, Enter menu, Back. If PARAMETERS is greyed out, that is a norns/system issue.
- **Black screen:** The script now draws "Lines" at the start of every redraw and wraps app redraw in error handling. If you still see black: (1) **Minimal test** — On norns, in `~/dust/code/lines/`, temporarily replace `lines.lua` with the contents of `lines/test_screen.lua` (it only draws "hello"). Run SELECT > Lines > K3. If you see **hello**, the screen works and the issue is in the app; if still black, the issue is norns/setup (folder, device, or screen). Restore `lines.lua` from the repo after testing. (2) **Maiden** — Open http://norns.local and check the REPL for any errors when you run Lines.
- **"MISSING INCLUDE" or script errors:** Sync again so **lib/** and all Lua files are present. Check Maiden (norns.local) for the error message.
- **norns.local not found:** Use the norns IP (shown in the device WiFi menu) and set **NORNS_HOST** when running the sync script.
- **Permission denied:** SSH user is **we**; if you changed the password, use ssh keys or update the script to use them.
