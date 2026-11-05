# EveUI end-to-end test

A repeatable manual run of the whole UI in the live game. Do each step for
real, then take a screenshot and run `/eve check` (the debug snapshot) before
moving on. Fix what you find, `/reload`, and run the step again.

Never restart the client; `/reload` after code changes.

## How to check a step

- `/eve check` prints one line: errors logged by EveUI, blocked protected
  calls (taint), Lua errors from any code, and whether you are in combat. It
  also lists visible Blizzard windows that are still unskinned.
- Blocked calls also print as they happen (`EveUI blocked: ...`). For the
  cause, `/console taintLog 1`, `/reload`, repeat the step, `/reload` again
  and read `_forever_/Logs/taint.log` (written on reload). Set it back to 0.
- `/eve debug` + `/reload` writes a frame/texture snapshot to
  `WTF/Account/<id>/SavedVariables/EveUI.lua` (`EveUIDB.debug`).
- Screenshot after each step and look for misalignment, overlap, default
  Blizzard art (gold borders, parchment, red buttons) and clipped text.

## Checklist

Results of the latest run are in the last section.

1. Load: `/reload`, `/eve check` is clean, nothing default on screen.
2. Move: walk, back up, strafe, jump. HUD speed readout changes.
3. Target: click a unit, Overview row, Tab. Lock ring, target-of-target.
4. Focus: `/focus`, focus frame shows; `/clearfocus`.
5. Fight: cast at a mob. Cast ring fills and flashes; lock ring and
   nameplate update; combat text for damage dealt.
   Direction: a cast (Wrath, Healing Touch, opening a chest, using a quest
   item) fills the ring, the target ring and the nameplate bar from empty to
   full; a channel drains. `/eve check` prints `casts: N rings, 0 reversed;
   N plates, 0 reversed`. Samples are in `EveUIDB.castTrace` and
   `EveUIDB.plateTrace` after a `/reload`.
6. Take damage: hull/health arc drops, incoming combat text, low-health
   vignette.
7. Interrupt: start a cast and move. Ring blinks red with the reason.
8. Kill and loot: XP bar moves, loot window (Shift+right-click with
   auto-loot on), loot toast.
9. Heal: self-cast, cast ring and health arc.
10. Windows by keybind: open and close each (C, P, N, K, L, M, B, O, J,
    Shift+P, Shift+J, Y, I, Esc). Each one skinned and clear of the Neocom.
11. Windows by Neocom: click every Neocom icon, then close. Also in combat.
12. Game menu entries: Options, AddOns, Macros, Edit Mode (open/close only).
13. Tooltips: Neocom icon, action button, unit in the world, bag item,
    buff, minimap button, Overview row.
14. Drag: `/eve unlock`, drag the HUD and target lock, `/eve lock`;
    `/eve reset`. Drag a bag item and a spell to the action bar and back.
15. Chat: Enter, type, Esc; scroll; switch tabs.
16. `/eve` commands: `test`, `cast` (all four), `preview` (mirror, alert,
    boss, error, warning, zone, plate), `show`, `plates`, `cvars`, `scale`.
17. Final `/eve check` and a taint log read.
18. Settings: `/eveui` (and `/eve`, and the Neocom gear) opens the window;
    Esc and × close it. Unlock: every element shows a labelled cyan outline
    (HUD, both racks, experience, cast bar, combat text, locked target,
    focus, target's target, drone, Overview, Fleet, Hostiles, Location,
    buffs, quest tracker, chat, Neocom). Drag each one; drag the chat corner
    grip to resize; drag the Neocom to the right edge and back. Lock hides
    the outlines. `/reload`: everything stays put. Reset Layout restores the
    defaults. Unlock in combat is refused; entering combat while unlocked
    locks it. Scale and opacity sliders apply; module toggles show Reload UI.
    `/eve check` shows 0 blocked after a fight that follows a layout change.
19. Blizzard art sweep: `/eve check` prints `blizzard art: N textures in
    <frames>`; `/eve art` lists the first 15 (frame path, atlas or file,
    size). The full list is `EveUIDB.artScan` after a `/reload` (also taken
    automatically 8 s after login). Theme each frame it names, then repeat
    until it is empty or only lists art that should stay. Right side first:
    tracker headers, All Objectives and Quests bars, collapse buttons, POI
    icons, item buttons, progress and timer bars, scenario and bonus
    blocks, minimap buttons, buffs, zone text.

## Results

### Run 1 (2026-11-05, stopped early)

The client closed at 03:56:40, about 13 s after a `/reload`. Just before that
an exit countdown ("20 Seconds until exit") appeared. The likeliest cause is
the game menu left open by an Esc press, then Enter/keys reaching its Exit
Game button. Before typing chat commands, make sure no menu is open.

| Step | Result | Notes |
|---|---|---|
| 1 Load | pass | `/eve check` clean: 0 errors, 0 blocked, 0 Lua errors |
| Fonts | partial | All named font objects and chat use ARIALN (`fonts: 0 not swapped`). Names above heads and world damage/XP numbers still use the old face: the client reads `UNIT_NAME_FONT`/`DAMAGE_TEXT_FONT` only at startup, so they change on the next client start |
| 2 Move | pass | Speed readout 4.5 yd/s back, 7.1 yd/s forward, speed arc follows |
| 3 Target | pass | Tab and Overview targeting, lock ring, target-of-target |
| 4 Focus | pass | Focus frame appears and clears |
| 5 Fight | pass | Cast ring, success flash, lock ring, nameplate, damage text |
| 6 Take damage | pass | Health arc and readout drop |
| 7 Interrupt | pass, fixed | Ring blinks red with INTERRUPTED. Fixed: square red interrupt/cast animation on round action buttons |
| 8 Kill and loot | partial | XP gained, auto-loot worked; loot window not seen |
| Buffs | fixed | Buff duration text and expand arrow were Blizzard gold |
| Reputation | fixed | "Move to Inactive" and other gold window labels now white |
| Add-friend dialog | fixed, unverified | Gold border and red Okay button; new dialog skin not yet seen in game |
| 9-17 | not run | |

### Run 2 (2026-11-05, player-driven)

The user is playing, so from here the user runs `/reload` and reports back;
nothing is typed or clicked in the game by the agent.

| Step | Result | Notes |
|---|---|---|
| 5 Cast direction | fixed, unverified | Reported: casts and timed casts (quest-item pickup, looting) ran in reverse on the ring, the slim bar, the target ring and nameplates. The ring now uses plain start/end times, then the game's duration object, then secret step curves; timer bars get an explicit direction (elapsed for casts, remaining for channels); nameplate bars have reverse fill and count-down timers undone for normal casts. Each cast is traced and `/eve check` reports reversed ones |
| 18 Settings and layout | new, unverified | `/eveui` settings window, unlock/lock outlines, per-character positions (`EveUIDB.chars`), chat move and resize, Neocom edge snap, reset, scale, opacity, module toggles |
| Chat font | changed, unverified | Barlow Semi Condensed Medium (SIL OFL, `EveUI/media`) everywhere, chat without outline and with a light shadow, capitalised tabs with an accent underline, edit box with focus border. Falls back to Arial Narrow if the client can't see the new file before a restart (`/eve check` prints the face) |
| 19 Blizzard art | changed, unverified | Tracker: gold titles to white (hover cyan), POI rings steel, flat –/+ collapse glyphs, item buttons framed, progress/timer bars flat with hairline box, scenario stage block on an EVE panel, decorative tracker art hidden. Minimap tracking, mail and addon icons steel. Zone text and Location title use cyan/white/red instead of green/gold, with a cyan hairline under the zone banner. HUD widgets, toasts, talking head, loss of control, group loot and every other visible top-level Blizzard frame get a decorative-art sweep. New art scan in `/eve check`, `/eve art` and `EveUIDB.artScan` |

### Run 3 (2026-11-05, player-driven)

| Step | Result | Notes |
|---|---|---|
| 5 Cast direction | pass | `EveUIDB.castTrace`: every Wrath fills forward, 0 reversed |
| Screen sweep error | fixed, unverified | `IsVisible` was called on forbidden frames before the `IsForbidden` check (Skins.lua ScreenPass) |
| `GetAtlasInfo` Lua error | open | Thrown outside EveUI with no stack; the error hook now stores a stack so the next reload shows the caller |
| Unit frame colours | changed, unverified | Health red (`C.health`) on the HUD hull arc, lock/focus/ToT/pet arcs and Fleet bars; mana blue (`C.mana`) everywhere `ns.PowerColor` is used |
| 2.5D look | changed, unverified | Arcs: drop shadow, recessed groove, shaded lit bar, additive glow and specular edge (`Arc.lua`). HUD and lock rings: raised glass orbs (`ns.Orb`) with a lens over portraits (`ns.Lens`). Status bars: glass tubes (`ns.Bar3D`, `ns.SetBarColor`) |
| Arc clean-up | changed, unverified | Screenshot: per-segment shadow, glow and specular dash read as noisy bricks, and the target's hp/power glows merged. Arcs are back to groove + lit bar with a subtle shade; depth comes from plates (HUD orbs, new dial plate under lock rings). One capacitor ring instead of two. Lock power arc hidden when the unit has no power |
| ExtraActionButton1:SetSize blocked | fixed, unverified | Extra/zone button skin ran on OnShow in combat; now waits for PLAYER_REGEN_ENABLED |
| Health/mana gauges static | fixed, unverified | User: the ring cubes did not drop with health or mana. Arcs now use plain UnitHealth/UnitPower fractions whenever they are not secret and fall back to step curves only for secrets. `EveUIDB.arcTrace` and `/eve check` (`gauge player health: plain N, curve N, last x, mid curve y`) show which path ran and what the curve returned |

## Autopilot (Pilot.lua + pilot service)

New files (`Guide.lua`, `Pilot.lua`) need one full client restart; after that `/reload` is enough.

- In game: autopilot panel above the HUD (arrow, step, quest, distance, ETA, `<` `>` skip), a chevron on
  the HUD rim (top = straight ahead) with yards, a minimap diamond (edge chevron when off the map) and
  numbered pins for the next 6 steps on the world map. `/eve pilot` shows status; `next | back | auto |
  ai | off | goal <text>`.
- Without an AI guide it points at the nearest quest position the game knows (objective or turn-in).
- Flow: `/reload` writes `EveUIDB.pilotState` -> `eveui-pilot` (systemd user service, port 7450)
  notices the change, plans with Claude (Agent SDK, this machine's Claude Code login, web tools only)
  when the quest set changed, writes `EveUI/Guide.lua` -> next `/reload` loads the route.
- Second screen: http://<pilot-host>:7450/ (ask questions, see and replan the route). API: `GET
  /health /state /guide`, `POST /plan {goal}`, `POST /ask {question}`.
- Verified outside the game: test plan from a sample Teldrassil state (10 steps, valid Lua), `/ask`
  answers in ~14 s. Not yet verified in game: arrow direction, minimap scale, world map pins.

### Run 4 (2026-11-05)

| Step | Result | Notes |
|---|---|---|
| Health/mana cubes | fixed, unverified | `arcTrace`: player power was secret on every update (973 of 973), so the plain-number fallback never ran and the step-curve/alpha path never changed the cubes. Health and power arcs (`bars = true`) now use one tiny StatusBar per cube fed `UnitHealthPercent(unit, true, ScaleTo100)` (the same call as the working % text) or the power equivalent; each bar has a 0.01-wide range at its threshold, so the game fills or empties it. Fleet and Hostiles bars now use the same 0-100 values. `/eve check` prints `gauge player health: N updates, N secret[, error]` |
| `GetAtlasInfo` error | Blizzard | Stack is entirely Blizzard code (MinimalScrollBar open animation in ScrollingFlatPanel); EveUI never changes that art |
| Autopilot | working | Service planned a 21-step route from the real game state at 18:03 |
| Traditional unit frames | new, unverified | Default style now: player (portrait left) and target (portrait right) 260x62 frames above the racks, focus, target's target and pet; red health bar with "cur / max" and %, power bar with numbers, level, elite border, COMBAT/RESTING. Horizontal cast bars (icon, name, time, spark; amber cast, cyan channel, steel uninterruptible, green success, red interrupt): player cast in the gap between the racks, target and focus casts above their frames, target auras above that. `/eve style eve` (or Settings > EVE ring frames) brings back the ring HUD and lock frames. Code lives in Lock.lua so no client restart is needed |
