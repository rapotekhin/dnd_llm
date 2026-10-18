"""Driver for live playtests of the legacy pygame game.

Runs the real Game and screens on a dummy display (no window), feeds them pygame
events like a player would, uses the real LLM from .env, and saves a screenshot
plus a report after every step. Scenarios live next to this file.
"""
import os
import sys
import time
from pathlib import Path

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")

REPO = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "out"
for _p in (REPO / "legacy" / "game", REPO / "dnd-5e-core", REPO / "DnD-5th-Edition-API"):
    if _p.exists() and str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import pygame  # noqa: E402

pygame.scrap.init = lambda: None  # the dummy video driver has no clipboard
pygame.scrap.get = lambda *a: None

from core.logging_config import configure_logging, get_logger  # noqa: E402

configure_logging()
log = get_logger("playtest")

from core.game import Game  # noqa: E402

REPORT: list[str] = []


def note(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    REPORT.append(line)


def dump_chat(title: str, entries) -> None:
    REPORT.append(f"--- {title} ---")
    for role, text in entries:
        REPORT.append(f"  {role:9} {text}")


def errors_in(entries) -> list[str]:
    return [t for r, t in entries if r == "SYSTEM" and ("Ошибка" in t or "Мастер не ответил" in t)]


class Driver:
    def __init__(self) -> None:
        OUT.mkdir(exist_ok=True)
        for old in OUT.glob("*"):
            old.unlink()
        self.game = Game()
        self.step = 0

    # ── frame pump (mirrors Game.run) ────────────────────────────────
    def frame(self) -> None:
        g = self.game
        for event in pygame.event.get():
            if event.type == pygame.VIDEORESIZE:
                if not (g.screen.get_flags() & pygame.FULLSCREEN):
                    g._create_display((event.w, event.h), False)
                    g._init_screens()
                continue
            if g.current_screen:
                g._handle_screen_result(g.current_screen.handle_event(event))
        if g.current_screen:
            result = g.current_screen.update()
            if result:
                g._handle_screen_result(result)
            g.current_screen.draw()
        pygame.display.flip()
        g.clock.tick(60)

    def pump(self, seconds: float) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            self.frame()

    def wait_for(self, pred, timeout: float, what: str) -> bool:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            self.frame()
            if pred():
                note(f"OK   {what}")
                return True
        note(f"FAIL timeout waiting for: {what}")
        return False

    def turn_done(self) -> bool:
        """A turn is over when the active screen waits for the player (or trade opened)."""
        name = self.game.current_screen_name
        if name == "main":
            return self.main()._awaiting_input
        if name == "social":
            return self.social()._awaiting_input
        return name == "trade"

    def wait_turn(self, what: str, timeout: float = 120) -> bool:
        ok = self.wait_for(self.turn_done, timeout, what)
        note(f"     -> screen={self.game.current_screen_name}")
        return ok

    # ── input ────────────────────────────────────────────────────────
    def key(self, key: int, uni: str = "") -> None:
        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=key, unicode=uni, mod=0, scancode=0))
        pygame.event.post(pygame.event.Event(pygame.KEYUP, key=key, mod=0, scancode=0))
        self.frame()

    def type_text(self, text: str) -> None:
        """Type into the focused input box and press Enter."""
        for ch in text:
            pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=0, unicode=ch, mod=0, scancode=0))
        self.frame()
        self.key(pygame.K_RETURN, "\r")

    def click(self, pos) -> None:
        pygame.mouse.set_pos(pos)
        pygame.event.post(pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=pos, button=1))
        pygame.event.post(pygame.event.Event(pygame.MOUSEBUTTONUP, pos=pos, button=1))
        self.frame()
        self.frame()

    def resize(self, w: int, h: int) -> None:
        pygame.event.post(pygame.event.Event(pygame.VIDEORESIZE, w=w, h=h, size=(w, h)))
        self.pump(0.5)

    # ── evidence ─────────────────────────────────────────────────────
    def shot(self, name: str) -> Path:
        self.frame()
        self.step += 1
        path = OUT / f"{self.step:02d}_{name}.png"
        pygame.image.save(self.game.screen, str(path))
        note(f"shot {path.name} (screen={self.game.current_screen_name})")
        return path

    def main(self):
        return self.game.screens["main"]

    def social(self):
        return self.game.screens["social"]

    def main_chat(self):
        return [(e.role.name, e.text) for e in self.main().chat_entries]

    def social_chat(self):
        return [(e.role.name, e.text) for e in self.social()._chat_entries]

    def stop_threads(self) -> None:
        self.main()._stop_event.set()
        self.social()._stop_event.set()


def make_character(cls: str = "fighter", name: str = "Ирма", gender: str = "female"):
    """Build a level-1 character the way the creation wizard does."""
    from core.builders.character_builder import CharacterBuild
    from core.database.json_database import JsonDatabase

    hero = CharacterBuild(
        name=name, race="human", class_type=cls,
        class_data=JsonDatabase().get(f"/classes/{cls}.json"),
        alignment="neutral-good",
        abilities={"str": 15, "dex": 14, "con": 13, "int": 10, "wis": 12, "cha": 8},
        points_remaining=0,
    ).create_character()
    hero.gender = gender
    return hero


def run_scenario(scenario) -> int:
    """Run ``scenario(driver)``, always write out/report.txt; returns an exit code."""
    code = 0
    try:
        driver = Driver()
        note(f"API valid={driver.game.api_manager.is_valid} model={driver.game.api_manager.model_name}")
        scenario(driver)
        driver.stop_threads()
    except Exception:
        log.exception("playtest crashed")
        note("CRASH (see log above)")
        code = 1
    finally:
        (OUT / "report.txt").write_text("\n".join(REPORT), encoding="utf-8")
        pygame.quit()
    if any(line.split("] ", 1)[-1].startswith("FAIL") for line in REPORT):
        code = code or 2
    return code
