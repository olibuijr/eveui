# EveUI

A complete World of Warcraft interface inspired by the ship UI of EVE Online: dark glass panels, thin
steel borders, cyan accents and a narrow technical typeface. It replaces the unit frames, cast bars,
action bars, minimap, chat, tooltips and most windows, and adds a quest autopilot that can plan your
route with Claude.

Built for the **WoW Forever** client (interface `16001`), including its hidden combat values ("secret
values").

## Features

**Unit frames** (two styles, switch with `/eve style`)

- **Traditional** (default): player, target, focus, target's target and pet frames with portrait,
  name, level and elite marker, a red health bar with current / max and percent, and a power bar with
  numbers (mana in blue). Target buffs and debuffs with timers and stack counts.
- **EVE rings**: a ship HUD for the player (red health arc, blue capacitor ring for power, speed
  gauge, shield readout) and round "locked target" frames for target, focus, target's target and pet.

**Cast bars**: icon, spell name, time left and a spark. Amber for casts, cyan for channels, grey when
the cast can't be interrupted, a green flash on success and a red INTERRUPTED blink. In the ring style
the cast fills a segmented ring like an EVE module cycle.

**Quest autopilot**

- An arrow panel with the current step, quest, distance and travel time, plus `<` / `>` to skip or go
  back.
- A pointer on the HUD rim (ring style), a pulsing marker on the minimap (an edge arrow when it is off
  the map) and numbered pins for the next six steps on the world map.
- Works on its own using the game's quest positions (nearest objective or turn-in). With the optional
  [pilot service](#ai-route-planning-optional) it follows an AI-planned route instead.

**Ship systems** (0.4)

- **Brackets**: nameplates become EVE brackets: shape by unit type, reaction colour, distance, a thin
  health line, lock-on corners on your target, a red ring when a unit is on you, fleet tags.
- **D-Scan and radar**: a round radar with range rings (group members exact, other units by distance
  and screen bearing) and a directional scanner with angle, range and an animated sweep.
- **Star map**: zones of the continent as star systems with jump lines, security colours from zone
  levels, you-are-here and the autopilot route. Pan, zoom, hover for quests, click to open the map.
- **Fitting**: gear on high, mid and low slot rings around your ship, stats as gauges.
- **Skill queue**: level as the skill in training (XP/h, time to level), professions as queued skills.
- **Wallet**: gold history graph (24h, 7d, all), session income and expenses by source, ISK display.
- **Killmails**: an EVE killmail after each kill or death, with involved parties and spells.
- **Missions**: quest dialogs as agent conversations with briefings, and a mission journal.
- **Fleet broadcasts**: target, need heals, need mana, in position, hold, align to, enemy spotted,
  travel and clear, sent between EveUI users in your group.
- **Voice alerts**: a ship-computer voice and banners for shields low, hull critical, capacitor,
  target destroyed, warp, docking, level up, mission complete and more (original Piper TTS clips).
- **Fleet comms and combat coach**: the pilot service reads the combat log live, shows graphs and
  breakdowns on the second screen and has Claude debrief each fight; the tips show in game after
  `/reload`.
- **Faction themes**: Caldari, Amarr, Gallente, Minmatar and Jove accents (Settings or `/eve theme`).

**The rest of the interface**

- **Module racks**: round action buttons in two racks either side of the screen centre, with
  cooldowns, range and proc highlights.
- **Overview**: nearby units, with distance and type, click to target.
- **Fleet**: party frames with range fade.
- **Damage meter**: damage, DPS, healing, HPS, absorbs, interrupts, dispels, damage taken, avoidable
  damage, deaths and enemy damage taken for the current fight, overall or any past fight. Click a row
  for its spell breakdown (right-click to go back), hover for the top spells, Shift+wheel to change
  mode, report to chat, reset. Right-click the panel to show it always, in combat or in a group. It
  reads the game's own tracking (`C_DamageMeter`) and hides Blizzard's meter window.
- **Location**: square minimap with coordinates, FPS and latency, durability, gold and clock.
- **Neocom**: a sidebar on the left or right edge with the game menus, bags, map and settings. It
  works in combat.
- **Combat text**, a quest tracker and buff display in the same style, plus nameplate cast bars.
- **Reskin**: tooltips, chat (tabs, edit box), character and other windows, popups, toasts, loot and
  alerts. Gold borders, parchment and red buttons are removed.
- **Layout**: `/eve unlock` outlines every element. Drag them, resize the chat, and snap the Neocom to
  either edge. Positions are saved per character.
- **Settings window**: UI scale, panel opacity and module toggles.

## Install

1. Download this repository (Code → Download ZIP) or clone it.
2. Copy the `EveUI` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Start the game (a full client start the first time, so the font and all files are found).

To develop, symlink the folder instead of copying it:

```sh
ln -s /path/to/eveui/EveUI "World of Warcraft/_forever_/Interface/AddOns/EveUI"
```

## Commands

| Command | What it does |
|---|---|
| `/eveui` or `/eve` | Open the settings window |
| `/eve unlock`, `/eve lock` | Show outlines and drag elements, then lock them |
| `/eve reset` | Reset the layout |
| `/eve scale 0.9` | UI scale (0.5 to 2) |
| `/eve style classic` / `eve` | Traditional frames or the EVE ring HUD (reloads) |
| `/eve pilot` | Autopilot status; also `next`, `back`, `auto`, `ai`, `off`, `goal <text>` |
| `/eve cast [channel\|locked\|interrupt]` | Preview the cast display |
| `/eve neocom`, `/eve blizz` | Toggle the Neocom, or hiding Blizzard's unit frames |
| `/eve check` | One-line health report: errors, blocked actions, gauge and cast traces |
| `/eve art` | List Blizzard art still visible, for theming work |
| `/eve meter`, `/eve km` | Toggle the damage meter, open killmails |
| `/eve starmap`, `/eve dscan` | Star map, D-Scan window |
| `/eve fitting`, `/eve skills`, `/eve wallet` | Ship screens |
| `/eve missions [agent\|replace]` | Mission journal; agent panel options |
| `/eve bc [kind]` | Fleet broadcast (target, shield, cap, position, hold, align, enemy, jump, clear) |
| `/eve voice [all\|on\|off\|mute\|<line>]` | Voice alert test and options |
| `/eve brackets`, `/eve comms` | Toggle brackets; fleet comms panel |
| `/eve theme <name>` | caldari, amarr, gallente, minmatar, jove (reloads) |

## AI route planning (optional)

WoW addons can't use the network or read files while you play. The only bridge is `/reload`: WoW then
saves the addon's data to disk and loads its files again. The pilot service uses that:

1. On `/reload` or logout EveUI saves your quest log, objectives, position, level and class.
2. The service in [`pilot/`](pilot/) notices the change and asks Claude for an efficient route (via
   the [Claude Agent SDK](https://docs.claude.com/en/api/agent-sdk/overview), with only web search and
   web fetch tools). It writes the route to `EveUI/Guide.lua`.
3. Your next `/reload` loads the route into the autopilot.

The service also serves a page for a phone or second monitor, where you can ask questions while you
play and replan with a goal ("finish Teldrassil, then Darkshore").

**Requirements**: Python 3.13+, [uv](https://docs.astral.sh/uv/), Lua 5.1 (`lua5.1`, to read the
saved data) and Claude access. If you are not the author, set `ANTHROPIC_API_KEY`. Anthropic's terms
don't let a published tool run on someone else's claude.ai login.

```sh
cd pilot
uv sync
EVEUI_WOW="/path/to/World of Warcraft/_forever_" uv run python pilot.py
```

| Variable | Default |
|---|---|
| `EVEUI_WOW` | `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_` |
| `EVEUI_ADDON` | `../EveUI` (where `Guide.lua` is written) |
| `EVEUI_PILOT_HOST`, `EVEUI_PILOT_PORT` | `0.0.0.0`, `7450` |
| `EVEUI_PILOT_MODEL` | Claude Code's default model |
| `EVEUI_COMBATLOG` | newest `Logs/WoWCombatLog*.txt` (file or folder) |
| `EVEUI_DEBRIEF_MIN`, `EVEUI_COMBAT_GAP` | 20 s fight minimum for a debrief, 5 s gap ends a fight |
| `EVEUI_BRIEFINGS` | `1`; `0` turns mission briefings off |

For the combat coach, type `/combatlog` in game once per session; the service follows the log file.

A systemd user unit is in [`pilot/eveui-pilot.service`](pilot/eveui-pilot.service). The service has no
password: run it on your home network only.

**API**: `GET /` (second-screen page), `GET /health`, `GET /state`, `GET /guide`,
`POST /plan {"goal": "..."}`, `POST /ask {"question": "..."}`.

The autopilot only shows information. It never moves your character, targets, casts or clicks for you,
which Blizzard's addon rules don't allow.

## How it handles hidden combat values

The WoW Forever client hides health, power and some cast numbers from addon code: they can be shown
but not compared or calculated with. EveUI shows them only through the game's own widgets:

- **Health and power** go to StatusBars as a 0-100 value from
  `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)`.
- **Ring gauges** use one tiny StatusBar per segment, each with a very narrow range at its threshold,
  so the game itself decides which segments are lit.
- **Cast bars** use start and end times when the game gives them, and otherwise the game's duration
  objects (`SetTimerDuration`).

Secure actions (targeting, menus, Neocom clicks) use secure templates. Anything that resizes protected
frames waits until combat ends.

## Project layout

```
EveUI/          the addon
  Core.lua        palette, drawing helpers (glass orbs, bars), layout, slash commands
  Arc.lua         segmented ring gauges
  Castbar.lua     EVE ring cast display
  HUD.lua         ship HUD (ring style)
  Lock.lua        unit frames: ring "locked targets" and traditional frames and cast bars
  ActionBars.lua  module racks
  DamageMeter.lua damage meter over C_DamageMeter
  Overview.lua, Party.lua, Location.lua, Neocom.lua, SCT.lua
  Skins.lua, Extras.lua  reskin of Blizzard windows, settings window
  Pilot.lua       quest autopilot
  Guide.lua       AI route, written by the pilot service
  Debug.lua       /eve check, traces and snapshots
pilot/          optional route-planning service (Python, Claude Agent SDK)
TESTING.md      in-game test checklist and results
```

## Debugging

- `/eve check` prints errors, blocked protected calls, Lua errors from any addon, and gauge and cast
  traces.
- Details are saved to `WTF/Account/<account>/SavedVariables/EveUI.lua` on `/reload`: `EveUIDB.errors`,
  `castTrace`, `arcTrace`, `artScan` and `pilotState`.
- For taint, use `/console taintLog 1`, `/reload`, reproduce, `/reload`, then read `Logs/taint.log`.

## Credits and license

- Code: [MIT](LICENSE) © Ólafur Búi Ólafsson.
- Font: [Barlow Semi Condensed](https://github.com/jpt/barlow) by The Barlow Project Authors, SIL Open Font License
  1.1 ([`EveUI/media/OFL.txt`](EveUI/media/OFL.txt)).

EveUI is a fan project. It is not affiliated with or endorsed by CCP Games (EVE Online) or Blizzard
Entertainment (World of Warcraft). Both names are trademarks of their owners.
