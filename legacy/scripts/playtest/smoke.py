"""Smoke playtest: one pass through every main feature of the legacy game.

    python legacy/scripts/playtest/smoke.py

Real LLM calls (OpenRouter key from .env), ~20 calls on the default model.
Screenshots and report.txt go to legacy/scripts/playtest/out/.
"""
import sys

import pygame

from driver import Driver, dump_chat, errors_in, make_character, note, run_scenario


def inspect_trade(d: Driver) -> None:
    """Screenshot the open trade screen, then go back the way a player would (Esc)."""
    g = d.game
    t = g.screens["trade"]._trade
    npc = t.get_npc()
    note(f"trade: npc_items={len(t.npc_inv_items())} player_items={len(t.player_inv_items())} "
         f"player_coins={t.get_player().coins} npc_coins={npc.coins if npc else None}")
    d.shot("trade")
    d.key(pygame.K_ESCAPE)
    d.wait_turn("back from trade")
    d.shot("after_trade")


def smoke(d: Driver) -> None:
    g = d.game

    # Character -> first scene
    hero = make_character()
    g._handle_screen_result(hero)
    note(f"character: {hero.class_type.index} lvl={hero.level} xp={hero.xp} "
         f"hp={hero.hit_points}/{hero.max_hit_points} ac={hero.armor_class} coins={hero.coins}")
    d.wait_turn("first scene")
    d.shot("scene")

    # Side screens and back: exploration must survive (B1)
    d.click(d.main().nav_buttons[0].rect.center)
    d.shot("inventory")
    d.key(pygame.K_ESCAPE)
    d.click(d.main().nav_buttons[3].rect.center)
    d.shot("character_sheet")
    d.key(pygame.K_ESCAPE)
    d.pump(0.5)
    note(f"back on {g.current_screen_name}: thread_alive={d.main()._exploration_thread.is_alive()} "
         f"awaiting={d.main()._awaiting_input} errors={errors_in(d.main_chat())}")

    # Action + typing while the DM thinks (B19) + resize mid-turn (B2)
    d.type_text("Осматриваю зал и ищу что-нибудь необычное")
    d.pump(0.3)
    d.main().input_buffer = "это не должно уйти"
    d.key(pygame.K_RETURN, "\r")
    note(f"buffer kept while thinking: {d.main().input_buffer == 'это не должно уйти'}")
    d.main().input_buffer = ""
    before = len(d.main_chat())
    d.resize(1600, 900)
    note(f"resize mid-turn: chat {before} -> {len(d.main_chat())}, "
         f"thread_alive={d.main()._exploration_thread.is_alive()}")
    d.wait_turn("search resolved after resize")
    d.shot("after_search")

    # Attack attempt: combat is not implemented, scene must go on (B3, B25)
    if g.current_screen_name == "main":
        d.type_text("Бью ближайшего пьяницу кулаком в лицо")
        d.wait_turn("attack attempt")
        d.shot("attack_attempt")

    # Dialogue with an NPC in the room
    import core.data as game_data
    gs = game_data.game_state
    room = gs.rooms[gs.current_room_id]
    names = [gs.npcs[n].name for n in room.npcs if n in gs.npcs]
    note(f"room={room.name} npcs={names}")
    if g.current_screen_name == "main" and names:
        d.type_text(f"Подхожу к стойке и заговариваю с {names[0]}")
        d.wait_turn("approach NPC")
        if g.current_screen_name == "main":
            d.type_text(f"Начинаю разговор с {names[0]}")
            d.wait_turn("approach NPC, second try")
    traded = False
    if g.current_screen_name == "social":
        d.shot("social")
        d.type_text("1")
        d.wait_turn("NPC reply")
        d.shot("social_reply")
        if g.current_screen_name == "trade":  # the LLM itself moved to trade
            inspect_trade(d)
            traded = True

    # Trade via the dialogue button and back (if the LLM did not open it already)
    if g.current_screen_name == "social" and not traded:
        d.click(d.social()._action_buttons[0].rect.center)
        d.pump(0.5)
        if g.current_screen_name == "trade":
            inspect_trade(d)

    # Leave the dialogue -> exploration resume with a summary
    if g.current_screen_name == "social":
        d.click(d.social()._action_buttons[2].rect.center)
        dump_chat("social chat", d.social_chat())
        d.wait_for(lambda: g.current_screen_name == "main" and d.main()._awaiting_input, 180,
                   "exploration after leaving dialogue")
        d.shot("exploration_resume")

    # Quick button
    if g.current_screen_name == "main" and d.main()._awaiting_input:
        d.click(d.main().quick_buttons[1].rect.center)
        d.wait_turn("quick button 'look'")
        d.shot("quick_look")

    dump_chat("exploration chat", d.main_chat())
    errs = errors_in(d.main_chat()) + errors_in(d.social_chat())
    note(f"agent/engine errors shown in chat: {len(errs)}")
    for e in errs:
        note(f"  {e}")


if __name__ == "__main__":
    sys.exit(run_scenario(smoke))
