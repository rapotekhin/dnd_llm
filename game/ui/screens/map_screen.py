"""
Map screen - graph of locations (global) or rooms (current location level).
Fast travel by clicking a directly connected node.
"""

from __future__ import annotations

import math
import pygame
from typing import List, Optional, Dict, Tuple, Set
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from core import data as game_data
from core.entities.base import ID
from core.entities.location import Location, IndoorLevel, Room
from localization import loc


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class MapScreen(BaseScreen):
    """Map: graph of locations or rooms; level switcher when in rooms view; fast travel on click."""

    VIEW_LOCATIONS = "locations"
    VIEW_ROOMS = "rooms"

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

        content_top = self.nav_h + _sc(12, s)
        content_bottom = h - _sc(64, s)
        content_h = content_bottom - content_top
        btn_w = _sc(140, s)
        btn_h = _sc(40, s)
        btn_gap = _sc(8, s)
        level_btn_w = _sc(100, s)
        # Fixed right panel: two columns (level buttons | view buttons), same width in both view modes
        self._right_panel_width = level_btn_w + btn_gap + btn_w
        self._panel_left = w - margin - self._right_panel_width
        self._graph_right = self._panel_left - _sc(12, s)
        # Level buttons (left column), view buttons (right column) — positions fixed
        self.btn_level_prev = Button(self._panel_left, content_top, level_btn_w, btn_h, loc["map_level_prev"], self.small_font)
        self.btn_level_next = Button(self._panel_left, content_top + btn_h + btn_gap, level_btn_w, btn_h, loc["map_level_next"], self.small_font)
        view_btn_x = self._panel_left + level_btn_w + btn_gap
        self.btn_locations = Button(view_btn_x, content_top, btn_w, btn_h, loc["map_level_locations"], self.small_font)
        self.btn_rooms = Button(view_btn_x, content_top + btn_h + btn_gap, btn_w, btn_h, loc["map_level_rooms"], self.small_font)

        # Text area below buttons (fixed right panel)
        self._text_area_top = content_top + 2 * (btn_h + btn_gap) + _sc(6, s)
        self._text_area_rect = pygame.Rect(
            self._panel_left, self._text_area_top,
            self._right_panel_width, content_bottom - self._text_area_top
        )
        self._desc_scroll = 0
        self._desc_line_h = _sc(20, s)
        self._desc_pad = _sc(8, s)

        # NPC link rects for rooms view: list of (screen Rect, npc_id)
        self._npc_link_rects: List[Tuple[pygame.Rect, ID]] = []

        self.graph_margin = margin
        self._content_top = content_top
        self._content_h = content_h
        self.graph_rect = pygame.Rect(self.graph_margin, content_top, self._graph_right - self.graph_margin, content_h)
        self.node_radius = _sc(22, s)
        self._view_mode = self.VIEW_LOCATIONS
        self._current_level_index = 0
        self._node_positions: Dict[ID, Tuple[float, float]] = {}
        self._node_rects: Dict[ID, pygame.Rect] = {}
        self._last_click_room_node_id: Optional[ID] = None
        self._last_click_time_ms: int = 0
        self._double_click_interval_ms = 400

    def _game_state(self):
        return game_data.game_state

    def _current_location(self) -> Optional[Location]:
        gs = self._game_state()
        if not gs or not gs.current_location_id:
            return None
        return gs.locations.get(gs.current_location_id)

    def _sync_rooms_level_to_current_room(self) -> None:
        """Set _current_level_index to the level that contains current_room_id (so map opens on the right floor)."""
        loc_obj = self._current_location()
        gs = self._game_state()
        if not loc_obj or not gs or not gs.current_room_id:
            return
        cur = str(gs.current_room_id)
        for idx, lvl in enumerate(loc_obj.levels or []):
            if cur in [str(r) for r in (lvl.rooms or [])]:
                self._current_level_index = idx
                return

    def _npc_name(self, npc_id: ID) -> Optional[str]:
        """Get NPC name by id (try id and str(id) for key mismatch)."""
        gs = self._game_state()
        if not gs or not gs.npcs:
            return None
        npc = gs.npcs.get(npc_id) or gs.npcs.get(str(npc_id))
        if not npc:
            return None
        return getattr(npc, "name", None) or ""

    def _get_current_location_description_text(self) -> str:
        """Text for the right panel on locations view: current location name, description, NPC names."""
        gs = self._game_state()
        loc_obj = self._current_location()
        if not gs or not loc_obj:
            return ""
        lines: List[str] = []
        lines.append(loc_obj.name)
        if loc_obj.description:
            lines.append(loc_obj.description)
        if loc_obj.npcs:
            npc_names = []
            for npc_id in loc_obj.npcs:
                name = self._npc_name(npc_id)
                if name:
                    npc_names.append(name)
            if npc_names:
                lines.append("")
                lines.append("NPC: " + ", ".join(npc_names))
        return "\n".join(lines)

    def _get_current_room_description_text(self) -> str:
        """Text for the right panel on rooms view (without NPC names — they are rendered as links)."""
        gs = self._game_state()
        if not gs or not gs.current_room_id:
            return ""
        room = gs.rooms.get(gs.current_room_id)
        if not room:
            return ""
        loc_obj = self._current_location()
        lines: List[str] = []
        is_entrance = loc_obj and loc_obj.entrance_room_id is not None and str(loc_obj.entrance_room_id) == str(gs.current_room_id)
        if is_entrance and loc_obj:
            lines.append(loc_obj.name)
            if loc_obj.description:
                lines.append(loc_obj.description)
            lines.append("")
        lines.append(room.name)
        if room.description:
            lines.append(room.description)
        return "\n".join(lines)

    def _get_current_room_npcs(self) -> List[Tuple[ID, str]]:
        """Return list of (npc_id, npc_name) for NPCs in current room."""
        gs = self._game_state()
        if not gs or not gs.current_room_id:
            return []
        room = gs.rooms.get(gs.current_room_id)
        if not room or not room.npcs:
            return []
        result: List[Tuple[ID, str]] = []
        for npc_id in room.npcs:
            name = self._npc_name(npc_id)
            if name:
                result.append((npc_id, name))
        return result

    def _wrap_description(self, text: str, max_width: int) -> List[str]:
        """Split text into lines that fit max_width (pixels). Preserves paragraph breaks."""
        out: List[str] = []
        for para in text.split("\n"):
            para = para.strip()
            if not para:
                out.append("")
                continue
            words = para.split()
            line = ""
            for w in words:
                trial = (line + " " + w).strip() if line else w
                if self.small_font.size(trial)[0] <= max_width:
                    line = trial
                else:
                    if line:
                        out.append(line)
                    line = w
            if line:
                out.append(line)
        return out

    def _build_locations_graph(self) -> Tuple[List[ID], Set[Tuple[ID, ID]]]:
        """Nodes = location ids, edges = connected_locations (undirected)."""
        gs = self._game_state()
        if not gs or not gs.locations:
            return [], set()
        nodes = list(gs.locations.keys())
        edges: Set[Tuple[ID, ID]] = set()
        for loc_id, loc in gs.locations.items():
            for other_id in (loc.connected_locations or []):
                if other_id in gs.locations:
                    a, b = (loc_id, other_id) if str(loc_id) <= str(other_id) else (other_id, loc_id)
                    edges.add((a, b))
        return nodes, edges

    def _build_rooms_graph(self) -> Tuple[List[ID], Set[Tuple[ID, ID]]]:
        """Nodes = rooms on current level + rooms connected to them (e.g. other levels, other locations).
        Edges = Room.connections between any of these nodes. Allows travel basement <-> kitchen etc."""
        loc_obj = self._current_location()
        gs = self._game_state()
        if not gs or not loc_obj or not loc_obj.levels:
            return [], set()
        level_index = max(0, min(self._current_level_index, len(loc_obj.levels) - 1))
        self._current_level_index = level_index
        level: IndoorLevel = loc_obj.levels[level_index]
        room_ids = set(level.rooms or [])
        # Include only rooms directly connected to current level (one hop: stairs/door to other floor or location)
        for rid in list(room_ids):
            room = gs.rooms.get(rid)
            if not room or not room.connections:
                continue
            for other_id in room.connections:
                if other_id not in room_ids and gs.rooms.get(other_id):
                    room_ids.add(other_id)
        nodes = [rid for rid in room_ids if gs.rooms.get(rid)]
        edges: Set[Tuple[ID, ID]] = set()
        for rid in nodes:
            room = gs.rooms.get(rid)
            if not room or not room.connections:
                continue
            for other_id in room.connections:
                if other_id in room_ids and gs.rooms.get(other_id):
                    a, b = (rid, other_id) if str(rid) <= str(other_id) else (other_id, rid)
                    edges.add((a, b))
        return nodes, edges

    def _layout_circle(self, nodes: List[ID]) -> None:
        """Place nodes on a circle inside graph_rect."""
        self._node_positions.clear()
        self._node_rects.clear()
        if not nodes:
            return
        cx = self.graph_rect.centerx
        cy = self.graph_rect.centery
        r = min(self.graph_rect.w, self.graph_rect.h) * 0.4
        n = len(nodes)
        for i, node_id in enumerate(nodes):
            angle = 2 * math.pi * i / n - math.pi / 2
            x = cx + r * math.cos(angle)
            y = cy + r * math.sin(angle)
            self._node_positions[node_id] = (x, y)
            self._node_rects[node_id] = pygame.Rect(
                int(x - self.node_radius), int(y - self.node_radius),
                2 * self.node_radius, 2 * self.node_radius
            )

    def _get_current_node_id(self) -> Optional[ID]:
        gs = self._game_state()
        if not gs:
            return None
        if self._view_mode == self.VIEW_LOCATIONS:
            return gs.current_location_id
        return gs.current_room_id

    def _get_neighbors(self, node_id: ID) -> List[ID]:
        if self._view_mode == self.VIEW_LOCATIONS:
            _, edges = self._build_locations_graph()
            out = []
            for a, b in edges:
                if a == node_id:
                    out.append(b)
                elif b == node_id:
                    out.append(a)
            return out
        _, edges = self._build_rooms_graph()
        out = []
        for a, b in edges:
            if a == node_id:
                out.append(b)
            elif b == node_id:
                out.append(a)
        return out

    def _node_label(self, node_id: ID) -> str:
        gs = self._game_state()
        if not gs:
            return str(node_id)
        if self._view_mode == self.VIEW_LOCATIONS:
            loc_obj = gs.locations.get(node_id)
            return loc_obj.name if loc_obj else str(node_id)
        room = gs.rooms.get(node_id)
        return room.name if room else str(node_id)

    def _room_level_directions(self, room_id: ID) -> Tuple[bool, bool]:
        """Return (can_go_up, can_go_down) for this room: connected rooms on higher/lower level."""
        gs = self._game_state()
        room = gs.rooms.get(room_id) if gs else None
        if not room or not room.connections:
            return False, False
        my_level = room.level
        can_up, can_down = False, False
        for other_id in room.connections:
            other = gs.rooms.get(other_id) if gs else None
            if not other:
                continue
            if other.level > my_level:
                can_up = True
            if other.level < my_level:
                can_down = True
        return can_up, can_down

    def _perform_travel_to_location(self, location_id: ID) -> bool:
        gs = self._game_state()
        loc_obj = gs.locations.get(location_id)
        if not loc_obj:
            return False
        gs.current_location_id = location_id
        gs.current_room_id = loc_obj.entrance_room_id
        return True

    def _perform_travel_to_room(self, room_id: ID) -> bool:
        gs = self._game_state()
        room = gs.rooms.get(room_id)
        if not room:
            return False
        gs.current_room_id = room_id
        if room.location_id:
            gs.current_location_id = room.location_id
        return True

    def handle_event(self, event: pygame.event.Event):
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "main"

        if event.type == pygame.MOUSEWHEEL:
            if self._text_area_rect.collidepoint(pygame.mouse.get_pos()):
                step = self._desc_line_h * 2
                if event.y > 0:
                    self._desc_scroll = max(0, self._desc_scroll - step)
                else:
                    desc_text = (
                        self._get_current_location_description_text()
                        if self._view_mode == self.VIEW_LOCATIONS
                        else self._get_current_room_description_text()
                    )
                    if desc_text:
                        wrap_w = max(1, self._text_area_rect.w - 2 * self._desc_pad)
                        lines = self._wrap_description(desc_text, wrap_w)
                        total_h = len(lines) * self._desc_line_h
                        max_scroll = max(0, total_h - (self._text_area_rect.h - 2 * self._desc_pad))
                        self._desc_scroll = min(max_scroll, self._desc_scroll + step)
            return None

        if event.type == pygame.MOUSEBUTTONDOWN and event.button != 1:
            return None

        pos = event.pos if event.type == pygame.MOUSEBUTTONDOWN else None
        if not pos:
            return None

        if self.back_btn.is_clicked(pos):
            return "main"

        # Level / view buttons
        if self.btn_locations.is_clicked(pos):
            self._view_mode = self.VIEW_LOCATIONS
            self._desc_scroll = 0
            return None
        if self.btn_rooms.is_clicked(pos):
            self._view_mode = self.VIEW_ROOMS
            self._desc_scroll = 0
            return None
        if self._view_mode == self.VIEW_ROOMS:
            # Upper button = go up (next level), lower button = go down (prev level)
            if self.btn_level_prev.is_clicked(pos):
                loc_obj = self._current_location()
                if loc_obj and loc_obj.levels and self._current_level_index < len(loc_obj.levels) - 1:
                    self._current_level_index += 1
                return None
            if self.btn_level_next.is_clicked(pos):
                if self._current_level_index > 0:
                    self._current_level_index -= 1
                return None

        # Nav
        for i, key in enumerate(self.nav_keys):
            if self.nav_buttons[i].is_clicked(pos):
                if key == "nav_map":
                    return None
                if key == "nav_inventory":
                    return "inventory"
                if key == "nav_journal":
                    return "journal"
                if key == "nav_character":
                    return "character"
                if key == "nav_abilities":
                    return "abilities"
                return "main"

        # NPC link clicks in rooms view right panel
        if self._view_mode == self.VIEW_ROOMS:
            for rect, npc_id in self._npc_link_rects:
                if rect.collidepoint(pos):
                    return f"social:{npc_id}"

        # Graph click: fast travel if clicked node is direct neighbor of current; double-click current room = switch level to that room's floor
        if self.graph_rect.collidepoint(pos):
            current_id = self._get_current_node_id()
            now_ms = pygame.time.get_ticks()
            for node_id, rect in self._node_rects.items():
                if not rect.collidepoint(pos):
                    continue
                # Click on current room (rooms view): double-click switches map level to this room's floor
                if self._view_mode == self.VIEW_ROOMS and current_id is not None and str(node_id) == str(current_id):
                    if (self._last_click_room_node_id is not None and str(self._last_click_room_node_id) == str(node_id)
                            and (now_ms - self._last_click_time_ms) < self._double_click_interval_ms):
                        self._sync_rooms_level_to_current_room()
                        self._last_click_room_node_id = None
                    else:
                        self._last_click_room_node_id = node_id
                        self._last_click_time_ms = now_ms
                    return None
                self._last_click_room_node_id = None
                neighbors = self._get_neighbors(current_id) if current_id else []
                neighbors_str = {str(n) for n in neighbors}
                if str(node_id) != str(current_id) and str(node_id) not in neighbors_str:
                    return None
                if str(node_id) == str(current_id):
                    return None
                if self._view_mode == self.VIEW_LOCATIONS:
                    self._perform_travel_to_location(node_id)
                else:
                    self._perform_travel_to_room(node_id)
                return None

        return None

    def update(self):
        pos = pygame.mouse.get_pos()
        self.back_btn.update(pos)
        self.btn_locations.update(pos)
        self.btn_rooms.update(pos)
        self.btn_level_prev.update(pos)
        self.btn_level_next.update(pos)
        for b in self.nav_buttons:
            b.update(pos)

    def draw(self):
        self.screen.fill(BLACK)

        nav_rect = pygame.Rect(0, 0, self._w, self.nav_h)
        pygame.draw.rect(self.screen, DARK_GRAY, nav_rect)
        pygame.draw.line(self.screen, GOLD, (0, self.nav_h), (self._w, self.nav_h), 2)
        for b in self.nav_buttons:
            b.draw(self.screen)
        self.back_btn.draw(self.screen)

        # Fixed right panel: buttons (level column + view column)
        self.btn_locations.draw(self.screen)
        self.btn_rooms.draw(self.screen)
        self.btn_level_prev.draw(self.screen)
        self.btn_level_next.draw(self.screen)

        # Graph area — fixed width, same in both view modes
        self.graph_rect = pygame.Rect(
            self.graph_margin, self._content_top,
            self._graph_right - self.graph_margin, self._content_h
        )
        pygame.draw.rect(self.screen, MODAL_BG, self.graph_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self.graph_rect, width=2, border_radius=8)

        if self._view_mode == self.VIEW_LOCATIONS:
            nodes, edges = self._build_locations_graph()
        else:
            self._sync_rooms_level_to_current_room()
            nodes, edges = self._build_rooms_graph()

        self._layout_circle(nodes)
        current_id = self._get_current_node_id()

        # Edges
        for (a, b) in edges:
            if a not in self._node_positions or b not in self._node_positions:
                continue
            x1, y1 = self._node_positions[a]
            x2, y2 = self._node_positions[b]
            pygame.draw.line(self.screen, LIGHT_GRAY, (int(x1), int(y1)), (int(x2), int(y2)), 2)

        # Nodes (compare IDs as strings so current room/location highlights correctly)
        current_id_str = str(current_id) if current_id else None
        gs = self._game_state()
        current_loc_id_str = str(gs.current_location_id) if (gs and gs.current_location_id) else None
        for node_id in nodes:
            if node_id not in self._node_positions:
                continue
            x, y = self._node_positions[node_id]
            is_current = current_id_str is not None and str(node_id) == current_id_str
            # Rooms of another location (on rooms view) — blue
            is_other_location = False
            if self._view_mode == self.VIEW_ROOMS and gs:
                room = gs.rooms.get(node_id)
                if room and room.location_id is not None and current_loc_id_str is not None:
                    if str(room.location_id) != current_loc_id_str:
                        is_other_location = True
            if is_current:
                color = DARK_RED
            elif is_other_location:
                color = DARK_BLUE
            else:
                color = DARK_GRAY
            pygame.draw.circle(self.screen, color, (int(x), int(y)), self.node_radius, 0)
            border_w = 4 if is_current else 2
            pygame.draw.circle(self.screen, GOLD, (int(x), int(y)), self.node_radius, border_w)
            label = self._node_label(node_id)
            if len(label) > 12:
                label = label[:10] + "…"
            surf = self.small_font.render(label, True, WHITE)
            r = surf.get_rect(center=(int(x), int(y)))
            self.screen.blit(surf, r)
            # On rooms view: arrows to the right if this room connects to other levels
            if self._view_mode == self.VIEW_ROOMS:
                can_up, can_down = self._room_level_directions(node_id)
                arrow_x = int(x) + self.node_radius + _sc(6, self._scale)
                arrow_color = GOLD
                if can_up:
                    up_surf = self.small_font.render("↑", True, arrow_color)
                    self.screen.blit(up_surf, (arrow_x, int(y) - up_surf.get_height() - 1))
                if can_down:
                    down_surf = self.small_font.render("↓", True, arrow_color)
                    self.screen.blit(down_surf, (arrow_x, int(y) + 1))

        # Right panel text area (below buttons) — locations: current location; rooms: current room
        pygame.draw.rect(self.screen, MODAL_BG, self._text_area_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self._text_area_rect, width=2, border_radius=8)
        self._npc_link_rects = []  # reset every frame

        if self._view_mode == self.VIEW_LOCATIONS:
            desc_text = self._get_current_location_description_text()
            room_npcs: List[Tuple[ID, str]] = []
        else:
            desc_text = self._get_current_room_description_text()
            room_npcs = self._get_current_room_npcs()

        # Build all lines: desc lines + empty line + "NPC:" header + one line per NPC
        wrap_w = max(1, self._text_area_rect.w - 2 * self._desc_pad)
        desc_lines = self._wrap_description(desc_text, wrap_w) if desc_text else []
        npc_line_start = len(desc_lines)
        if room_npcs:
            desc_lines.append("")
            desc_lines.append("NPC:")
            npc_line_start = len(desc_lines)
            for _, name in room_npcs:
                desc_lines.append(f"  {name}")

        total_h = len(desc_lines) * self._desc_line_h
        max_scroll = max(0, total_h - (self._text_area_rect.h - 2 * self._desc_pad))
        self._desc_scroll = min(max_scroll, self._desc_scroll)

        clip_save = self.screen.get_clip()
        self.screen.set_clip(self._text_area_rect)
        y = self._text_area_rect.y + self._desc_pad - self._desc_scroll
        npc_render_idx = 0
        for i, line in enumerate(desc_lines):
            if y + self._desc_line_h > self._text_area_rect.y and y < self._text_area_rect.bottom:
                is_npc_name = room_npcs and i >= npc_line_start and npc_render_idx < len(room_npcs)
                if is_npc_name:
                    color = BRIGHT_GOLD
                    surf = self.small_font.render(line, True, color)
                    self.screen.blit(surf, (self._text_area_rect.x + self._desc_pad, y))
                    # Underline (hyperlink style)
                    uy = y + surf.get_height() - 1
                    pygame.draw.line(
                        self.screen, BRIGHT_GOLD,
                        (self._text_area_rect.x + self._desc_pad, uy),
                        (self._text_area_rect.x + self._desc_pad + surf.get_width(), uy),
                        1,
                    )
                    # Store clickable rect
                    npc_id, _ = room_npcs[npc_render_idx]
                    link_rect = pygame.Rect(
                        self._text_area_rect.x + self._desc_pad, y,
                        surf.get_width(), surf.get_height()
                    )
                    self._npc_link_rects.append((link_rect, npc_id))
                    npc_render_idx += 1
                else:
                    surf = self.small_font.render(line, True, LIGHT_GRAY)
                    self.screen.blit(surf, (self._text_area_rect.x + self._desc_pad, y))
            elif room_npcs and i >= npc_line_start and npc_render_idx < len(room_npcs):
                # Line is scrolled out of view — still advance index to keep npc_id mapping correct
                npc_render_idx += 1
            y += self._desc_line_h
        self.screen.set_clip(clip_save)
