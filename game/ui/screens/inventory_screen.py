"""
Inventory screen - equipment slots, inventory list, item description, coins.
"""

from __future__ import annotations

import pygame
from typing import List, Optional, Dict, Any, Union, Tuple
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from core import data as game_data
from core.entities.equipment import GameEquipment
from core.database.json_database import JsonDatabase
from localization import loc

SB_W = 12
SB_PAD = 4


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


# Slot keys and which item types they accept. Category index: "weapon", "armor". Shield = armor + index "shield".
SLOTS = [
    ("head", "inv_head", []),  # TODO: not implemented in db
    ("body", "inv_body", ["armor"]),  # exclude shield
    ("hands", "inv_hands", []),  # TODO: not implemented in db
    ("feet", "inv_feet", []),  # TODO: not implemented in db
    ("cloak", "inv_cloak", []),  # TODO: not implemented in db
    ("amulet", "inv_amulet", ["amulet"]),  # TODO: not implemented in db
    ("ring_1", "inv_ring_1", ["ring"]),
    ("ring_2", "inv_ring_2", ["ring"]),
    ("left_hand", "inv_left_hand", ["weapon", "armor"]),   # weapon or shield
    ("right_hand", "inv_right_hand", ["weapon"]),
]


def _can_equip_in_slot(item: GameEquipment, slot_key: str, categories: List[str]) -> bool:
    cat = item.category.index if item.category else ""

    # body: only armor (no shield; shield has cat "armor" and index "shield")
    if slot_key == "body":
        return cat == "armor" and (item.index or "") != "shield"

    # left_hand: shield (armor + index "shield") or weapon
    if slot_key == "left_hand":
        if cat == "weapon":
            return True
        return cat == "armor" and (item.index or "") == "shield"

    # right_hand: only weapon
    if slot_key == "right_hand":
        return cat == "weapon"

    if cat not in categories:
        return False
    return True


class InventoryScreen(BaseScreen):
    """Inventory: equipment panel, item list, description, coins. Nav + Back."""

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        self.db = JsonDatabase()
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
        self.coins_rect = pygame.Rect(w - margin - _sc(180, s), h - _sc(56, s), _sc(180, s), _sc(44, s))

        content_top = self.nav_h + _sc(12, s)
        content_h = h - content_top - _sc(64, s)
        split = w // 2
        self.equip_panel = pygame.Rect(margin, content_top, split - margin - _sc(8, s), content_h)
        self.inv_panel = pygame.Rect(split + _sc(8, s), content_top, w - split - 2 * margin, content_h)

        self._slot_rects: Dict[str, pygame.Rect] = {}
        self._hp_ac_rect: Optional[pygame.Rect] = None
        self._equip_modal_slot: Optional[str] = None
        self._equip_modal_items: List[GameEquipment] = []
        self._equip_modal_scroll = 0
        self._inv_list_scroll = 0
        self._sort_by: str = "name"  # name, price, weight
        self._selected_item: Optional[GameEquipment] = None
        self._inv_list_rect = pygame.Rect(0, 0, 0, 0)
        self._desc_rect = pygame.Rect(0, 0, 0, 0)
        self._sort_rects: Dict[str, pygame.Rect] = {}

        # Description scroll
        self._desc_scroll: int = 0

        # Drag-and-drop state
        self._drag_item: Optional[GameEquipment] = None
        self._drag_pos: Tuple[int, int] = (0, 0)
        self._drag_start_pos: Tuple[int, int] = (0, 0)
        self._drag_threshold: int = 6  # px before drag is considered started

    def _player(self):
        gs = game_data.game_state
        return gs.player if gs else None

    def _layout_slots(self) -> None:
        """Compute slot rects inside equipment panel."""
        r = self.equip_panel
        s = self._scale
        pad = _sc(8, s)
        slot_w = (r.w - 3 * pad) // 2
        slot_h = _sc(36, s)
        row_h = slot_h + pad
        # Left column: head, body, hands, feet
        x0 = r.x + pad
        x1 = r.x + pad + slot_w + pad
        y = r.y + pad
        for i, (key, loc_key, _) in enumerate(SLOTS):
            if i < 4:
                self._slot_rects[key] = pygame.Rect(x0, y + i * row_h, slot_w, slot_h)
            elif i < 8:
                self._slot_rects[key] = pygame.Rect(x1, y + (i - 4) * row_h, slot_w, slot_h)
            else:
                # left_hand, right_hand
                by = r.y + r.h - pad - slot_h - _sc(40, s) - pad
                self._slot_rects[key] = pygame.Rect(x0 if i == 8 else x1, by, slot_w, slot_h)
        self._hp_ac_rect = pygame.Rect(r.centerx - slot_w // 2, r.y + r.h - pad - _sc(36, s), slot_w, _sc(36, s))

    def _layout_inv(self) -> None:
        """Layout sort buttons, list area, description area."""
        r = self.inv_panel
        s = self._scale
        pad = _sc(8, s)
        sort_h = _sc(32, s)
        self._sort_rects["name"] = pygame.Rect(r.x + pad, r.y + pad, _sc(80, s), sort_h)
        self._sort_rects["price"] = pygame.Rect(r.x + pad + _sc(86, s), r.y + pad, _sc(80, s), sort_h)
        self._sort_rects["weight"] = pygame.Rect(r.x + pad + _sc(172, s), r.y + pad, _sc(80, s), sort_h)
        list_top = r.y + pad + sort_h + pad
        desc_h = min(_sc(180, s), r.h // 3)
        self._desc_rect = pygame.Rect(r.x + pad, r.y + r.h - pad - desc_h, r.w - 2 * pad, desc_h)
        self._inv_list_rect = pygame.Rect(r.x + pad, list_top, r.w - 2 * pad - SB_W - SB_PAD, r.h - (list_top - r.y) - pad - desc_h - pad)

    def _item_in_slot(self, slot_key: str) -> Optional[GameEquipment]:
        player = self._player()
        if not player or not getattr(player, "inventory", None):
            return None
        for it in player.inventory:
            if it is None:
                continue
            if not isinstance(it, GameEquipment):
                continue
            if slot_key in ("left_hand", "right_hand"):
                if slot_key == "left_hand" and it.equipped_left_hand:
                    return it
                if slot_key == "right_hand" and it.equipped_right_hand:
                    return it
            elif it.equipped_slot == slot_key:
                return it
        return None

    def _inventory_items(self) -> List[Tuple[GameEquipment, int]]:
        """List of (item, quantity) for display. Quantity = 1 per slot for now."""
        player = self._player()
        if not player or not getattr(player, "inventory", None):
            return []
        out: List[Tuple[GameEquipment, int]] = []
        seen: Dict[str, List[GameEquipment]] = {}
        for it in player.inventory:
            if it is None or not isinstance(it, GameEquipment):
                continue
            k = it.index
            if k not in seen:
                seen[k] = []
            seen[k].append(it)
        for k, group in seen.items():
            out.append((group[0], len(group)))
        return out

    def _sorted_inventory(self) -> List[Tuple[GameEquipment, int]]:
        items = self._inventory_items()
        if self._sort_by == "name":
            items.sort(key=lambda x: (x[0].name or "").lower())
        elif self._sort_by == "price":
            items.sort(key=lambda x: (x[0].price or 0, (x[0].name or "").lower()))
        else:
            items.sort(key=lambda x: (x[0].weight or 0, (x[0].name or "").lower()))
        return items

    def _equippable_for_slot(self, slot_key: str) -> List[GameEquipment]:
        player = self._player()
        if not player or not getattr(player, "inventory", None):
            return []
        _, _, cats = next((x for x in SLOTS if x[0] == slot_key), (None, None, []))
        if not cats:
            return []
        current = self._item_in_slot(slot_key)
        cand: List[GameEquipment] = []
        for it in player.inventory:
            if it is None or not isinstance(it, GameEquipment):
                continue
            if it is current:
                continue
            if _can_equip_in_slot(it, slot_key, cats):
                cand.append(it)
        return cand

    def _wrap_desc(self, raw_lines: list, max_w: int) -> List[str]:
        """Word-wrap description lines to fit *max_w* pixels."""
        out: List[str] = []
        for raw in (raw_lines if isinstance(raw_lines, list) else [str(raw_lines)]):
            words = str(raw or "").split()
            if not words:
                out.append("")
                continue
            cur = ""
            for w in words:
                trial = (cur + " " + w).strip() if cur else w
                if self.small_font.size(trial)[0] <= max_w:
                    cur = trial
                else:
                    if cur:
                        out.append(cur)
                    cur = w
            if cur:
                out.append(cur)
        return out or ["—"]

    def _compute_ac(self) -> int:
        player = self._player()
        if not player:
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

    def _unequip_from_slot(self, slot_key: str) -> None:
        item = self._item_in_slot(slot_key)
        if not item:
            return
        item.equipped = False
        item.equipped_left_hand = False
        item.equipped_right_hand = False
        item.equipped_slot = None

    def _clear_item_from_any_slot(self, item: GameEquipment) -> None:
        item.equipped = False
        item.equipped_left_hand = False
        item.equipped_right_hand = False
        item.equipped_slot = None

    def _equip_to_slot(self, slot_key: str, item: GameEquipment) -> None:
        self._clear_item_from_any_slot(item)
        self._unequip_from_slot(slot_key)
        if slot_key == "left_hand":
            item.equipped = True
            item.equipped_left_hand = True
        elif slot_key == "right_hand":
            item.equipped = True
            item.equipped_right_hand = True
        else:
            item.equipped = True
            item.equipped_slot = slot_key
        self._equip_modal_slot = None

    def _cancel_drag(self) -> None:
        self._drag_item = None

    def _item_at_inv_pos(self, pos: Tuple[int, int]) -> Optional[GameEquipment]:
        """Return the inventory item under screen position, or None."""
        s = self._scale
        if not self._inv_list_rect.collidepoint(pos):
            return None
        items = self._sorted_inventory()
        line_h = _sc(24, s)
        for i, (eq, _) in enumerate(items):
            ry = self._inv_list_rect.y + i * line_h - self._inv_list_scroll
            if ry <= pos[1] < ry + line_h:
                return eq
        return None

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            if self._drag_item:
                self._cancel_drag()
                return None
            if self._equip_modal_slot:
                self._equip_modal_slot = None
                return None
            return "main"

        s = self._scale
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            w, h = self._w, self._h
            if self.back_btn.is_clicked(pos):
                return "main"
            for i, key in enumerate(self.nav_keys):
                if not self.nav_buttons[i].is_clicked(pos):
                    continue
                if key == "nav_inventory":
                    return None
                if key == "nav_map":
                    return "map"
                if key == "nav_journal":
                    return "journal"
                if key == "nav_character":
                    return "character"
                if key == "nav_abilities":
                    return "abilities"
                return "main"

            if self._equip_modal_slot:
                mw, mh = _sc(400, s), _sc(300, s)
                mr = pygame.Rect(w // 2 - mw // 2, h // 2 - mh // 2, mw, mh)
                has_current = self._item_in_slot(self._equip_modal_slot) is not None
                y0 = mr.y + 50
                if has_current:
                    rr0 = pygame.Rect(mr.x + 16, y0, mr.w - 32, 24)
                    if rr0.collidepoint(pos):
                        self._unequip_from_slot(self._equip_modal_slot)
                        self._equip_modal_slot = None
                        return None
                for ii, it in enumerate(self._equip_modal_items[:12]):
                    ry = y0 + (ii + (1 if has_current else 0)) * 28
                    rr = pygame.Rect(mr.x + 16, ry, mr.w - 32, 24)
                    if rr.collidepoint(pos):
                        self._equip_to_slot(self._equip_modal_slot, it)
                        return None
                if not mr.collidepoint(pos):
                    self._equip_modal_slot = None
                return None

            self._layout_slots()
            self._layout_inv()
            if not self._player():
                return None

            # Click on slot — open modal (only when not dragging)
            for slot_key, rect in self._slot_rects.items():
                if rect.collidepoint(pos):
                    cand = self._equippable_for_slot(slot_key)
                    self._equip_modal_slot = slot_key
                    self._equip_modal_items = cand
                    self._equip_modal_scroll = 0
                    return None
            for sort_key, rect in self._sort_rects.items():
                if rect.collidepoint(pos):
                    self._sort_by = sort_key
                    return None
            # Inventory list: record drag start position; select item
            if self._inv_list_rect.collidepoint(pos):
                eq = self._item_at_inv_pos(pos)
                if eq:
                    self._selected_item = eq
                    self._desc_scroll = 0
                    self._drag_start_pos = pos
                    self._drag_item = None  # actual drag starts after threshold in MOUSEMOTION
                return None

        if event.type == pygame.MOUSEMOTION:
            if event.buttons[0] and self._drag_start_pos != (0, 0):
                dx = event.pos[0] - self._drag_start_pos[0]
                dy = event.pos[1] - self._drag_start_pos[1]
                if (dx * dx + dy * dy) >= self._drag_threshold ** 2:
                    # Threshold crossed — start drag with the item that was under the initial click
                    if self._drag_item is None and self._selected_item is not None:
                        self._drag_item = self._selected_item
            if self._drag_item:
                self._drag_pos = event.pos
            return None

        if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._drag_start_pos = (0, 0)
            if self._drag_item:
                # Attempt drop onto a slot
                self._layout_slots()
                for slot_key, rect in self._slot_rects.items():
                    if rect.collidepoint(event.pos):
                        _, _, cats = next((x for x in SLOTS if x[0] == slot_key), (None, None, []))
                        if cats and _can_equip_in_slot(self._drag_item, slot_key, cats):
                            self._equip_to_slot(slot_key, self._drag_item)
                        # If not compatible — silently cancel (no equip)
                        break
                self._cancel_drag()
            return None

        if event.type == pygame.MOUSEWHEEL:
            self._layout_inv()
            mpos = pygame.mouse.get_pos()
            step = 48
            if self._inv_list_rect.collidepoint(mpos):
                line_h = _sc(24, s)
                items = self._sorted_inventory()
                total_h = len(items) * line_h
                max_scroll = max(0, total_h - self._inv_list_rect.height)
                if event.y > 0:
                    self._inv_list_scroll = max(0, self._inv_list_scroll - step)
                else:
                    self._inv_list_scroll = min(max_scroll, self._inv_list_scroll + step)
            elif self._desc_rect.collidepoint(mpos) and self._selected_item:
                desc_line_h = _sc(20, s)
                raw = self._selected_item.desc or ["—"]
                wrapped = self._wrap_desc(raw, self._desc_rect.w - 12 - SB_W - SB_PAD)
                total_desc_h = len(wrapped) * desc_line_h
                content_h = self._desc_rect.h - _sc(26, s)  # subtract title row
                max_desc_scroll = max(0, total_desc_h - content_h)
                if event.y > 0:
                    self._desc_scroll = max(0, self._desc_scroll - step)
                else:
                    self._desc_scroll = min(max_desc_scroll, self._desc_scroll + step)
            return None

        return None

    def update(self):
        pos = pygame.mouse.get_pos()
        for b in self.nav_buttons:
            b.update(pos)
        self.back_btn.update(pos)

    def draw(self):
        """
        Draw the screen.
        
        Z-order (drawing order) to prevent overlapping:
        1. Background (screen.fill)
        2. Static UI elements (nav bar, panels)
        3. Content (lists, descriptions)
        4. Navigation buttons
        5. Modals (with overlay - draws after everything else)
        6. Tooltips (always last, always on top)
        """
        self.screen.fill(BLACK)
        s = self._scale
        w, h = self._w, self._h
        margin = _sc(16, s)
        self._layout_slots()
        self._layout_inv()
        player = self._player()

        # 1. Background is already filled with BLACK
        
        # 2. Static UI elements (nav bar)
        nav_rect = pygame.Rect(0, 0, w, self.nav_h)
        pygame.draw.rect(self.screen, DARK_GRAY, nav_rect)
        pygame.draw.line(self.screen, GOLD, (0, self.nav_h), (w, self.nav_h), 2)
        for i, b in enumerate(self.nav_buttons):
            if i == 0:
                b.custom_color = DARK_GREEN
            else:
                b.custom_color = None
            b.draw(self.screen)

        if not player:
            no_pl = self.font.render(loc["inv_no_player"], True, LIGHT_GRAY)
            nr = no_pl.get_rect(center=(w // 2, h // 2))
            self.screen.blit(no_pl, nr)
            self.back_btn.draw(self.screen)
            pygame.draw.rect(self.screen, DARK_GRAY, self.coins_rect, border_radius=6)
            pygame.draw.rect(self.screen, GOLD, self.coins_rect, width=2, border_radius=6)
            c = self.font.render(f"{loc['inv_coins']}: 0", True, GOLD)
            self.screen.blit(c, c.get_rect(center=self.coins_rect.center))
            if self._equip_modal_slot:
                self._equip_modal_slot = None
            return

        # Equipment panel
        pygame.draw.rect(self.screen, MODAL_BG, self.equip_panel, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self.equip_panel, width=2, border_radius=8)
        title = self.font.render(loc["inv_equipment"], True, GOLD)
        self.screen.blit(title, (self.equip_panel.x + _sc(8, s), self.equip_panel.y + _sc(4, s)))
        for slot_key, loc_key, _ in SLOTS:
            r = self._slot_rects.get(slot_key)
            if not r:
                continue
            pygame.draw.rect(self.screen, DARK_GRAY, r, border_radius=4)
            pygame.draw.rect(self.screen, GOLD, r, width=1, border_radius=4)
            item = self._item_in_slot(slot_key)
            label = loc[loc_key]
            if item:
                label = item.name or label
            txt = self.small_font.render(label[:20], True, WHITE)
            tr = txt.get_rect(midleft=(r.x + 6, r.centery))
            self.screen.blit(txt, tr)
        if self._hp_ac_rect:
            hp = f"{player.hit_points}/{player.max_hit_points}"
            ac = self._compute_ac()
            ha = self.small_font.render(f"{loc['inv_hp_ac']}: {hp} | {ac}", True, WHITE)
            har = ha.get_rect(center=self._hp_ac_rect.center)
            pygame.draw.rect(self.screen, INPUT_BG, self._hp_ac_rect, border_radius=4)
            self.screen.blit(ha, har)

        # Inventory panel
        pygame.draw.rect(self.screen, MODAL_BG, self.inv_panel, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self.inv_panel, width=2, border_radius=8)
        for sort_key, rect in self._sort_rects.items():
            c = GOLD if self._sort_by == sort_key else LIGHT_GRAY
            pygame.draw.rect(self.screen, DARK_GRAY, rect, border_radius=4)
            pygame.draw.rect(self.screen, c, rect, width=1, border_radius=4)
            lbl = loc["inv_sort_name"] if sort_key == "name" else (loc["inv_sort_price"] if sort_key == "price" else loc["inv_sort_weight"])
            sr = self.small_font.render(lbl, True, WHITE)
            self.screen.blit(sr, sr.get_rect(center=rect.center))
        # List
        items = self._sorted_inventory()
        line_h = _sc(24, s)
        clip = self.screen.get_clip()
        self.screen.set_clip(self._inv_list_rect)
        for i, (eq, qty) in enumerate(items):
            y = self._inv_list_rect.y + i * line_h - self._inv_list_scroll
            if y + line_h < self._inv_list_rect.y or y > self._inv_list_rect.bottom:
                continue
            sel = self._selected_item == eq
            bg = HOVER_COLOR if sel else (DARK_GRAY if i % 2 == 0 else MODAL_BG)
            pygame.draw.rect(self.screen, bg, (self._inv_list_rect.x, y, self._inv_list_rect.w, line_h))
            name = (eq.name or eq.index or "?")[:24]
            name_s = self.small_font.render(name, True, WHITE)
            self.screen.blit(name_s, (self._inv_list_rect.x + 6, y + 2))
            info = f" {eq.weight} · {qty} · {eq.price}cp"
            info_s = self.small_font.render(info, True, LIGHT_GRAY)
            self.screen.blit(info_s, (self._inv_list_rect.right - info_s.get_width() - 6, y + 2))
        self.screen.set_clip(clip)
        # Description
        pygame.draw.rect(self.screen, INPUT_BG, self._desc_rect, border_radius=4)
        pygame.draw.rect(self.screen, GOLD, self._desc_rect, width=1, border_radius=4)
        desc_title = self.small_font.render(loc["inv_description"], True, GOLD)
        self.screen.blit(desc_title, (self._desc_rect.x + 6, self._desc_rect.y + 4))
        if self._selected_item:
            title_h   = _sc(26, s)
            desc_line_h = _sc(20, s)
            text_x    = self._desc_rect.x + 6
            text_max_w = self._desc_rect.w - 12 - SB_W - SB_PAD
            content_top = self._desc_rect.y + title_h
            content_h   = self._desc_rect.h - title_h

            raw     = self._selected_item.desc or ["—"]
            wrapped = self._wrap_desc(raw, text_max_w)
            total_h = len(wrapped) * desc_line_h
            max_desc_scroll = max(0, total_h - content_h)
            self._desc_scroll = min(self._desc_scroll, max_desc_scroll)

            desc_clip = pygame.Rect(self._desc_rect.x, content_top,
                                    self._desc_rect.w, content_h)
            saved_clip = self.screen.get_clip()
            self.screen.set_clip(desc_clip)
            for i, line in enumerate(wrapped):
                yy = content_top + i * desc_line_h - self._desc_scroll
                if yy + desc_line_h < content_top or yy > self._desc_rect.bottom:
                    continue
                ls = self.small_font.render(line, True, LIGHT_GRAY)
                self.screen.blit(ls, (text_x, yy))
            self.screen.set_clip(saved_clip)

            # Scrollbar (only when content overflows)
            if max_desc_scroll > 0:
                sb_x    = self._desc_rect.right - SB_W - SB_PAD
                track   = pygame.Rect(sb_x, content_top + 2, SB_W, content_h - 4)
                vis_ratio = content_h / max(1, total_h)
                thumb_h = max(20, int(track.h * vis_ratio))
                thumb_y = track.y + int((self._desc_scroll / max_desc_scroll) * (track.h - thumb_h))
                pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=3)
                pygame.draw.rect(self.screen, GOLD,
                                 pygame.Rect(sb_x, thumb_y, SB_W, thumb_h), border_radius=3)

        # Back, coins
        self.back_btn.draw(self.screen)
        pygame.draw.rect(self.screen, DARK_GRAY, self.coins_rect, border_radius=6)
        pygame.draw.rect(self.screen, GOLD, self.coins_rect, width=2, border_radius=6)
        coins = player.coins if player else 0
        co = self.font.render(f"{loc['inv_coins']}: {coins} cp", True, GOLD)
        self.screen.blit(co, co.get_rect(center=self.coins_rect.center))

        # 5. Drag-and-drop: slot highlights + ghost item (before modal overlay)
        if self._drag_item:
            for slot_key, r in self._slot_rects.items():
                _, _, cats = next((x for x in SLOTS if x[0] == slot_key), (None, None, []))
                compatible = bool(cats) and _can_equip_in_slot(self._drag_item, slot_key, cats)
                highlight_color = (60, 180, 80) if compatible else (180, 60, 60)
                surf = pygame.Surface((r.w, r.h), pygame.SRCALPHA)
                surf.fill((*highlight_color, 80))
                self.screen.blit(surf, r.topleft)
                pygame.draw.rect(self.screen, highlight_color, r, width=2, border_radius=4)

            # Ghost label following cursor
            ghost_label = (self._drag_item.name or self._drag_item.index or "?")[:24]
            ghost_surf = self.small_font.render(ghost_label, True, WHITE)
            ghost_bg = pygame.Surface((ghost_surf.get_width() + 12, ghost_surf.get_height() + 6), pygame.SRCALPHA)
            ghost_bg.fill((30, 30, 30, 200))
            gx = self._drag_pos[0] + 14
            gy = self._drag_pos[1] - ghost_bg.get_height() // 2
            self.screen.blit(ghost_bg, (gx, gy))
            self.screen.blit(ghost_surf, (gx + 6, gy + 3))

        # 6. Modals (draw after everything else, with overlay that darkens background)
        if self._equip_modal_slot:
            mw, mh = _sc(400, s), _sc(300, s)
            mr = pygame.Rect(w // 2 - mw // 2, h // 2 - mh // 2, mw, mh)
            # Overlay must be drawn first to darken everything underneath
            overlay = pygame.Surface((w, h))
            overlay.set_alpha(180)
            overlay.fill(BLACK)
            self.screen.blit(overlay, (0, 0))
            pygame.draw.rect(self.screen, MODAL_BG, mr, border_radius=8)
            pygame.draw.rect(self.screen, GOLD, mr, width=2, border_radius=8)
            tit = self.font.render(loc["inv_equipment"], True, GOLD)
            self.screen.blit(tit, (mr.centerx - tit.get_width() // 2, mr.y + 12))
            has_current = self._item_in_slot(self._equip_modal_slot) is not None
            y0 = mr.y + 50
            if has_current:
                rr0 = pygame.Rect(mr.x + 16, y0, mr.w - 32, 24)
                pygame.draw.rect(self.screen, DARK_GRAY, rr0, border_radius=4)
                pygame.draw.rect(self.screen, GOLD, rr0, width=1, border_radius=4)
                uq = self.small_font.render(loc["inv_unequip"], True, WHITE)
                self.screen.blit(uq, (rr0.x + 6, rr0.centery - uq.get_height() // 2))
            for ii, it in enumerate(self._equip_modal_items[:12]):
                ry = y0 + (ii + (1 if has_current else 0)) * 28
                rr = pygame.Rect(mr.x + 16, ry, mr.w - 32, 24)
                pygame.draw.rect(self.screen, DARK_GRAY, rr, border_radius=4)
                pygame.draw.rect(self.screen, GOLD, rr, width=1, border_radius=4)
                ts = self.small_font.render((it.name or it.index)[:30], True, WHITE)
                self.screen.blit(ts, (rr.x + 6, rr.centery - ts.get_height() // 2))
