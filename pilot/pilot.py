"""EveUI pilot: AI route planning for the EveUI autopilot.

Watches EveUI's SavedVariables (written by WoW on /reload or logout), asks
Claude (through the Claude Agent SDK and this machine's Claude Code login) for
an efficient quest route, and writes it to EveUI/Guide.lua, which the addon
loads on the next /reload. Also serves a small HTTP API and a second-screen
page for live questions.

Combat coach: tails the client's combat log (/combatlog in game), splits it into
fights for a live second-screen view, asks Claude for a short debrief after each
fight and writes the tips to EveUI/Comms.lua. Also renders EveUIDB.killmails and
writes EVE-style mission briefings for the quest log to EveUI/Briefings.lua.

Personal use only: it runs on the logged-in Claude Code account of this machine.
Claude only gets read-only web tools (WebSearch, WebFetch).
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import re
import subprocess
import time
from pathlib import Path

from aiohttp import web
from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query

import combatlog

HERE = Path(__file__).resolve().parent
WOW = Path(os.environ.get(
    "EVEUI_WOW",
    "~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_",
)).expanduser()
ADDON = Path(os.environ.get("EVEUI_ADDON", HERE.parent / "EveUI")).expanduser()
DATA = Path(os.environ.get("EVEUI_PILOT_DATA", HERE / "data")).expanduser()
HOST = os.environ.get("EVEUI_PILOT_HOST", "0.0.0.0")
PORT = int(os.environ.get("EVEUI_PILOT_PORT", "7450"))
MODEL = os.environ.get("EVEUI_PILOT_MODEL") or None
LUA = os.environ.get("EVEUI_LUA", "lua5.1")
# Combat log: a WoWCombatLog*.txt file or the directory holding them (Linux or C:\ path in Wine).
COMBATLOG = combatlog.wine_path(os.environ.get("EVEUI_COMBATLOG") or str(WOW / "Logs"))
COMBATLOG_REPLAY = os.environ.get("EVEUI_COMBATLOG_REPLAY") == "1"  # read files from the start
DEBRIEF_MIN_S = float(os.environ.get("EVEUI_DEBRIEF_MIN", "20"))
BRIEFINGS = os.environ.get("EVEUI_BRIEFINGS", "1") != "0"

log = logging.getLogger("eveui-pilot")

KINDS = ["accept", "turnin", "kill", "loot", "use", "talk", "goto", "fly", "hearth", "train", "vendor"]

PLAN_SCHEMA = {
    "type": "object",
    "required": ["summary", "steps"],
    "properties": {
        "summary": {"type": "string"},
        "steps": {
            "type": "array",
            "maxItems": 40,
            "items": {
                "type": "object",
                "required": ["kind", "text"],
                "properties": {
                    "kind": {"type": "string", "enum": KINDS},
                    "text": {"type": "string"},
                    "note": {"type": "string"},
                    "quest": {"type": "integer"},
                    "title": {"type": "string"},
                    "obj": {"type": "integer"},
                    "map": {"type": "integer"},
                    "x": {"type": "number"},
                    "y": {"type": "number"},
                    "radius": {"type": "number"},
                },
            },
        },
    },
}

PLAN_SYSTEM = """You plan quest routes for EveUI's autopilot in World of Warcraft (the "WoW Forever" client; \
judge the content era from the quests and zones you are given, it is usually classic-era levelling).

You get the player's state as JSON: level, class, race, faction, current map (uiMapID, name, x/y as 0-1 \
fractions), the zones of the continent (uiMapID + name), the quest log (id, title, level, complete, \
objectives with done flags) where `poi` is the game's own exact position for that quest's current \
objective or turn-in, and quests already turned in.

Return the most efficient ordered route for the next 45-60 minutes of play:
- Group objectives by area, collect nearby quests on the way, turn in before leaving an area, avoid \
backtracking, and skip quests well above the player's level unless they say they are grouped.
- Use `poi` coordinates when present: they are exact. For anything else (quest givers, turn-ins, mob \
areas) use coordinates you are sure of, or look them up (Wowhead classic pages give "x, y" in percent; \
divide by 100). If you are not sure, leave map/x/y out rather than guess.
- `map` must be a uiMapID from the state's zones list. x and y are 0-1 fractions of that map.
- kind: accept, turnin (quest id required), kill/loot/use/talk (quest id, and obj = 1-based index into \
that quest's objectives when the step is one objective), goto (a place), fly, hearth, train, vendor.
- For accept steps give the quest id if you know it and always the exact quest title in `title`.
- text: short imperative, at most 50 characters ("Kill Strigid Owls"). note: at most 90 characters \
(where or how). summary: one or two sentences on the plan.
- Never include quests the player already turned in. Only route advice: no automation, macros or bots.
Work fast: look things up only when needed, at most a few lookups."""

ASK_SYSTEM = """You answer a World of Warcraft player's questions while they play (the "WoW Forever" \
client; usually classic-era content). You get their current state as JSON (level, class, zone, \
position, quest log). Be concise: at most 120 words, concrete coordinates (x, y in percent) and \
directions when useful. Look things up on the web when you are not sure. Only gameplay advice: no \
automation, macros that play for them, or bots."""


DEBRIEF_SCHEMA = {
    "type": "object",
    "required": ["headline", "tips"],
    "properties": {
        "headline": {"type": "string"},
        "tips": {"type": "array", "minItems": 3, "maxItems": 5, "items": {"type": "string"}},
    },
}

DEBRIEF_SYSTEM = """You are a combat coach for a World of Warcraft player (the "WoW Forever" client, usually \
classic-era levelling). You get one finished fight from their combat log as JSON: duration, damage/healing per \
second (1 s buckets), damage by spell (hits, crits, casts), the cast sequence with times, damage taken by \
source, deaths with the last events before them, interrupts, enemy casts that went through, DoT/HoT uptime, \
idle time between casts, plus the player's class and level.

Give a short debrief: a headline (at most 70 characters) and 3-5 concrete tips. Every tip must cite numbers \
from this fight (uptime %, DPS, seconds idle, hits, damage taken) and say what to do differently next pull. \
Each tip at most 140 characters, plain text, no markdown. Use the player's real spells and their rank-appropriate \
rotation. Only gameplay advice: no macros that play for them, no automation."""

BRIEF_SCHEMA = {
    "type": "object",
    "required": ["briefings"],
    "properties": {
        "briefings": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["quest", "agent", "text", "objective", "tip"],
                "properties": {
                    "quest": {"type": "integer"},
                    "agent": {"type": "string"},
                    "text": {"type": "string"},
                    "objective": {"type": "string"},
                    "tip": {"type": "string"},
                },
            },
        },
    },
}

BRIEF_SYSTEM = """You write mission briefings for a World of Warcraft player whose UI is styled like EVE \
Online. For each quest you get (id, title, level, objectives), write the briefing an EVE Online mission agent \
would give: `agent` is the quest giver as "Name, Corporation" (use the real quest giver if you know it, with an \
EVE-style corporation name fitting their faction, e.g. "Tallonkai Swiftroot, Cenarion Circle Security"), \
`text` is 2-4 sentences in that agent's clipped EVE voice that still tells the real WoW story, `objective` is \
at most 60 characters, `tip` is one short practical gameplay tip (at most 100 characters). Return one entry \
per quest id given, nothing else."""


# SavedVariables -----------------------------------------------------------------

def sv_path() -> Path | None:
    files = sorted(WOW.glob("WTF/Account/*/SavedVariables/EveUI.lua"), key=lambda p: p.stat().st_mtime)
    return files[-1] if files else None


def load_sv(path: Path) -> dict:
    out = subprocess.run([LUA, str(HERE / "sv2json.lua"), str(path)], capture_output=True, text=True,
                         timeout=20, check=True)
    data = json.loads(out.stdout or "{}")
    return data if isinstance(data, dict) else {}  # an empty Lua table encodes as []


def signature(state: dict | None, goal: str | None = None) -> str:
    if not state:
        return ""
    quests = sorted(
        (q.get("id"), bool(q.get("complete")), tuple(bool(o.get("done")) for o in q.get("objectives") or []))
        for q in state.get("quests") or []
    )
    key = json.dumps([quests, (state.get("continent") or {}).get("id"), state.get("level"),
                      goal or state.get("goal")], default=str)
    return hashlib.sha1(key.encode()).hexdigest()[:16]


# Guide file -----------------------------------------------------------------------

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lua(v) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 5))
    if isinstance(v, str):
        s = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
        s = re.sub(r"[\x00-\x1f]", "", s)
        return f'"{s}"'
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if x is None:
                continue
            key = k if isinstance(k, str) and IDENT.match(k) else f"[{lua(k)}]"
            parts.append(f"{key} = {lua(x)}")
        return "{" + ", ".join(parts) + "}"
    return lua(str(v))


def write_atomic(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def write_guide(guide: dict) -> None:
    body = (
        "-- Written by the EveUI pilot service (~/Projects/wow-eveui/pilot). Do not edit\n"
        "-- by hand: the service replaces this file after each plan, and /reload loads it.\n"
        "EveUI_GUIDE_FILE = true\n"
        f"EveUI_GUIDE = {lua(guide)}\n"
    )
    write_atomic(ADDON / "Guide.lua", body)
    write_atomic(DATA / "guide.json", json.dumps(guide, indent=2))


def write_comms(fight: dict) -> None:
    deb = fight.get("debrief") or {}
    comms = {
        "generated": int(time.time()),
        "fight": str(fight.get("name") or "Unknown")[:60],
        "duration": int(round(fight.get("duration") or 0)),
        "dps": round(fight.get("dps") or 0, 1),
        "headline": str(deb.get("headline") or "")[:80],
        "tips": [str(t)[:160] for t in deb.get("tips") or []][:5],
    }
    body = (
        "-- Written by the EveUI pilot service (~/Projects/wow-eveui/pilot) after each fight.\n"
        "-- Do not edit by hand; /reload loads the latest combat debrief.\n"
        f"EveUIComms = {lua(comms)}\n"
    )
    write_atomic(ADDON / "Comms.lua", body)


def write_briefings(briefings: dict[int, dict]) -> None:
    body = (
        "-- Written by the EveUI pilot service (~/Projects/wow-eveui/pilot) when the quest log changes.\n"
        "-- Do not edit by hand; /reload loads the latest briefings.\n"
        f"EveUIBriefings = {lua(briefings)}\n"
    )
    write_atomic(ADDON / "Briefings.lua", body)


def clean_steps(steps: list, state: dict) -> list:
    zones = {z.get("id") for z in state.get("zones") or [] if z.get("id")}
    out = []
    for s in steps:
        kind = s.get("kind")
        if kind not in KINDS or not s.get("text"):
            continue
        step = {"kind": kind, "text": str(s["text"])[:60]}
        if s.get("note"):
            step["note"] = str(s["note"])[:100]
        for k in ("quest", "obj"):
            if isinstance(s.get(k), int) and s[k] > 0:
                step[k] = s[k]
        if s.get("title"):
            step["title"] = str(s["title"])[:80]
        x, y, m = s.get("x"), s.get("y"), s.get("map")
        if isinstance(x, (int, float)) and isinstance(y, (int, float)) and isinstance(m, int):
            if x > 1 or y > 1:
                x, y = x / 100, y / 100
            if 0 <= x <= 1 and 0 <= y <= 1 and (not zones or m in zones):
                step.update(map=m, x=round(x, 4), y=round(y, 4))
        if isinstance(s.get("radius"), (int, float)) and 3 <= s["radius"] <= 200:
            step["radius"] = s["radius"]
        out.append(step)
    return out


# Claude ---------------------------------------------------------------------------

def options(system: str, schema: dict | None, turns: int, web_tools: bool = True) -> ClaudeAgentOptions:
    tools = ["WebSearch", "WebFetch"] if web_tools else []
    kw: dict[str, object] = dict(
        system_prompt=system,
        tools=tools,
        allowed_tools=tools,
        setting_sources=[],
        max_turns=turns,
        cwd=str(DATA),
    )
    if MODEL:
        kw["model"] = MODEL
    if schema:
        kw["output_format"] = {"type": "json_schema", "schema": schema}
    return ClaudeAgentOptions(**kw)


async def run_claude(prompt: str, opts: ClaudeAgentOptions) -> ResultMessage:
    result = None
    async for msg in query(prompt=prompt, options=opts):
        if isinstance(msg, ResultMessage):
            result = msg
    if result is None:
        raise RuntimeError("no result from Claude")
    if result.is_error:
        raise RuntimeError(f"Claude error: {result.subtype} {result.errors or result.result}")
    return result


def parse_plan(result: ResultMessage) -> dict:
    if isinstance(result.structured_output, dict):
        return result.structured_output
    text = result.result or ""
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        raise RuntimeError("plan was not JSON")
    return json.loads(m.group(0))


def compact_state(state: dict) -> dict:
    s = dict(state)
    s.pop("money", None)
    return s


# Service ----------------------------------------------------------------------------

class Pilot:
    def __init__(self) -> None:
        self.state: dict | None = None
        self.guide: dict | None = None
        self.planning = False
        self.again = False
        self.last_error: str | None = None
        self.last_plan_s: float | None = None
        self.sv_mtime = 0.0
        self.lock = asyncio.Lock()
        g = DATA / "guide.json"
        if g.exists():
            try:
                self.guide = json.loads(g.read_text())
            except ValueError:
                pass
        # Combat coach
        self.killmails: list[dict] = []
        self.fights: list[dict] = load_json(DATA / "fights.json", [])  # finished fights, newest last
        self.tracker = combatlog.Tracker(on_end=self.fight_ended)
        self.tracker.next_id = max((f.get("id", 0) for f in self.fights), default=0) + 1
        self.parser = combatlog.Parser()
        self.tailer = combatlog.Tailer(COMBATLOG, from_start=COMBATLOG_REPLAY)
        self.debriefing: int | None = None
        self.debrief_next: dict | None = None
        self.combat_error: str | None = None
        # Mission briefings: questID -> briefing, cached so only new quests are asked for.
        self.briefings: dict[int, dict] = {int(k): v for k, v in load_json(DATA / "briefings.json", {}).items()}
        self.briefing = False
        self.brief_again = False
        self.quest_sig = ""

    async def watch(self) -> None:
        while True:
            try:
                await self.poll()
            except Exception as e:  # keep watching whatever happens
                log.exception("watch failed")
                self.last_error = f"watch: {e}"
            await asyncio.sleep(2)

    async def poll(self) -> None:
        path = sv_path()
        if not path:
            return
        mtime = path.stat().st_mtime
        if mtime == self.sv_mtime:
            return
        await asyncio.sleep(1)  # let WoW finish writing
        self.sv_mtime = path.stat().st_mtime
        data = await asyncio.to_thread(load_sv, path)
        self.killmails = clean_killmails(data.get("killmails"))
        state = data.get("state")
        if not state:
            log.info("no pilotState in %s yet", path)
            return
        self.state = state
        self.tracker.set_player_name(state.get("char"))
        qsig = json.dumps(sorted(q.get("id") or 0 for q in state.get("quests") or []))
        if BRIEFINGS and qsig != self.quest_sig:
            self.quest_sig = qsig
            asyncio.create_task(self.brief())
        write_atomic(DATA / "state.json", json.dumps(state, indent=2))
        sig = signature(state)
        log.info("state %s: %s, %d quests, sig %s", state.get("time"), (state.get("map") or {}).get("name"),
                 len(state.get("quests") or []), sig)
        if not self.guide or self.guide.get("signature") != sig:
            asyncio.create_task(self.plan())

    async def plan(self, goal: str | None = None) -> dict | None:
        if not self.state:
            raise RuntimeError("no game state yet: /reload in game first")
        if self.lock.locked():
            self.again = True
            return self.guide
        async with self.lock:
            self.planning = True
            try:
                while True:
                    self.again = False
                    state = self.state
                    goal = goal or state.get("goal")
                    t0 = time.time()
                    prompt = ("Player state:\n```json\n" + json.dumps(compact_state(state)) + "\n```\n"
                              + (f"\nThe player's goal: {goal}\n" if goal else "")
                              + "\nPlan the route now.")
                    log.info("planning (goal: %s)", goal)
                    result = await run_claude(prompt, options(PLAN_SYSTEM, PLAN_SCHEMA, 16))
                    plan = parse_plan(result)
                    steps = clean_steps(plan.get("steps") or [], state)
                    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
                    self.guide = {
                        "id": time.strftime("%Y%m%d%H%M%S"),
                        "created": stamp[11:16],
                        "stateTime": state.get("time"),
                        "signature": signature(state),
                        "summary": str(plan.get("summary") or "")[:300],
                        "steps": steps,
                    }
                    write_guide(self.guide)
                    self.last_plan_s = round(time.time() - t0, 1)
                    self.last_error = None
                    log.info("plan written: %d steps in %.0fs (cost %s)", len(steps), self.last_plan_s,
                             result.total_cost_usd)
                    if not self.again:
                        return self.guide
                    goal = None
            except Exception as e:
                log.exception("plan failed")
                self.last_error = f"plan: {e}"
                raise
            finally:
                self.planning = False

    # Combat coach ---------------------------------------------------------------

    async def combat(self) -> None:
        log.info("combat log: %s%s", COMBATLOG, " (replay)" if COMBATLOG_REPLAY else "")
        while True:
            try:
                lines = await asyncio.to_thread(self.tailer.poll)
                for ln in lines:
                    e = self.parser.parse(ln)
                    if e:
                        self.tracker.feed(e)
                self.tracker.tick()
                self.combat_error = None
            except Exception as e:  # keep tailing whatever happens
                log.exception("combat log failed")
                self.combat_error = f"combat log: {e}"
            await asyncio.sleep(0.5)

    def fight_ended(self, f: combatlog.Fight) -> None:
        s = f.summary()
        self.fights = [x for x in self.fights if x.get("id") != s["id"]][-39:] + [s]
        self.save_fights()
        log.info("fight %d ended: %s, %.0fs, %.0f dps", s["id"], s["name"], s["duration"], s["dps"])
        if s["duration"] < DEBRIEF_MIN_S:
            return
        if self.debriefing is not None:
            self.debrief_next = s  # only the latest waits; at most one in flight
            return
        self.debriefing = s["id"]
        asyncio.get_running_loop().create_task(self.debrief(s))

    def save_fights(self) -> None:
        write_atomic(DATA / "fights.json", json.dumps(self.fights[-20:]))

    async def debrief(self, s: dict) -> None:
        self.debriefing = s["id"]
        try:
            while s:
                st = self.state or {}
                facts = {k: s.get(k) for k in s if k not in ("castList", "debrief", "active")}
                facts["casts_seq"] = [f"{c['t']}:{c['name']}" for c in (s.get("castList") or [])[:150]]
                facts["player"] = {k: st.get(k) for k in ("class", "level", "race")}
                prompt = "Fight:\n```json\n" + json.dumps(facts) + "\n```\nDebrief this fight now."
                t0 = time.time()
                result = await run_claude(prompt, options(DEBRIEF_SYSTEM, DEBRIEF_SCHEMA, 4, web_tools=False))
                d = parse_plan(result)
                tips = [str(t).strip() for t in d.get("tips") or [] if str(t).strip()][:5]
                s["debrief"] = {"headline": str(d.get("headline") or "")[:80], "tips": tips,
                                "created": time.strftime("%H:%M:%S"), "seconds": round(time.time() - t0, 1)}
                for x in self.fights:
                    if x.get("id") == s["id"]:
                        x["debrief"] = s["debrief"]
                live = self.tracker.get(s["id"])
                if live:
                    live.debrief = s["debrief"]
                self.save_fights()
                write_comms(s)
                log.info("debrief for fight %d written (%.0fs, cost %s)", s["id"], time.time() - t0,
                         result.total_cost_usd)
                s, self.debrief_next = self.debrief_next, None
                if s:
                    self.debriefing = s["id"]
        except Exception as e:
            log.exception("debrief failed")
            self.combat_error = f"debrief: {e}"
        finally:
            self.debriefing = None

    def live(self) -> dict:
        t = self.tracker
        f = t.current
        return {
            "active": f is not None,
            "fight": f.summary() if f else (self.fights[-1] if self.fights else None),
            "player": t.player_label, "file": str(self.tailer.path) if self.tailer.path else None,
            "watching": str(COMBATLOG), "lines": t.lines, "debriefing": self.debriefing,
            "error": self.combat_error,
        }

    def fight(self, fid: int) -> dict | None:
        cur = self.tracker.current
        if cur and cur.id == fid:
            return cur.summary()
        return next((x for x in self.fights if x.get("id") == fid), None)

    # Mission briefings -----------------------------------------------------------

    async def brief(self) -> None:
        if self.briefing:
            self.brief_again = True
            return
        self.briefing = True
        try:
            while True:
                self.brief_again = False
                quests = [q for q in (self.state or {}).get("quests") or [] if isinstance(q.get("id"), int)]
                ids = {q["id"] for q in quests}
                todo = [q for q in quests if q["id"] not in self.briefings]
                for i in range(0, len(todo), 20):
                    slim = [{"id": q["id"], "title": q.get("title"), "level": q.get("level"),
                             "objectives": [o.get("text") for o in q.get("objectives") or []]} for q in todo[i:i + 20]]
                    st = self.state or {}
                    prompt = ("Player: " + json.dumps({k: st.get(k) for k in ("class", "race", "faction", "level")})
                              + "\nQuests:\n```json\n" + json.dumps(slim) + "\n```\nWrite the briefings now.")
                    result = await run_claude(prompt, options(BRIEF_SYSTEM, BRIEF_SCHEMA, 4, web_tools=False))
                    for b in parse_plan(result).get("briefings") or []:
                        qid = b.get("quest")
                        if qid in ids:
                            self.briefings[qid] = {
                                "agent": str(b.get("agent") or "")[:60], "text": str(b.get("text") or "")[:500],
                                "objective": str(b.get("objective") or "")[:80], "tip": str(b.get("tip") or "")[:120],
                            }
                    log.info("briefings written for %d quests (cost %s)", len(slim), result.total_cost_usd)
                current = {q: b for q, b in self.briefings.items() if q in ids}
                self.briefings = current
                write_atomic(DATA / "briefings.json", json.dumps(current))
                write_briefings(current)
                if not self.brief_again:
                    return
        except Exception as e:
            log.exception("briefings failed")
            self.last_error = f"briefings: {e}"
        finally:
            self.briefing = False

    async def ask(self, question: str) -> str:
        prompt = ("Player state:\n```json\n" + json.dumps(compact_state(self.state or {})) + "\n```\n\n"
                  f"Question: {question}")
        result = await run_claude(prompt, options(ASK_SYSTEM, None, 8))
        return result.result or ""


# HTTP ---------------------------------------------------------------------------------

def load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def clean_killmails(km) -> list[dict]:
    if isinstance(km, dict):  # a sparse Lua array encodes as an object
        km = [v for _, v in sorted(km.items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0)]
    if not isinstance(km, list):
        return []
    out = [k for k in km if isinstance(k, dict)]
    for k in out:
        for key in ("damage",):
            if isinstance(k.get(key), dict):
                k[key] = list(k[key].values())
    return out


def make_app(p: Pilot) -> web.Application:
    app = web.Application()
    routes = web.RouteTableDef()

    @routes.get("/")
    async def index(_):
        return web.FileResponse(HERE / "index.html")

    @routes.get("/health")
    async def health(_):
        sv = sv_path()
        return web.json_response({
            "ok": True, "planning": p.planning, "last_error": p.last_error, "last_plan_seconds": p.last_plan_s,
            "guide": p.guide and {k: p.guide.get(k) for k in ("id", "created", "stateTime", "summary")},
            "state_time": p.state and p.state.get("time"), "savedvariables": str(sv) if sv else None,
            "guide_file": str(ADDON / "Guide.lua"),
            "combatlog": str(p.tailer.path) if p.tailer.path else None, "debriefing": p.debriefing,
            "briefing": p.briefing, "combat_error": p.combat_error,
        })

    @routes.get("/state")
    async def state(_):
        return web.json_response(p.state or {})

    @routes.get("/guide")
    async def guide(_):
        return web.json_response(p.guide or {})

    @routes.post("/plan")
    async def plan(req):
        body = await req.json() if req.can_read_body else {}
        try:
            g = await p.plan((body or {}).get("goal"))
        except Exception as e:
            return web.json_response({"error": str(e)}, status=500)
        return web.json_response(g or {})

    @routes.post("/ask")
    async def ask(req):
        body = await req.json()
        q = str(body.get("question") or "").strip()
        if not q:
            return web.json_response({"error": "question is empty"}, status=400)
        try:
            return web.json_response({"answer": await p.ask(q[:1000])})
        except Exception as e:
            log.exception("ask failed")
            return web.json_response({"error": str(e)}, status=500)

    @routes.get("/combat/live")
    async def combat_live(_):
        return web.json_response(p.live())

    @routes.get("/combat/fights")
    async def combat_fights(_):
        keys = ("id", "name", "start", "end", "duration", "damage", "healing", "taken", "dps", "hps", "deaths",
                "kills", "outcome", "debrief")
        items = [{k: f.get(k) for k in keys} for f in reversed(p.fights)]
        cur = p.tracker.current
        if cur:
            items.insert(0, cur.summary(full=False))
        return web.json_response({"fights": items, "debriefing": p.debriefing})

    @routes.get(r"/combat/fight/{fid:\d+}")
    async def combat_fight(req):
        f = p.fight(int(req.match_info["fid"]))
        if not f:
            return web.json_response({"error": "no such fight"}, status=404)
        return web.json_response(f)

    @routes.post(r"/combat/fight/{fid:\d+}/debrief")
    async def combat_debrief(req):
        f = p.fight(int(req.match_info["fid"]))
        if not f or f.get("active"):
            return web.json_response({"error": "no finished fight with that id"}, status=404)
        if p.debriefing is not None:
            return web.json_response({"error": "a debrief is already running"}, status=409)
        p.debriefing = f["id"]
        asyncio.create_task(p.debrief(f))
        return web.json_response({"ok": True})

    @routes.get("/killmails")
    async def killmails(_):
        return web.json_response({"killmails": list(reversed(p.killmails))})

    @routes.get("/briefings")
    async def briefings(_):
        return web.json_response({"briefings": p.briefings, "working": p.briefing})

    app.add_routes(routes)

    async def start(_app):
        _app["watch"] = asyncio.create_task(p.watch())
        _app["combat"] = asyncio.create_task(p.combat())

    app.on_startup.append(start)
    return app


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    DATA.mkdir(parents=True, exist_ok=True)
    log.info("watching %s, writing %s, http %s:%d", WOW, ADDON / "Guide.lua", HOST, PORT)
    web.run_app(make_app(Pilot()), host=HOST, port=PORT, print=None)


if __name__ == "__main__":
    main()
