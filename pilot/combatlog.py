"""Combat log reader for the EveUI pilot.

Tails the client's WoWCombatLog*.txt (written while the player has /combatlog
on), follows rotation to newer files, parses standard WoW combat log lines
(with or without advanced logging) and splits the player's activity into
fights with per-second DPS/HPS, spell breakdowns, casts, damage taken, deaths,
interrupts and DoT/HoT uptime.
"""

from __future__ import annotations

import csv
import os
import re
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

GAP = float(os.environ.get("EVEUI_COMBAT_GAP", "5"))  # seconds without activity that end a fight

# Unit flags (COMBATLOG_OBJECT_*).
MINE = 0x1
FRIENDLY, NEUTRAL, HOSTILE = 0x10, 0x20, 0x40
T_PLAYER, T_NPC, T_PET, T_GUARDIAN = 0x400, 0x800, 0x1000, 0x2000

TS = re.compile(
    r"^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\s+(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(?:[-+]\d+)?\s+(.*)$")
GUIDISH = re.compile(r"^(0000000000000000|0|[A-Za-z]+-[0-9A-Za-z-]+)$")
FLOAT = re.compile(r"^-?\d+\.\d+$")
INT = re.compile(r"^-?\d+$")
ENV_TYPES = {"Falling", "Drowning", "Fatigue", "Fire", "Lava", "Slime"}
NO_BASE = {"COMBAT_LOG_VERSION", "ZONE_CHANGE", "MAP_CHANGE", "ENCOUNTER_START", "ENCOUNTER_END",
           "COMBATANT_INFO", "EMOTE", "CHALLENGE_MODE_START", "CHALLENGE_MODE_END", "WORLD_MARKER_PLACED",
           "WORLD_MARKER_REMOVED", "ARENA_MATCH_START", "ARENA_MATCH_END"}


def flags(s: str) -> int:
    try:
        return int(s, 16) if s.lower().startswith("0x") else int(s)
    except (ValueError, AttributeError):
        return 0


def num(s: str | None) -> int:
    if s is None:
        return 0
    try:
        return int(s)
    except ValueError:
        try:
            return int(float(s))
        except ValueError:
            return 0


def wine_path(p: str) -> Path:
    """Accept Linux paths and Windows paths (C:\\...) inside the Wine prefix."""
    m = re.match(r"^([A-Za-z]):[\\/](.*)$", p)
    if m:
        prefix = Path(os.environ.get("WINEPREFIX", "~/Games/battlenet")).expanduser()
        return prefix / f"drive_{m.group(1).lower()}" / m.group(2).replace("\\", "/")
    return Path(p).expanduser()


# Parsing -------------------------------------------------------------------------

@dataclass
class Ev:
    t: float
    event: str
    src: str = ""
    src_name: str = ""
    src_flags: int = 0
    dst: str = ""
    dst_name: str = ""
    dst_flags: int = 0
    spell_id: int = 0
    spell: str = ""
    school: int = 0
    rest: list = field(default_factory=list)  # suffix fields, advanced block removed
    info_guid: str = ""
    hp: int = 0
    max_hp: int = 0
    raw: list = field(default_factory=list)


class Parser:
    def __init__(self) -> None:
        self.version = 20
        self.advanced = True
        self.year = datetime.now().year

    def timestamp(self, m: re.Match) -> float:
        mo, d, y, h, mi, s, ms = m.group(1, 2, 3, 4, 5, 6, 7)
        year = int(y) if y else self.year
        if year < 100:
            year += 2000
        try:
            dt = datetime(year, int(mo), int(d), int(h), int(mi), int(s), int((ms or "0").ljust(3, "0")) * 1000)
        except ValueError:
            return time.time()
        return dt.timestamp()

    def strip_advanced(self, rest: list) -> tuple[list, list]:
        """Remove the advanced-logging block (infoGUID ... positionX, positionY, uiMapID, facing[, level])."""
        if not rest or not GUIDISH.match(rest[0]) or len(rest) < 12:
            return rest, []
        for i in range(8, min(len(rest) - 3, 16)):
            if FLOAT.match(rest[i]) and FLOAT.match(rest[i + 1]) and INT.match(rest[i + 2]) \
                    and FLOAT.match(rest[i + 3]):
                end = i + 4 + (1 if self.version >= 9 and i + 4 < len(rest) and INT.match(rest[i + 4]) else 0)
                return rest[end:], rest[:end]
        return rest, []

    def parse(self, line: str) -> Ev | None:
        m = TS.match(line.strip())
        if not m:
            return None
        try:
            f = next(csv.reader([m.group(8)]))
        except (csv.Error, StopIteration):
            return None
        if not f:
            return None
        ev = f[0]
        t = self.timestamp(m)
        if ev == "COMBAT_LOG_VERSION":
            self.version = num(f[1]) if len(f) > 1 else self.version
            if "ADVANCED_LOG_ENABLED" in f:
                i = f.index("ADVANCED_LOG_ENABLED")
                self.advanced = i + 1 < len(f) and f[i + 1] == "1"
            return Ev(t, ev, raw=f)
        if ev in NO_BASE or len(f) < 9:
            return Ev(t, ev, raw=f)
        e = Ev(t, ev, f[1], f[2], flags(f[3]), f[5], f[6], flags(f[7]))
        rest = f[9:]
        if ev.startswith(("SPELL_", "RANGE_")) or ev in ("DAMAGE_SPLIT", "DAMAGE_SHIELD", "DAMAGE_SHIELD_MISSED"):
            if len(rest) >= 3:
                e.spell_id, e.spell, e.school = num(rest[0]), rest[1], flags(rest[2])
                rest = rest[3:]
        elif ev.startswith("SWING_"):
            e.spell_id, e.spell = 6603, "Melee"
        elif ev.startswith("ENVIRONMENTAL_"):
            for i, x in enumerate(rest):
                if x in ENV_TYPES:
                    e.spell = x
                    rest = rest[i + 1:]
                    break
            else:
                rest, _ = self.strip_advanced(rest)
                if rest:
                    e.spell, rest = rest[0], rest[1:]
            e.rest = rest
            return e
        rest, adv = self.strip_advanced(rest)
        if adv:
            e.info_guid = adv[0]
            if len(adv) > 3:
                e.hp, e.max_hp = num(adv[2]), num(adv[3])
        e.rest = rest
        return e


def trim_tail(rest: list) -> list:
    """Drop trailing non-numeric tags some versions add (ST/AOE damage type)."""
    out = list(rest)
    while out and not INT.match(out[-1]) and out[-1] not in ("nil", "1"):
        out.pop()
    return out


def damage_of(e: Ev) -> tuple[int, bool, int]:
    """amount, critical, overkill for a *_DAMAGE event."""
    r = trim_tail(e.rest)
    if not r:
        return 0, False, 0
    amount = num(r[0])
    # File layout: amount[, baseAmount], overkill, school, resisted, blocked, absorbed,
    # critical, glancing, crushing[, isOffHand]. Count the trailing nil/1 flags.
    k = 0
    while k < 4 and k < len(r) and r[-1 - k] in ("nil", "1"):
        k += 1
    flags_n = 4 if k >= 4 else 3
    crit = len(r) > flags_n and r[-flags_n] == "1"
    oi = -(flags_n + 5)
    overkill = max(0, num(r[oi])) if len(r) >= -oi + 1 else 0
    return amount, crit, overkill


def heal_of(e: Ev) -> tuple[int, int, bool]:
    """amount, overheal, critical for a *_HEAL event."""
    r = trim_tail(e.rest)
    if not r:
        return 0, 0, False
    amount = num(r[0])
    over = num(r[-3]) if len(r) >= 4 else 0
    return amount, max(0, over), r[-1] == "1"


# Fights --------------------------------------------------------------------------

def is_damage(ev: str) -> bool:
    return ev.endswith("_DAMAGE") or ev in ("DAMAGE_SPLIT", "DAMAGE_SHIELD")


class Fight:
    def __init__(self, fid: int, t: float, player: str) -> None:
        self.id = fid
        self.start = t
        self.last = t
        self.end: float | None = None
        self.player = player
        self.encounter: str | None = None
        self.targets: dict[str, int] = {}
        self.engaged: set[str] = set()
        self.dmg: dict[int, int] = {}
        self.heal: dict[int, int] = {}
        self.taken_t: dict[int, int] = {}
        self.spells: dict[str, dict] = {}
        self.heals: dict[str, dict] = {}
        self.casts: list[dict] = []
        self.taken: dict[str, dict] = {}
        self.deaths: list[dict] = []
        self.kills: list[str] = []
        self.interrupts: list[dict] = []
        self.enemy_casts: dict[str, dict] = {}  # srcGUID -> pending cast start
        self.enemy_done: list[dict] = []
        self.auras: dict[int, dict] = {}
        self.misses = 0
        self.cast_counts: dict[str, int] = {}
        self.overheal = 0
        self.debrief: dict | None = None
        self.outcome = "ok"

    def sec(self, t: float) -> int:
        return max(0, int(t - self.start))

    def duration(self) -> float:
        return max(1.0, (self.end or self.last) - self.start)

    def name(self) -> str:
        if self.encounter:
            return self.encounter
        if not self.targets:
            return "Unknown"
        top = sorted(self.targets.items(), key=lambda kv: -kv[1])
        first = top[0][0].split("-")[0]
        return first + (f" +{len(top) - 1}" if len(top) > 1 else "")

    def uptime(self) -> list[dict]:
        end = self.end or self.last
        out = []
        for sid, a in self.auras.items():
            ivs = list(a["intervals"]) + [(s, end) for s in a["open"].values()]
            ivs = sorted((max(s, self.start), min(e, end)) for s, e in ivs if e > s)
            total, cur_s, cur_e = 0.0, None, None
            for s, e in ivs:
                if cur_e is None or s > cur_e:
                    if cur_e is not None:
                        total += cur_e - cur_s
                    cur_s, cur_e = s, e
                else:
                    cur_e = max(cur_e, e)
            if cur_e is not None:
                total += cur_e - cur_s
            out.append({"spellId": sid, "name": a["name"], "kind": a["kind"], "applications": a["apps"],
                        "uptime": round(min(100.0, total / self.duration() * 100), 1)})
        return sorted(out, key=lambda x: -x["uptime"])

    def summary(self, full: bool = True) -> dict:
        dur = self.duration()
        n = int(dur) + 1
        dmg_total = sum(self.dmg.values())
        heal_total = sum(self.heal.values())
        taken_total = sum(self.taken_t.values())
        s = {
            "id": self.id, "name": self.name(), "start": round(self.start, 3),
            "end": self.end and round(self.end, 3), "active": self.end is None,
            "duration": round(dur, 1), "damage": dmg_total, "healing": heal_total, "taken": taken_total,
            "dps": round(dmg_total / dur, 1), "hps": round(heal_total / dur, 1),
            "dtps": round(taken_total / dur, 1), "overheal": self.overheal,
            "deaths": len(self.deaths), "kills": len(self.kills), "casts": len(self.casts),
            "interrupts": len(self.interrupts), "outcome": self.outcome,
            "debrief": self.debrief,
        }
        if not full:
            return s
        gaps = [b["t"] - a["t"] for a, b in zip(self.casts, self.casts[1:])]
        for key, sp in list(self.spells.items()) + list(self.heals.items()):
            sp["casts"] = self.cast_counts.get(key, 0)
        s.update({
            "timeline": {
                "dps": [self.dmg.get(i, 0) for i in range(n)],
                "hps": [self.heal.get(i, 0) for i in range(n)],
                "taken": [self.taken_t.get(i, 0) for i in range(n)],
            },
            "spells": sorted(self.spells.values(), key=lambda x: -x["amount"]),
            "heals": sorted(self.heals.values(), key=lambda x: -x["amount"]),
            "castList": self.casts[-400:],
            "takenBy": sorted(({"source": k, **v} for k, v in self.taken.items()), key=lambda x: -x["amount"]),
            "deathList": self.deaths,
            "killList": self.kills,
            "interruptList": self.interrupts,
            "enemyCasts": {
                "completed": len(self.enemy_done),
                "list": self.enemy_done[-20:],
            },
            "uptime": self.uptime(),
            "idle": round(sum(g - 1.5 for g in gaps if g > 2.5), 1),
            "misses": self.misses,
            "targets": sorted(({"name": k, "amount": v} for k, v in self.targets.items()), key=lambda x: -x["amount"]),
        })
        return s


class Tracker:
    """Feeds parsed events, keeps the current fight and a history of finished ones."""

    def __init__(self, player_name: str | None = None, on_end=None, keep: int = 40) -> None:
        self.player_name = (player_name or "").split("-")[0] or None
        self.player: str | None = None  # GUID
        self.player_label: str | None = None
        self.current: Fight | None = None
        self.fights: deque[Fight] = deque(maxlen=keep)
        self.next_id = 1
        self.on_end = on_end
        self.recent: deque[dict] = deque(maxlen=10)  # last events hitting the player
        self.skew = 0.0  # wall clock minus log time at the last line read
        self.lines = 0
        self.last_event_t: float | None = None
        self.encounter: str | None = None
        self.pre: deque[Ev] = deque(maxlen=6)  # player casts just before a pull

    def mine(self, guid: str, fl: int) -> bool:
        return guid == self.player or (bool(fl & MINE) and bool(fl & (T_PET | T_GUARDIAN)))

    def detect(self, e: Ev) -> None:
        if self.player or not e.src.startswith("Player-"):
            return
        if self.player_name:
            if e.src_name.split("-")[0] == self.player_name:
                self.player, self.player_label = e.src, e.src_name
        elif e.src_flags & MINE and e.src_flags & T_PLAYER:
            self.player, self.player_label = e.src, e.src_name

    def set_player_name(self, name: str | None) -> None:
        name = (name or "").split("-")[0] or None
        if name and name != self.player_name:
            self.player_name = name
            if self.player_label and self.player_label.split("-")[0] != name:
                self.player = self.player_label = None

    def feed(self, e: Ev) -> None:
        self.lines += 1
        self.skew = time.time() - e.t
        self.last_event_t = e.t
        if e.event == "ENCOUNTER_START":
            self.encounter = e.raw[2] if len(e.raw) > 2 else None
            if self.current:
                self.current.encounter = self.encounter
            return
        if e.event == "ENCOUNTER_END":
            self.encounter = None
            if self.current:
                self.close(e.t)
            return
        if not e.src and not e.dst:
            return
        self.detect(e)
        if not self.player:
            return
        f = self.current
        if f and e.t - f.last > GAP:
            self.close(f.last)
            f = None
        ev = e.event
        src_mine = self.mine(e.src, e.src_flags)
        dst_me = e.dst == self.player
        hostile_dst = not self.mine(e.dst, e.dst_flags) and e.dst_flags & (HOSTILE | NEUTRAL) and e.dst != self.player
        engage = (ev.endswith(("_DAMAGE", "_MISSED")) and
                  ((src_mine and hostile_dst) or (dst_me and not src_mine and e.src)))
        if engage and not f:
            f = self.current = Fight(self.next_id, e.t, self.player)
            f.encounter = self.encounter
            self.next_id += 1
            for c in self.pre:
                if c.t >= e.t - 3:
                    f.start = min(f.start, c.t)
            for c in self.pre:
                if c.t >= e.t - 3:
                    self.apply(f, c, True, False, False)
            self.pre.clear()
        if not f and e.event == "SPELL_CAST_SUCCESS" and e.src == self.player:
            self.pre.append(e)
        if dst_me and (is_damage(ev) or ev.endswith(("_HEAL", "_MISSED")) or ev == "ENVIRONMENTAL_DAMAGE"):
            self.note_recent(e)
        if not f:
            return
        if engage:
            f.last = e.t
            f.engaged.add(e.dst if src_mine else e.src)
        self.apply(f, e, src_mine, dst_me, bool(hostile_dst))

    def note_recent(self, e: Ev) -> None:
        item = {"t": e.t, "event": e.event, "source": e.src_name.split("-")[0] or e.spell or "?",
                "spell": e.spell}
        if is_damage(e.event) or e.event == "ENVIRONMENTAL_DAMAGE":
            item["amount"], item["crit"], item["overkill"] = damage_of(e)
            item["kind"] = "damage"
        elif e.event.endswith("_HEAL"):
            item["amount"], _, item["crit"] = heal_of(e)
            item["kind"] = "heal"
        else:
            item["kind"] = "miss"
            item["miss"] = e.rest[0] if e.rest else ""
        if e.info_guid == self.player and e.max_hp:
            item["hp"] = round(e.hp / e.max_hp * 100)
        self.recent.append(item)

    def apply(self, f: Fight, e: Ev, src_mine: bool, dst_me: bool, hostile_dst: bool) -> None:
        ev = e.event
        sec = f.sec(e.t)
        key = f"{e.spell_id}:{e.spell}"
        if src_mine and is_damage(ev) and hostile_dst:
            amount, crit, _ = damage_of(e)
            f.dmg[sec] = f.dmg.get(sec, 0) + amount
            sp = f.spells.setdefault(key, {"spellId": e.spell_id, "name": e.spell or "?", "amount": 0, "hits": 0,
                                           "crits": 0, "max": 0, "pet": e.src != self.player,
                                           "periodic": "PERIODIC" in ev})
            sp["amount"] += amount
            sp["hits"] += 1
            sp["crits"] += crit
            sp["max"] = max(sp["max"], amount)
            name = e.dst_name or "?"
            f.targets[name] = f.targets.get(name, 0) + amount
        elif src_mine and ev.endswith("_MISSED") and hostile_dst:
            f.misses += 1
        elif src_mine and ev.endswith("_HEAL"):
            amount, over, crit = heal_of(e)
            eff = max(0, amount - over)
            f.heal[sec] = f.heal.get(sec, 0) + eff
            f.overheal += over
            sp = f.heals.setdefault(key, {"spellId": e.spell_id, "name": e.spell or "?", "amount": 0,
                                          "overheal": 0, "hits": 0, "crits": 0})
            sp["amount"] += eff
            sp["overheal"] += over
            sp["hits"] += 1
            sp["crits"] += crit
        if dst_me and (is_damage(ev) or ev == "ENVIRONMENTAL_DAMAGE"):
            amount, _, _ = damage_of(e)
            f.taken_t[sec] = f.taken_t.get(sec, 0) + amount
            srcn = (e.src_name.split("-")[0] if e.src_name else "") or e.spell or "Environment"
            t = f.taken.setdefault(srcn, {"amount": 0, "hits": 0, "spells": {}})
            t["amount"] += amount
            t["hits"] += 1
            t["spells"][e.spell or "?"] = t["spells"].get(e.spell or "?", 0) + amount
        if ev == "SPELL_CAST_SUCCESS" and e.src == self.player:
            f.casts.append({"t": round(e.t - f.start, 2), "spellId": e.spell_id, "name": e.spell})
            f.cast_counts[key] = f.cast_counts.get(key, 0) + 1
        hostile_src = not src_mine and e.src and not e.src.startswith("Player-") and e.src_flags & (HOSTILE | NEUTRAL)
        if hostile_src and e.src in f.engaged:
            if ev == "SPELL_CAST_START":
                f.enemy_casts[e.src] = {"t": e.t, "spellId": e.spell_id, "name": e.spell,
                                        "source": e.src_name}
            elif ev == "SPELL_CAST_SUCCESS":
                st = f.enemy_casts.pop(e.src, None)
                if st and st["spellId"] == e.spell_id:
                    f.enemy_done.append({"t": round(e.t - f.start, 1), "name": e.spell, "source": e.src_name,
                                         "castTime": round(e.t - st["t"], 1)})
            elif ev == "SPELL_CAST_FAILED":
                f.enemy_casts.pop(e.src, None)
        if ev == "SPELL_INTERRUPT" and src_mine:
            f.interrupts.append({"t": round(e.t - f.start, 1), "spell": e.spell, "target": e.dst_name,
                                 "interrupted": e.rest[1] if len(e.rest) > 1 else "?"})
            f.enemy_casts.pop(e.dst, None)
        if ev.startswith("SPELL_AURA_") and e.src == self.player and e.dst:
            kind = e.rest[0] if e.rest else ""
            if (kind == "DEBUFF" and hostile_dst) or (kind == "BUFF" and not hostile_dst):
                self.aura(f, e, kind)
        if ev in ("UNIT_DIED", "UNIT_DESTROYED"):
            if e.dst == self.player:
                killer = next((r["source"] for r in reversed(self.recent) if r["kind"] == "damage"), None)
                f.deaths.append({"t": round(e.t - f.start, 1), "killer": killer,
                                 "events": [dict(r, t=round(r["t"] - e.t, 1)) for r in self.recent]})
                f.outcome = "death"
                self.close(e.t)
                return
            if e.dst in f.engaged:
                f.engaged.discard(e.dst)
                f.kills.append(e.dst_name)
                f.last = e.t
                if not f.engaged and not f.encounter:
                    self.close(e.t)

    def aura(self, f: Fight, e: Ev, kind: str) -> None:
        a = f.auras.setdefault(e.spell_id, {"name": e.spell, "kind": kind, "intervals": [], "open": {}, "apps": 0})
        if e.event in ("SPELL_AURA_APPLIED", "SPELL_AURA_REFRESH"):
            if e.dst not in a["open"]:
                a["open"][e.dst] = e.t
            a["apps"] += 1
        elif e.event in ("SPELL_AURA_REMOVED", "SPELL_AURA_BROKEN", "SPELL_AURA_BROKEN_SPELL"):
            s = a["open"].pop(e.dst, None)
            if s is not None:
                a["intervals"].append((s, e.t))

    def close(self, t: float) -> None:
        f = self.current
        if not f:
            return
        f.end = max(t, f.start)
        self.current = None
        if not f.dmg and not f.heal and not f.taken_t and not f.deaths:
            return
        self.fights.append(f)
        if self.on_end:
            self.on_end(f)

    def tick(self) -> None:
        """Close the fight when the log has gone quiet (wall clock mapped to log time)."""
        f = self.current
        if f and time.time() - self.skew - f.last > GAP + 1:
            self.close(f.last)

    def get(self, fid: int) -> Fight | None:
        if self.current and self.current.id == fid:
            return self.current
        return next((f for f in self.fights if f.id == fid), None)


# Tailing -------------------------------------------------------------------------

class Tailer:
    """Follows the newest WoWCombatLog*.txt in a directory (or one given file)."""

    def __init__(self, target: Path, from_start: bool = False) -> None:
        self.target = target
        self.from_start = from_start
        self.path: Path | None = None
        self.pos = 0
        self.buf = b""
        self.header: str | None = None

    def newest(self) -> Path | None:
        if self.target.is_file():
            return self.target
        if not self.target.is_dir():
            return None
        files = [p for p in self.target.glob("WoWCombatLog*.txt") if p.is_file()]
        return max(files, key=lambda p: p.stat().st_mtime) if files else None

    def read_header(self, p: Path) -> None:
        try:
            with p.open("rb") as fh:
                line = fh.readline(4096).decode("utf-8", "replace")
            self.header = line if "COMBAT_LOG_VERSION" in line else None
        except OSError:
            self.header = None

    def poll(self) -> list[str]:
        out: list[str] = []
        p = self.newest()
        if p is None:
            return out
        if p != self.path:
            if self.path is not None and self.path.exists():
                out += self._read()  # drain the old file
                self.buf = b""
            first = self.path is None
            self.path = p
            self.pos = p.stat().st_size if first and not self.from_start else 0
            self.read_header(p)
            if self.header and self.pos > 0:
                out.append(self.header)
        try:
            size = self.path.stat().st_size
        except OSError:
            return out
        if size < self.pos:  # truncated / rewritten
            self.pos, self.buf = 0, b""
        if size > self.pos:
            out += self._read()
        return out

    def _read(self) -> list[str]:
        assert self.path is not None
        try:
            with self.path.open("rb") as fh:
                fh.seek(self.pos)
                data = fh.read(8 * 1024 * 1024)
                self.pos = fh.tell()
        except OSError:
            return []
        data = self.buf + data
        lines = data.split(b"\n")
        self.buf = lines.pop()
        return [ln.decode("utf-8", "replace").rstrip("\r") for ln in lines if ln.strip()]
