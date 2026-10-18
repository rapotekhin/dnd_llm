"""
Character screen - stats, HP, AC, damage, abilities, effects, spell DC.
"""

from __future__ import annotations

import pygame
from typing import List, Optional, Union, Dict, Any
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button, Tooltip

# Import BRIGHT_GOLD explicitly for level up indicator
try:
    from ..colors import BRIGHT_GOLD
except ImportError:
    BRIGHT_GOLD = (255, 215, 0)  # Fallback if not defined
from core import data as game_data
from core.entities.equipment import GameEquipment
from core.database.json_database import JsonDatabase
from core.utils.level_up_utils import can_level_up
from localization import loc

SB_W = 12
SB_PAD = 4


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


def _compute_ac(player) -> int:
    """AC from equipped GameEquipment + ac_bonus."""
    if not player or not getattr(player, "inventory", None):
        return 10
    total = 0
    for it in (player.inventory or []):
        if it is None or not isinstance(it, GameEquipment) or not it.equipped:
            continue
        if it.armor_class_base is not None:
            total += it.armor_class_base
    base = total if total > 0 else 10
    ac_bonus = getattr(player, "ac_bonus", 0) or 0
    return base + ac_bonus


class CharacterScreen(BaseScreen):
    """Character stats: HP, AC, damage, abilities, effects, spell DC. Nav + Back."""

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        s = self._scale
        w, h = self._w, self._h
        self.font = pygame.font.Font(None, _sc(26, s))
        self.small_font = pygame.font.Font(None, _sc(22, s))

        self.nav_h = _sc(48, s)
        margin = _sc(16, s)
        nav_gap = _sc(10, s)
        nw = (w - 2 * margin - 5 * nav_gap) // 5
        self.nav_buttons: List[Button] = []
        self.nav_keys = ["nav_inventory", "nav_map", "nav_journal", "nav_character", "nav_abilities"]
        for i, key in enumerate(self.nav_keys):
            x = margin + i * (nw + nav_gap)
            self.nav_buttons.append(Button(x, _sc(6, s), nw, self.nav_h - _sc(12, s), loc[key], self.font))

        self.back_btn = Button(margin, h - _sc(56, s), _sc(120, s), _sc(44, s), loc["back"], self.font)
        # Level up button (shown when level up is available)
        self.level_up_btn = Button(
            margin + _sc(130, s), h - _sc(56, s), 
            _sc(180, s), _sc(44, s), 
            loc.get("level_up_button", "Новый Уровень"), 
            self.font
        )
        content_top = self.nav_h + _sc(12, s)
        content_h = h - content_top - _sc(64, s)
        self.content_rect = pygame.Rect(margin, content_top, w - 2 * margin, content_h)
        self._scroll = 0
        self.line_h = _sc(24, s)
        self.pad = _sc(12, s)
        self.tooltip = Tooltip()
        self.db = JsonDatabase()
        self.features_cache: Dict[str, Dict[str, Any]] = {}
        self._feature_line_rects: Dict[int, str] = {}  # line_index -> feature_index (reset in _build_lines)

    def _player(self):
        gs = game_data.game_state
        return gs.player if gs else None

    def _build_lines(self) -> List[str]:
        """Build list of display lines for character stats."""
        p = self._player()
        if not p:
            return []
        lines: List[str] = []
        self._feature_line_rects = {}  # Reset feature line mapping

        def add(s: str):
            lines.append(s)

        def section(title: str):
            add("")
            add(f"—— {title} ——")
            add("")

        # Overview
        section(loc["char_details"])
        add(f"{loc['char_screen_hp']}: {p.hit_points} / {p.max_hit_points}")
        add(f"{loc['char_screen_ac']}: {_compute_ac(p)}")
        # Find equipped weapon (GameEquipment with category "weapon" in hand)
        damage_str = "—"
        if getattr(p, "inventory", None):
            for it in p.inventory:
                if it and isinstance(it, GameEquipment):
                    if it.category and it.category.index == "weapon":
                        if it.equipped_right_hand or it.equipped_left_hand:
                            if it.damage_dice_str:
                                damage_str = it.damage_dice_str
                            break
        if damage_str == "—":
            # Fallback to character.damage_dice (might be unarmed 1d2)
            try:
                dd = p.damage_dice
                bonus = getattr(dd, "bonus", 0) or 0
                dice_str = getattr(dd, "dice", str(dd))
                damage_str = dice_str + (f" +{bonus}" if bonus else "")
            except Exception:
                pass
        add(f"{loc['char_screen_damage']}: {damage_str}")
        add(f"{loc['char_screen_speed']}: {getattr(p, 'speed', 0)} ft.")
        add(f"{loc['char_screen_level']}: {p.level}")
        add(f"{loc['char_screen_xp']}: {p.xp}")
        try:
            add(f"{loc['char_screen_proficiency']}: +{p.proficiency_bonus}")
        except Exception:
            pass

        # Race / Class
        section(loc["char_info"])
        race_d = getattr(p, "race", None)
        add(f"{loc['char_screen_race']}: {race_d.name if race_d else '—'}")
        sub = getattr(p, "subrace", None)
        if sub:
            add(f"  ({sub.name})")
        ct = getattr(p, "class_type", None)
        add(f"{loc['char_screen_class']}: {ct.name if ct else '—'}")

        # Abilities
        section(loc["char_screen_abilities"])
        ab_map = [
            ("str", "ability_str"),
            ("dex", "ability_dex"),
            ("con", "ability_con"),
            ("int", "ability_int"),
            ("wis", "ability_wis"),
            ("cha", "ability_cha"),
        ]
        ab = getattr(p, "abilities", None)
        ab_mod = getattr(p, "ability_modifiers", None)
        for idx, loc_key in ab_map:
            if not ab:
                continue
            # Get ability score - try get_value_by_index first, then direct attribute
            if hasattr(ab, "get_value_by_index"):
                score = ab.get_value_by_index(idx)
            else:
                score = getattr(ab, idx, 0)
            # Get modifier - ability_modifiers already contains modifiers, not scores!
            if ab_mod and hasattr(ab_mod, "get_value_by_index"):
                # ability_modifiers.get_value_by_index returns the modifier directly
                mod = ab_mod.get_value_by_index(idx)
            elif ab_mod:
                # Fallback to direct attribute access
                mod = getattr(ab_mod, idx, 0)
            else:
                # Calculate from ability score if modifiers not available
                mod = (score - 10) // 2
            mod_str = f"+{mod}" if mod >= 0 else str(mod)
            add(f"  {loc[loc_key]}: {score} ({mod_str})")

        # Traits (racial traits)
        section(loc["char_screen_traits"])
        traits_list: List[str] = []
        race_obj = getattr(p, "race", None)
        if race_obj and hasattr(race_obj, "traits"):
            for trait in race_obj.traits:
                if trait:
                    name = getattr(trait, "name", None) or getattr(trait, "index", str(trait))
                    traits_list.append(name)
        subrace_obj = getattr(p, "subrace", None)
        if subrace_obj and hasattr(subrace_obj, "racial_traits"):
            for trait in subrace_obj.racial_traits:
                if trait:
                    name = getattr(trait, "name", None) or getattr(trait, "index", str(trait))
                    traits_list.append(name)
        if not traits_list:
            add("  —")
        else:
            for t in traits_list:
                add(f"  • {t}")

        # Proficiencies
        section(loc["char_screen_proficiencies"])
        profs = getattr(p, "proficiencies", None) or []
        if not profs:
            add("  —")
        else:
            # Group by type
            by_type: Dict[str, List[str]] = {}
            for prof in profs:
                if not prof:
                    continue
                ptype = getattr(prof, "type", None)
                if ptype:
                    type_name = getattr(ptype, "value", str(ptype))
                else:
                    type_name = "Other"
                if type_name not in by_type:
                    by_type[type_name] = []
                pname = getattr(prof, "name", None) or getattr(prof, "index", str(prof))
                by_type[type_name].append(pname)
            for ptype, names in sorted(by_type.items()):
                add(f"  {ptype}:")
                for n in sorted(names):
                    add(f"    • {n}")

        # Conditions
        section(loc["char_screen_conditions"])
        cond = getattr(p, "conditions", None) or []
        if not cond:
            add("  —")
        else:
            for c in cond:
                if c:
                    n = getattr(c, "name", None) or getattr(c, "index", str(c))
                    add(f"  • {n}")

        # Damage vulnerabilities/resistances/immunities
        dmg_vuln = getattr(p, "damage_vulnerabilities", None) or []
        if dmg_vuln:
            section(loc["char_screen_damage_vulnerabilities"])
            for v in dmg_vuln:
                add(f"  • {v}")
        
        dmg_res = getattr(p, "damage_resistances", None) or []
        if dmg_res:
            section(loc["char_screen_damage_resistances"])
            for r in dmg_res:
                add(f"  • {r}")
        
        dmg_imm = getattr(p, "damage_immunities", None) or []
        if dmg_imm:
            section(loc["char_screen_damage_immunities"])
            for i in dmg_imm:
                add(f"  • {i}")
        
        # Condition advantages/immunities
        cond_adv = getattr(p, "condition_advantages", None) or []
        if cond_adv:
            section(loc["char_screen_condition_advantages"])
            for ca in cond_adv:
                add(f"  • {ca}")
        
        cond_imm = getattr(p, "condition_immunities", None) or []
        if cond_imm:
            section(loc["char_screen_condition_immunities"])
            for ci in cond_imm:
                add(f"  • {ci}")
        
        # Senses
        senses = getattr(p, "senses", None) or {}
        if senses:
            section(loc["char_screen_senses"])
            for sense_name, sense_value in senses.items():
                # Format sense name (e.g., "darkvision" -> "Darkvision")
                sense_display = sense_name.replace("_", " ").title()
                if sense_value:
                    add(f"  • {sense_display}: {sense_value}")
                else:
                    add(f"  • {sense_display}")

        # Effects (buffs/debuffs)
        section(loc["char_screen_effects"])
        effects: List[str] = []
        if getattr(p, "hasted", False):
            effects.append("Haste")
        if getattr(p, "str_effect_modifier", -1) != -1:
            effects.append(f"Strength +{p.str_effect_modifier}")
        adv = getattr(p, "st_advantages", None) or []
        for a in adv:
            if a:
                effects.append(f"Advantage: {a}")
        if not effects:
            add("  —")
        else:
            for e in effects:
                add(f"  • {e}")

        # Features
        features = getattr(p, "features", None) or []
        if features:
            section(loc["char_screen_features"])
            for feat_index in features:
                if feat_index:
                    # Store line index for tooltip
                    line_idx = len(lines)
                    self._feature_line_rects[line_idx] = feat_index
                    # Try to get feature name
                    feat_name = feat_index
                    try:
                        if feat_index not in self.features_cache:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        feat_data = self.features_cache[feat_index]
                        feat_name = feat_data.get("name", feat_index)
                    except:
                        pass
                    add(f"  • {feat_name}")

        # Spellcasting
        if getattr(p, "is_spell_caster", False) and getattr(p, "sc", None):
            section(loc["char_screen_spell_dc"])
            try:
                add(f"  {loc['char_screen_spell_dc']}: {p.dc_value}")
            except Exception:
                add("  —")
            section(loc["char_screen_spell_slots"])
            slots = getattr(p.sc, "spell_slots", None) or []
            for i, count in enumerate(slots):
                if count > 0:
                    add(f"  Level {i + 1}: {count}")
            if not any(s > 0 for s in slots):
                add("  —")

        return lines

    def _total_height(self) -> int:
        return self.pad + len(self._build_lines()) * self.line_h

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "main"

        # Tooltip on hover for features
        if event.type == pygame.MOUSEMOTION:
            mouse_pos = event.pos
            if self.content_rect.collidepoint(mouse_pos):
                # Calculate which line is hovered
                rel_y = mouse_pos[1] - self.content_rect.y - self.pad + self._scroll
                line_idx = rel_y // self.line_h
                feat_index = self._feature_line_rects.get(line_idx)
                if feat_index:
                    # Load feature data
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {"name": feat_index, "desc": ["No description"]}
                    feat_data = self.features_cache[feat_index]
                    desc = feat_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    self.tooltip.show(feat_data.get("name", feat_index), desc, mouse_pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            if self.back_btn.is_clicked(pos):
                return "main"
            # Check level up button
            player = self._player()
            if can_level_up(player) and self.level_up_btn.is_clicked(pos):
                return "level_up"
            for i, key in enumerate(self.nav_keys):
                if not self.nav_buttons[i].is_clicked(pos):
                    continue
                if key == "nav_character":
                    return None
                if key == "nav_map":
                    return "map"
                if key == "nav_inventory":
                    return "inventory"
                if key == "nav_journal":
                    return "journal"
                if key == "nav_abilities":
                    return "abilities"
                return "main"

        if event.type == pygame.MOUSEWHEEL and self.content_rect.collidepoint(pygame.mouse.get_pos()):
            mx = max(0, self._total_height() - self.content_rect.height)
            step = 48
            if event.y > 0:
                self._scroll = max(0, self._scroll - step)
            else:
                self._scroll = min(mx, self._scroll + step)
            return None

        return None

    def update(self):
        pos = pygame.mouse.get_pos()
        # Update button hover states
        for b in self.nav_buttons:
            b.update(pos)
        self.back_btn.update(pos)
        player = self._player()
        if can_level_up(player):
            self.level_up_btn.update(pos)
        
        # Ensure custom_color is set for character button if level up is available
        player = self._player()
        can_level = can_level_up(player) if player else False
        if len(self.nav_buttons) > 3:
            if can_level:
                self.nav_buttons[3].custom_color = BRIGHT_GOLD  # type: ignore
            else:
                self.nav_buttons[3].custom_color = DARK_GREEN  # type: ignore

    def draw(self):
        """
        Draw the screen.
        
        Z-order (drawing order) to prevent overlapping:
        1. Background (screen.fill)
        2. Static UI elements (nav bar)
        3. Content (text, scrollbars)
        4. Navigation buttons
        5. Tooltips (always last, always on top)
        """
        self.screen.fill(BLACK)
        s = self._scale
        w, h = self._w, self._h
        margin = _sc(16, s)

        # 1. Background is already filled with BLACK

        # 2. Static UI elements (nav bar)
        nav_rect = pygame.Rect(0, 0, w, self.nav_h)
        pygame.draw.rect(self.screen, DARK_GRAY, nav_rect)
        pygame.draw.line(self.screen, GOLD, (0, self.nav_h), (w, self.nav_h), 2)
        player = self._player()
        can_level = can_level_up(player) if player else False
        
        # Set button colors before drawing
        for i, b in enumerate(self.nav_buttons):
            if i == 3:  # Character button (index 3 = "nav_character")
                if can_level:
                    b.custom_color = BRIGHT_GOLD  # type: ignore
                else:
                    b.custom_color = DARK_GREEN
            else:
                b.custom_color = None  # type: ignore
        
        # Draw nav buttons
        for b in self.nav_buttons:
            b.draw(self.screen)

        player = self._player()
        if not player:
            no_pl = self.font.render(loc["inv_no_player"], True, LIGHT_GRAY)
            nr = no_pl.get_rect(center=(w // 2, h // 2))
            self.screen.blit(no_pl, nr)
            self.back_btn.draw(self.screen)
            self.tooltip.draw(self.screen)
            return

        # 3. Content (draw before buttons)
        pygame.draw.rect(self.screen, MODAL_BG, self.content_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self.content_rect, width=2, border_radius=8)
        lines = self._build_lines()
        clip = self.screen.get_clip()
        self.screen.set_clip(self.content_rect)
        y = self.content_rect.y + self.pad - self._scroll
        for line in lines:
            if y + self.line_h >= self.content_rect.y and y < self.content_rect.bottom:
                is_header = line.startswith("——")
                col = GOLD if is_header else WHITE
                surf = self.small_font.render(line[:80], True, col)
                self.screen.blit(surf, (self.content_rect.x + self.pad, y))
            y += self.line_h
        self.screen.set_clip(clip)

        # Scrollbar (part of content)
        total_h = self._total_height()
        mx = max(0, total_h - self.content_rect.height)
        if mx > 0:
            track_h = self.content_rect.height - 2 * SB_PAD
            vis_ratio = self.content_rect.height / max(1, total_h)
            th = max(24, int(track_h * vis_ratio))
            ty = self.content_rect.y + SB_PAD + int((self._scroll / mx) * (track_h - th))
            rx = self.content_rect.right - SB_W - SB_PAD
            track = pygame.Rect(rx, self.content_rect.y + SB_PAD, SB_W, track_h)
            thumb = pygame.Rect(rx, ty, SB_W, th)
            pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=4)
            pygame.draw.rect(self.screen, GOLD, thumb, border_radius=4)

        # 4. Navigation buttons (draw after content)
        self.back_btn.draw(self.screen)
        player = self._player()
        if can_level_up(player):
            self.level_up_btn.draw(self.screen)
        
        # 5. Tooltip (draw last, always on top)
        self.tooltip.draw(self.screen)
