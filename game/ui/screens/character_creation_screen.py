"""
Character Creation Screen - Multi-step character builder
"""

import pygame
from typing import List, Dict, Any, Optional, Union
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button, InputModal, Tooltip
from ..controls import Dropdown, Toggle
from core.entities.character import Character
from core.database.json_database import JsonDatabase
from core.character_builder import CharacterBuild
from localization import loc
from generators.fantasy_name_generator_base import fantasy_name_generator


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class AbilityCounter:
    """Counter widget for ability scores"""
    
    def __init__(self, x: int, y: int, ability: str, label: str, font: pygame.font.Font):
        self.x = x
        self.y = y
        self.ability = ability
        self.label = label
        self.font = font
        self.small_font = pygame.font.Font(None, 24)
        
        # Buttons
        btn_size = 30
        self.minus_rect = pygame.Rect(x + 100, y, btn_size, btn_size)
        self.plus_rect = pygame.Rect(x + 180, y, btn_size, btn_size)
        self.value_rect = pygame.Rect(x + 135, y, 40, btn_size)
        
    def draw(self, surface: pygame.Surface, value: int, modifier: int, can_increase: bool, can_decrease: bool):
        """Draw the counter"""
        # Label
        label_surface = self.font.render(self.label, True, WHITE)
        surface.blit(label_surface, (self.x, self.y + 5))
        
        # Minus button
        minus_color = GOLD if can_decrease else DARK_GRAY
        pygame.draw.rect(surface, DARK_GRAY, self.minus_rect, border_radius=4)
        pygame.draw.rect(surface, minus_color, self.minus_rect, width=2, border_radius=4)
        minus_text = self.font.render("-", True, minus_color)
        surface.blit(minus_text, (self.minus_rect.centerx - 5, self.minus_rect.centery - 10))
        
        # Value
        pygame.draw.rect(surface, INPUT_BG, self.value_rect, border_radius=4)
        value_text = self.font.render(str(value), True, WHITE)
        value_rect = value_text.get_rect(center=self.value_rect.center)
        surface.blit(value_text, value_rect)
        
        # Plus button
        plus_color = GOLD if can_increase else DARK_GRAY
        pygame.draw.rect(surface, DARK_GRAY, self.plus_rect, border_radius=4)
        pygame.draw.rect(surface, plus_color, self.plus_rect, width=2, border_radius=4)
        plus_text = self.font.render("+", True, plus_color)
        surface.blit(plus_text, (self.plus_rect.centerx - 5, self.plus_rect.centery - 10))
        
        # Modifier
        mod_str = f"+{modifier}" if modifier >= 0 else str(modifier)
        mod_color = DARK_GREEN if modifier > 0 else (DARK_RED if modifier < 0 else LIGHT_GRAY)
        mod_surface = self.font.render(f"({mod_str})", True, mod_color)
        surface.blit(mod_surface, (self.plus_rect.right + 10, self.y + 5))
        
    def handle_click(self, pos: tuple) -> Optional[str]:
        """Handle click, return 'increase' or 'decrease' or None"""
        if self.minus_rect.collidepoint(pos):
            return "decrease"
        if self.plus_rect.collidepoint(pos):
            return "increase"
        return None


class SelectionList:
    """Scrollable selection list with optional scrollbar and highlighted items"""
    
    SCROLLBAR_WIDTH = 12
    SCROLLBAR_PAD = 4
    
    def __init__(self, x: int, y: int, width: int, height: int, font: pygame.font.Font):
        self.rect = pygame.Rect(x, y, width, height)
        self.font = font
        self.items: List[Dict[str, Any]] = []
        self.selected_index: int = -1
        self.scroll_offset: int = 0
        self.item_height = 40
        self.hovered_index = -1
        self.selected_indices: Optional[set] = None  # set of item["index"] to highlight (e.g. chosen cantrips)
        self._scroll_dragging = False
        self._last_items_key: Optional[tuple] = None
        
    def set_items(self, items: List[Dict[str, Any]]):
        """Set list items. Preserves scroll if same items."""
        key = tuple((it.get("index", ""), it.get("name", "")) for it in items) if items else ()
        if key == self._last_items_key:
            return
        self._last_items_key = key
        self.items = items
        self.selected_index = -1
        self.scroll_offset = 0
        
    def get_selected(self) -> Optional[Dict[str, Any]]:
        """Get selected item"""
        if 0 <= self.selected_index < len(self.items):
            return self.items[self.selected_index]
        return None
        
    def get_item_at_pos(self, pos: tuple) -> Optional[Dict[str, Any]]:
        """Get item at screen position (for click-to-toggle)."""
        if not self.rect.collidepoint(pos):
            return None
        rel_y = pos[1] - self.rect.y + self.scroll_offset
        i = rel_y // self.item_height
        if 0 <= i < len(self.items):
            return self.items[i]
        return None
        
    def _max_scroll(self) -> int:
        return max(0, len(self.items) * self.item_height - self.rect.height)
        
    def _is_in_scrollbar(self, pos: tuple) -> bool:
        """True if pos is in the scrollbar strip (don't treat as item click)."""
        if self._max_scroll() <= 0:
            return False
        bar_left = self.rect.right - self.SCROLLBAR_WIDTH - self.SCROLLBAR_PAD
        return pos[0] >= bar_left
        
    def handle_event(self, event: pygame.event.Event) -> bool:
        """Handle events. Returns True if an item was clicked (for toggle)."""
        if event.type == pygame.MOUSEBUTTONDOWN:
            if event.button == 1:
                if self.rect.collidepoint(event.pos):
                    if self._is_in_scrollbar(event.pos):
                        tr, th = self._scrollbar_rects()
                        if th and th.collidepoint(event.pos):
                            self._scroll_dragging = True
                        return False
                    rel_y = event.pos[1] - self.rect.y + self.scroll_offset
                    idx = rel_y // self.item_height
                    if 0 <= idx < len(self.items):
                        self.selected_index = idx
                        return True
                self._scroll_dragging = False
            elif event.button in (4, 5) and self.rect.collidepoint(event.pos):
                mx = self._max_scroll()
                if mx > 0:
                    if event.button == 4:
                        self.scroll_offset = max(0, self.scroll_offset - 24)
                    else:
                        self.scroll_offset = min(mx, self.scroll_offset + 24)
        elif event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._scroll_dragging = False
        elif event.type == pygame.MOUSEMOTION:
            if self._scroll_dragging:
                mx = self._max_scroll()
                if mx > 0:
                    track, thumb = self._scrollbar_rects()
                    if track and thumb:
                        rel = event.pos[1] - track.y
                        t = max(0, min(1, rel / (track.height - thumb.height))) if track.height > thumb.height else 0
                        self.scroll_offset = int(t * mx)
            elif self.rect.collidepoint(event.pos):
                rel_y = event.pos[1] - self.rect.y + self.scroll_offset
                self.hovered_index = rel_y // self.item_height
                if self.hovered_index < 0 or self.hovered_index >= len(self.items):
                    self.hovered_index = -1
            else:
                self.hovered_index = -1
        return False
        
    def _scrollbar_rects(self) -> tuple:
        """(track_rect, thumb_rect). Thumb None if no scroll."""
        mx = self._max_scroll()
        if mx <= 0:
            return (None, None)
        rx = self.rect.right - self.SCROLLBAR_WIDTH - self.SCROLLBAR_PAD
        track = pygame.Rect(rx, self.rect.y + self.SCROLLBAR_PAD, self.SCROLLBAR_WIDTH,
                            self.rect.height - 2 * self.SCROLLBAR_PAD)
        visible = self.rect.height / max(1, len(self.items) * self.item_height)
        thumb_h = max(24, int(track.height * visible))
        thumb_y = track.y + int((self.scroll_offset / mx) * (track.height - thumb_h))
        thumb = pygame.Rect(rx, thumb_y, self.SCROLLBAR_WIDTH, thumb_h)
        return (track, thumb)
        
    def draw(self, surface: pygame.Surface):
        """Draw the list. Uses selected_indices for extra highlight (e.g. chosen cantrips)."""
        pygame.draw.rect(surface, MODAL_BG, self.rect, border_radius=8)
        pygame.draw.rect(surface, GOLD, self.rect, width=2, border_radius=8)
        
        list_width = self.rect.width
        has_scroll = self._max_scroll() > 0
        if has_scroll:
            list_width -= self.SCROLLBAR_WIDTH + 2 * self.SCROLLBAR_PAD
        
        clip_rect = surface.get_clip()
        surface.set_clip(self.rect)
        
        for i, item in enumerate(self.items):
            y = self.rect.y + i * self.item_height - self.scroll_offset
            if y + self.item_height < self.rect.y or y > self.rect.bottom:
                continue
            item_rect = pygame.Rect(self.rect.x + 5, y + 2, list_width - 10, self.item_height - 4)
            is_sel = self.selected_indices and item.get("index") in self.selected_indices
            if i == self.selected_index:
                pygame.draw.rect(surface, DARK_GREEN, item_rect, border_radius=4)
            elif is_sel:
                pygame.draw.rect(surface, (80, 60, 20), item_rect, border_radius=4)
                pygame.draw.rect(surface, GOLD, item_rect, width=1, border_radius=4)
            elif i == self.hovered_index:
                pygame.draw.rect(surface, HOVER_COLOR, item_rect, border_radius=4)
            name = item.get("name", str(item))
            text_surface = self.font.render(name, True, GOLD if is_sel else WHITE)
            surface.blit(text_surface, (item_rect.x + 10, item_rect.centery - 10))
            
        surface.set_clip(clip_rect)
        
        if has_scroll:
            track, thumb = self._scrollbar_rects()
            if track and thumb:
                pygame.draw.rect(surface, DARK_GRAY, track, border_radius=4)
                pygame.draw.rect(surface, GOLD, thumb, border_radius=4)


class CharacterCreationScreen(BaseScreen):
    """Character creation with multiple steps"""
    
    STEPS = [
        "biography",      # 0: Name, Alignment
        "race",           # 1: Race selection
        "subrace",        # 2: Subrace (if available)
        "class",          # 3: Class selection
        "subclass",       # 4: Subclass (if available)
        "cantrips",       # 5: Cantrips (if spellcaster)
        "spells",         # 6: Spells (if spellcaster)
        "prepared",       # 7: Prepared spells
        "background",     # 8: Background
        "abilities",      # 9: Ability scores
        "proficiency_choices",  # 10: Class proficiency choices (skills, etc.)
    ]
    
    @staticmethod
    def _get_step_names() -> Dict[str, str]:
        """Get localized step names"""
        return {
            "biography": loc["step_biography"],
            "race": loc["step_race"],
            "subrace": loc["step_subrace"],
            "class": loc["step_class"],
            "features": loc["step_features"],
            "subclass": loc["step_subclass"],
            "cantrips": loc["step_cantrips"],
            "spells": loc["step_spells"],
            "prepared": loc["step_prepared"],
            "background": loc["step_background"],
            "abilities": loc["step_abilities"],
            "proficiency_choices": loc["step_proficiency_choices"],
            "confirmation": loc["step_confirmation"],
        }
    
    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        s = self._scale
        self.db = JsonDatabase()
        self.build = CharacterBuild()
        self.current_step = 0
        
        self.title_font = pygame.font.Font(None, _sc(56, s))
        self.header_font = pygame.font.Font(None, _sc(42, s))
        self.font = pygame.font.Font(None, _sc(32, s))
        self.small_font = pygame.font.Font(None, _sc(26, s))
        
        self._load_data()
        self._create_ui()
        
    def _load_data(self):
        """Load all necessary data from database"""
        # Alignments
        alignments_data = self.db.get("/alignments.json")
        self.alignments = alignments_data.get("results", [])
        self.alignment_data: Optional[Dict[str, Any]] = None
        
        # Races
        races_data = self.db.get("/races.json")
        self.races = races_data.get("results", [])
        
        # Classes
        classes_data = self.db.get("/classes.json")
        self.classes = classes_data.get("results", [])
        
        # Backgrounds
        backgrounds_data = self.db.get("/backgrounds.json")
        self.backgrounds = backgrounds_data.get("results", [])
        
        # Traits cache for tooltips
        self.traits_cache: Dict[str, Dict[str, Any]] = {}
        # Spell cache for cantrip/spell tooltips
        self.spell_cache: Dict[str, Dict[str, Any]] = {}
        # Proficiency cache for proficiency_choices tooltips
        self.proficiency_cache: Dict[str, str] = {}
        
        # Ability scores
        self.ability_labels = {
            "str": loc["ability_str"],
            "dex": loc["ability_dex"],
            "con": loc["ability_con"],
            "int": loc["ability_int"],
            "wis": loc["ability_wis"],
            "cha": loc["ability_cha"],
        }
        
    def _create_ui(self):
        """Create UI components"""
        s = self._scale
        w, h = self._w, self._h
        bw, bh = _sc(150, s), _sc(50, s)
        btn_y = h - _sc(70, s)
        self.prev_btn = Button(
            _sc(50, s), btn_y, bw, bh,
            f"< {loc['back']}", self.font
        )
        self.next_btn = Button(
            w - _sc(200, s), btn_y, bw, bh,
            f"{loc['next']} >", self.font
        )
        self.finish_btn = Button(
            w - _sc(200, s), btn_y, bw, bh,
            loc["finish"], self.font
        )
        
        self.tooltip = Tooltip(max_width=_sc(350, s))
        
        # Trait rects for hover detection (filled when drawing race)
        self.trait_rects: List[tuple] = []  # [(rect, trait_index), ...]
        
        # Confirmation screen scroll
        self.confirmation_scroll_offset = 0
        self._confirmation_scroll_dragging = False
        self._confirmation_scroll_start_y = 0
        self._confirmation_panel_rect: Optional[pygame.Rect] = None
        
        # Step-specific UI
        self._create_biography_ui()
        self._create_race_ui()
        self._create_class_ui()
        self._create_background_ui()
        self._create_abilities_ui()
        
    def _create_biography_ui(self):
        """Create biography step UI"""
        self.name_input_rect = pygame.Rect(100, 178, 350, 42)
        self.name_input_active = False
        self.random_name_btn = Button(
            460, 176, 200, 46,
            loc["random_name"],
            self.font
        )
        self.gender_male_btn = Button(100, 238, 120, 36, loc["gender_male"], self.small_font)
        self.gender_female_btn = Button(230, 238, 120, 36, loc["gender_female"], self.small_font)
        self.age_input_rect = pygame.Rect(100, 292, 80, 36)
        self.age_input_active = False
        self.bio_age_buffer = ""
        self.weight_input_rect = pygame.Rect(220, 292, 80, 36)
        self.weight_input_active = False
        self.bio_weight_buffer = ""
        self.alignment_list = SelectionList(100, 348, 350, 320, self.font)
        self.alignment_list.set_items(self.alignments)
        
    def _create_race_ui(self):
        """Create race step UI"""
        self.race_list = SelectionList(100, 150, 350, 450, self.font)
        self.race_list.set_items(self.races)
        
        self.subrace_list = SelectionList(100, 150, 350, 450, self.font)
        
    def _create_class_ui(self):
        """Create class step UI"""
        self.class_list = SelectionList(100, 150, 350, 450, self.font)
        self.class_list.set_items(self.classes)
        
        self.spell_list = SelectionList(500, 150, 350, 300, self.font)
        self.selected_spells_list = SelectionList(500, 470, 350, 150, self.font)
        
    def _create_background_ui(self):
        """Create background step UI"""
        self.background_list = SelectionList(100, 150, 350, 450, self.font)
        self.background_list.set_items(self.backgrounds)
        
    def _create_abilities_ui(self):
        """Create abilities step UI"""
        self.ability_counters = {}
        y = 180
        for ability, label in self.ability_labels.items():
            self.ability_counters[ability] = AbilityCounter(150, y, ability, label, self.font)
            y += 50
            
    def _get_visible_steps(self) -> List[str]:
        """Get list of visible steps based on current choices"""
        steps = ["race"]
        
        # Check for subrace
        if self.build.race_data:
            subraces = self.build.race_data.get("subraces", [])
            if subraces:
                steps.append("subrace")
                
        steps.append("class")
        
        # Features step (always show after class selection)
        if self.build.class_type:
            steps.append("features")
        
        # Check for subclass at level 1 (most don't have it)
        # For now, skip subclass
        
        # Check for spellcasting
        if self.build.class_data:
            spellcasting = self.build.class_data.get("spellcasting")
            if spellcasting:
                # Load cantrips/spells info
                class_index = self.build.class_type
                try:
                    level_data = self.db.get(f"/classes/{class_index}/levels/1.json")
                    spellcasting_info = level_data.get("spellcasting", {})
                    
                    cantrips = spellcasting_info.get("cantrips_known", 0)
                    if cantrips > 0:
                        self.build.cantrips_known = cantrips
                        steps.append("cantrips")
                        
                    spells = spellcasting_info.get("spells_known", 0)
                    if spells > 0:
                        self.build.spells_known = spells
                        steps.append("spells")
                except:
                    pass
                    
        steps.extend(["background", "abilities"])
        
        # Proficiency choices (after abilities) if class has any
        if self.build.class_data:
            choices = self.build.class_data.get("proficiency_choices", [])
            for c in choices:
                opts = c.get("from", {}).get("options", [])
                if opts and c.get("choose", 0) > 0:
                    steps.append("proficiency_choices")
                    break
        
        # Biography (name + alignment) just before confirmation
        steps.append("biography")
        steps.append("confirmation")
        
        return steps

    # FantasyNameGenerator.DnD race index -> generator class name
    _FNG_RACE_MAP = {
        "human": "Human",
        "elf": "Elf",
        "dwarf": "Dwarf",
        "halfling": "Halfling",
        "dragonborn": "Dragonborn",
        "half-elf": "HalfElf",
        "half-orc": "HalfOrc",
        "gnome": "Gnome",
        "tiefling": "Tiefling",
        "orc": "Orc",
        "goliath": "Goliath",
        "drow": "Drow",
        "goblin": "Goblin",
        "hobgoblin": "Hobgoblin",
        "kenku": "Kenku",
        "kobold": "Kobold",
        "lizardfolk": "Lizardfolk",
        "aasimer": "Aasimer",
        "firbolg": "Firbolg",
        "genasi": "Genasi",
        "gith": "Gith",
        "tabaxi": "Tabaxi",
        "triton": "Triton",
        "warforged": "Warforged",
        "yuan-ti": "YuanTi",
    }

    def _generate_random_name(self) -> Optional[str]:
        """Generate a random fantasy name via FantasyNameGenerator, based on selected race."""
        try:
            import FantasyNameGenerator.DnD as DnD
        except ImportError:
            return None
        race = (self.build.race or "human").lower().strip()
        gen_name = self._FNG_RACE_MAP.get(race, "Human")
        try:
            gen = getattr(DnD, gen_name, None)
            if gen is None:
                gen = DnD.Human
            return str(gen())
        except Exception:
            try:
                return str(DnD.Human())
            except Exception:
                return None
        
    def _load_race_details(self, race_index: str):
        """Load detailed race data"""
        try:
            self.build.race_data = self.db.get(f"/races/{race_index}.json")
            self.build.race = race_index
            
            # Update subrace list
            subraces = self.build.race_data.get("subraces", [])
            self.subrace_list.set_items(subraces)
        except Exception as e:
            print(f"Error loading race: {e}")
            
    def _load_class_details(self, class_index: str):
        """Load detailed class data"""
        try:
            self.build.class_data = self.db.get(f"/classes/{class_index}.json")
            self.build.class_type = class_index
            self.build.proficiency_choices_selected = []
            self.build.proficiency_choose = 0
            self.proficiency_options: List[Dict[str, Any]] = []
            self.build.features = []
            self.build.feature_choices = {}
            self.features_list: List[Dict[str, Any]] = []
            self.feature_rects: List[tuple] = []  # (rect, feature_index)
            self.features_cache: Dict[str, Dict[str, Any]] = {}
            self._subfeature_modal_active = False
            self._subfeature_modal_feature: Optional[str] = None
            self._subfeature_modal_options: List[Dict[str, Any]] = []
            self._subfeature_modal_choose = 1
            self._subfeature_modal_selected: List[str] = []
            
            # Load level 1 features
            try:
                level_data = self.db.get(f"/classes/{class_index}/levels/1.json")
                features_data = level_data.get("features", [])
                self.features_list = features_data
                # Initialize features list (will be updated when subfeatures chosen)
                self.build.features = [f.get("index", "") for f in features_data if f.get("index")]
            except Exception:
                self.features_list = []
                self.build.features = []
            
            # Load spells if spellcaster
            if self.build.class_data.get("spellcasting"):
                try:
                    spells_data = self.db.get(f"/classes/{class_index}/spells.json")
                    spells = spells_data.get("results", [])
                    
                    # Separate cantrips and level 1 spells
                    self.cantrips = [s for s in spells if s.get("level", 1) == 0]
                    self.level_1_spells = [s for s in spells if s.get("level", 1) == 1]
                    
                    self.spell_list.set_items(self.cantrips)
                except Exception:
                    self.cantrips = []
                    self.level_1_spells = []
            
            # First proficiency_choice (skills, etc.)
            choices = self.build.class_data.get("proficiency_choices", [])
            for c in choices:
                opts = c.get("from", {}).get("options", [])
                if opts and c.get("choose", 0) > 0:
                    self.build.proficiency_choose = c.get("choose", 0)
                    self.proficiency_options = []
                    for o in opts:
                        item = o.get("item") if isinstance(o.get("item"), dict) else None
                        if item:
                            self.proficiency_options.append({"index": item.get("index"), "name": item.get("name", "")})
                    break
        except Exception as e:
            print(f"Error loading class: {e}")
            
    def _load_background_details(self, bg_index: str):
        """Load detailed background data"""
        try:
            self.build.background_data = self.db.get(f"/backgrounds/{bg_index}.json")
            self.build.background = bg_index
        except Exception as e:
            print(f"Error loading background: {e}")
            
    def _format_spell_tooltip(self, data: Dict[str, Any]) -> str:
        """Build tooltip text from spell JSON: desc, range, components, duration, etc."""
        parts: List[str] = []
        desc = data.get("desc", [])
        if isinstance(desc, list):
            desc = " ".join(desc)
        if desc:
            parts.append(desc)
        range_val = data.get("range", "")
        if range_val:
            parts.append(f"Range: {range_val}")
        comp = data.get("components", [])
        if comp:
            parts.append(f"Components: {', '.join(comp)}")
        dur = data.get("duration", "")
        if dur:
            parts.append(f"Duration: {dur}")
        if data.get("concentration"):
            parts.append("Concentration: yes")
        if data.get("ritual"):
            parts.append("Ritual: yes")
        ct = data.get("casting_time", "")
        if ct:
            parts.append(f"Casting time: {ct}")
        level = data.get("level", 0)
        parts.append(f"Level: {level}")
        school = data.get("school", {})
        if isinstance(school, dict):
            sn = school.get("name", "")
            if sn:
                parts.append(f"School: {sn}")
        dmg = data.get("damage", {})
        if isinstance(dmg, dict):
            dt = dmg.get("damage_type", {})
            if isinstance(dt, dict):
                dtn = dt.get("name", "")
                if dtn:
                    parts.append(f"Damage: {dtn}")
            dacl = dmg.get("damage_at_character_level", {})
            if isinstance(dacl, dict) and dacl:
                bits = [f"{k}: {v}" for k, v in sorted(dacl.items(), key=lambda x: int(x[0]) if str(x[0]).isdigit() else 0)]
                parts.append("At level: " + ", ".join(bits))
        dc_block = data.get("dc", {})
        if isinstance(dc_block, dict):
            dct = dc_block.get("dc_type", {})
            if isinstance(dct, dict):
                dctn = dct.get("name", "")
                if dctn:
                    parts.append(f"DC: {dctn}")
        return "\n".join(parts)
    
    def _get_proficiency_tooltip_text(self, proficiency_index: str) -> str:
        """Load proficiency JSON, follow reference to get desc (e.g. skills/arcana)."""
        if proficiency_index in self.proficiency_cache:
            return self.proficiency_cache[proficiency_index]
        try:
            prof = self.db.get(f"/proficiencies/{proficiency_index}.json")
            name = prof.get("name", proficiency_index)
            ref = prof.get("reference")
            if isinstance(ref, dict):
                url = ref.get("url", "")
                if url:
                    path = url.replace("/api/2014/", "").replace("/api/2014", "").strip("/") + ".json"
                    ref_data = self.db.get(f"/{path}")
                    desc = ref_data.get("desc", [])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    if desc:
                        out = f"{name}\n\n{desc}"
                    else:
                        out = name
                else:
                    out = name
            else:
                out = name
        except Exception:
            out = proficiency_index
        self.proficiency_cache[proficiency_index] = out
        return out
            
    def handle_event(self, event: pygame.event.Event) -> Union[str, None, Character]:
        """Handle events"""
        visible_steps = self._get_visible_steps()
        current_step_name = visible_steps[self.current_step] if self.current_step < len(visible_steps) else "abilities"
        
        # Navigation buttons
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            
            if self.prev_btn.is_clicked(mouse_pos) and self.current_step > 0:
                self.current_step -= 1
                self.tooltip.hide()
                self.trait_rects = []
                return None
                
            # Check if on confirmation step (last step)
            if self.current_step == len(visible_steps) - 1:
                if self.finish_btn.is_clicked(mouse_pos):
                    character = self._finish_creation()
                    return character
            else:
                if self.next_btn.is_clicked(mouse_pos):
                    self.current_step += 1
                    self.tooltip.hide()
                    self.trait_rects = []
                    visible = self._get_visible_steps()
                    if self.current_step < len(visible) and visible[self.current_step] == "confirmation":
                        self.confirmation_scroll_offset = 0
                    return None
                    
        # ESC to go back
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "title"
            
        # Step-specific handling
        if current_step_name == "biography":
            self._handle_biography_event(event)
        elif current_step_name == "race":
            self._handle_race_event(event)
        elif current_step_name == "subrace":
            self._handle_subrace_event(event)
        elif current_step_name == "class":
            self._handle_class_event(event)
        elif current_step_name == "features":
            if self._subfeature_modal_active:
                self._handle_subfeature_modal_event(event)
            else:
                self._handle_features_event(event)
        elif current_step_name == "cantrips":
            self._handle_cantrips_event(event)
        elif current_step_name == "spells":
            self._handle_spells_event(event)
        elif current_step_name == "background":
            self._handle_background_event(event)
        elif current_step_name == "abilities":
            self._handle_abilities_event(event)
        elif current_step_name == "proficiency_choices":
            self._handle_proficiency_choices_event(event)
        elif current_step_name == "confirmation":
            self._handle_confirmation_event(event)
            
        return None
        
    def _handle_biography_event(self, event: pygame.event.Event):
        """Handle biography step events"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.random_name_btn.is_clicked(event.pos):
                name = fantasy_name_generator.generate_random_name(self.build.race or "human", self.build.gender or "male")
                if name:
                    self.build.name = name
                return
            if self.gender_male_btn.is_clicked(event.pos):
                self.build.gender = "male"
                return
            if self.gender_female_btn.is_clicked(event.pos):
                self.build.gender = "female"
                return
            # Commit and blur age/weight when clicking elsewhere
            if self.age_input_active:
                self.age_input_active = False
                self.build.age = int(self.bio_age_buffer) if self.bio_age_buffer.isdigit() else None
            if self.weight_input_active:
                self.weight_input_active = False
                self.build.weight = int(self.bio_weight_buffer) if self.bio_weight_buffer.isdigit() else None
            if self.age_input_rect.collidepoint(event.pos):
                self.age_input_active = True
                self.bio_age_buffer = str(self.build.age) if self.build.age is not None else ""
                self.name_input_active = False
                return
            if self.weight_input_rect.collidepoint(event.pos):
                self.weight_input_active = True
                self.bio_weight_buffer = str(self.build.weight) if self.build.weight is not None else ""
                self.name_input_active = False
                return
            self.name_input_active = self.name_input_rect.collidepoint(event.pos)
            if self.name_input_active:
                return
                
        if event.type == pygame.KEYDOWN:
            if self.name_input_active:
                nm = self.build.name or ""
                if event.key == pygame.K_BACKSPACE:
                    self.build.name = nm[:-1]
                elif event.key == pygame.K_RETURN:
                    self.name_input_active = False
                elif event.unicode and len(nm) < 30:
                    self.build.name = nm + event.unicode
                return
            if self.age_input_active:
                if event.key == pygame.K_BACKSPACE:
                    self.bio_age_buffer = self.bio_age_buffer[:-1]
                elif event.key == pygame.K_RETURN:
                    self.age_input_active = False
                    self.build.age = int(self.bio_age_buffer) if self.bio_age_buffer.isdigit() else None
                elif event.unicode and event.unicode.isdigit() and len(self.bio_age_buffer) < 4:
                    self.bio_age_buffer += event.unicode
                return
            if self.weight_input_active:
                if event.key == pygame.K_BACKSPACE:
                    self.bio_weight_buffer = self.bio_weight_buffer[:-1]
                elif event.key == pygame.K_RETURN:
                    self.weight_input_active = False
                    self.build.weight = int(self.bio_weight_buffer) if self.bio_weight_buffer.isdigit() else None
                elif event.unicode and event.unicode.isdigit() and len(self.bio_weight_buffer) < 4:
                    self.bio_weight_buffer += event.unicode
                return
                
        if self.alignment_list.handle_event(event):
            selected = self.alignment_list.get_selected()
            if selected:
                self.build.alignment = selected.get("index")
                try:
                    self.alignment_data = self.db.get(f"/alignments/{selected.get('index')}.json")
                except Exception:
                    self.alignment_data = None
                
    def _handle_race_event(self, event: pygame.event.Event):
        """Handle race step events"""
        if self.race_list.handle_event(event):
            selected = self.race_list.get_selected()
            if selected:
                self._load_race_details(selected.get("index"))
                
        # Handle trait hover for tooltip
        if event.type == pygame.MOUSEMOTION:
            mouse_pos = event.pos
            tooltip_shown = False
            for rect, trait_index in self.trait_rects:
                if rect.collidepoint(mouse_pos):
                    # Load trait data if not cached
                    if trait_index not in self.traits_cache:
                        try:
                            self.traits_cache[trait_index] = self.db.get(f"/traits/{trait_index}.json")
                        except:
                            self.traits_cache[trait_index] = {"name": trait_index, "desc": ["No description"]}
                    
                    trait_data = self.traits_cache[trait_index]
                    desc = trait_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    self.tooltip.show(trait_data.get("name", ""), desc, mouse_pos)
                    tooltip_shown = True
                    break
                    
            if not tooltip_shown:
                self.tooltip.hide()
                
    def _handle_subrace_event(self, event: pygame.event.Event):
        """Handle subrace step events"""
        if self.subrace_list.handle_event(event):
            selected = self.subrace_list.get_selected()
            if selected:
                self.build.subrace = selected.get("index")
                try:
                    self.build.subrace_data = self.db.get(f"/subraces/{selected.get('index')}.json")
                except:
                    pass
                    
        # Handle trait hover for tooltip (racial_traits for subraces)
        if event.type == pygame.MOUSEMOTION:
            mouse_pos = event.pos
            tooltip_shown = False
            for rect, trait_index in self.trait_rects:
                if rect.collidepoint(mouse_pos):
                    # Load trait data if not cached
                    if trait_index not in self.traits_cache:
                        try:
                            self.traits_cache[trait_index] = self.db.get(f"/traits/{trait_index}.json")
                        except:
                            self.traits_cache[trait_index] = {"name": trait_index, "desc": ["No description"]}
                    
                    trait_data = self.traits_cache[trait_index]
                    desc = trait_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    self.tooltip.show(trait_data.get("name", ""), desc, mouse_pos)
                    tooltip_shown = True
                    break
                    
            if not tooltip_shown:
                self.tooltip.hide()
                    
    def _handle_class_event(self, event: pygame.event.Event):
        """Handle class step events"""
        if self.class_list.handle_event(event):
            selected = self.class_list.get_selected()
            if selected:
                self._load_class_details(selected.get("index"))
    
    def _handle_features_event(self, event: pygame.event.Event):
        """Handle features step: tooltip on hover, click to choose subfeature if needed."""
        # Don't handle events if modal is active
        if self._subfeature_modal_active:
            return
        
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = event.pos
            for rect, feat_index in self.feature_rects:
                if rect.collidepoint(mouse_pos):
                    # Load feature data
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {"name": feat_index, "desc": ["No description"]}
                    
                    feat_data = self.features_cache[feat_index]
                    # Check if feature has subfeature_options
                    feature_specific = feat_data.get("feature_specific", {})
                    subfeature_opts = feature_specific.get("subfeature_options", {})
                    if subfeature_opts:
                        # Always allow selection (including re-selection)
                        # Show modal to choose subfeature
                        self._show_subfeature_choice_modal(feat_index, feat_data, subfeature_opts)
                    break
        
        # Tooltip on hover (only if modal is not active)
        if event.type == pygame.MOUSEMOTION and not self._subfeature_modal_active:
            mouse_pos = event.pos
            tooltip_shown = False
            for rect, feat_index in self.feature_rects:
                if rect.collidepoint(mouse_pos):
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {"name": feat_index, "desc": ["No description"]}
                    
                    feat_data = self.features_cache[feat_index]
                    desc = feat_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    # Show chosen subfeature if selected
                    chosen = self.build.feature_choices.get(feat_index)
                    if chosen:
                        try:
                            subfeat_data = self.db.get(f"/features/{chosen}.json")
                            subfeat_name = subfeat_data.get("name", chosen)
                            desc = f"{desc}\n\nВыбрано: {subfeat_name}"
                        except:
                            pass
                    self.tooltip.show(feat_data.get("name", ""), desc, mouse_pos)
                    tooltip_shown = True
                    break
            
            if not tooltip_shown:
                self.tooltip.hide()
        elif event.type == pygame.MOUSEMOTION and self._subfeature_modal_active:
            # Hide tooltip when modal is active
            self.tooltip.hide()
                
    def _show_subfeature_choice_modal(self, feature_index: str, feature_data: Dict, subfeature_opts: Dict):
        """Show modal to choose subfeature. Stores choice in self._pending_subfeature_choice."""
        from_data = subfeature_opts.get("from", {})
        options = from_data.get("options", [])
        choose_count = subfeature_opts.get("choose", 1)
        
        if not options:
            return
        
        # Extract subfeature options
        subfeatures: List[Dict[str, Any]] = []
        for opt in options:
            if opt.get("option_type") == "reference":
                item = opt.get("item", {})
                if item:
                    subfeatures.append({
                        "index": item.get("index", ""),
                        "name": item.get("name", ""),
                        "url": item.get("url", "")
                    })
        
        if not subfeatures:
            return
        
        # Hide tooltip when opening modal
        self.tooltip.hide()
        
        # Store modal state
        self._subfeature_modal_active = True
        self._subfeature_modal_feature = feature_index
        self._subfeature_modal_options = subfeatures
        self._subfeature_modal_choose = choose_count
        # Pre-select already chosen subfeature if exists
        already_chosen = self.build.feature_choices.get(feature_index)
        self._subfeature_modal_selected = [already_chosen] if already_chosen and already_chosen in [opt.get("index") for opt in subfeatures] else []
                
    def _handle_cantrips_event(self, event: pygame.event.Event):
        """Handle cantrips selection: scroll, tooltip on hover, click-to-toggle."""
        clicked = self.spell_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.spell_list.get_selected()
            if item:
                idx = item.get("index")
                if idx is not None:
                    if idx in self.build.cantrips:
                        self.build.cantrips.remove(idx)
                    elif len(self.build.cantrips) < self.build.cantrips_known:
                        self.build.cantrips.append(idx)
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.spell_list.rect.collidepoint(event.pos) and not self.spell_list._is_in_scrollbar(event.pos)
                       and 0 <= self.spell_list.hovered_index < len(self.spell_list.items))
            if in_list:
                it = self.spell_list.items[self.spell_list.hovered_index]
                sid = it.get("index")
                if sid is not None:
                    if sid not in self.spell_cache:
                        try:
                            self.spell_cache[sid] = self.db.get(f"/spells/{sid}.json")
                        except Exception:
                            self.spell_cache[sid] = {"name": it.get("name", ""), "desc": ["No description"]}
                    d = self.spell_cache[sid]
                    self.tooltip.show(d.get("name", ""), self._format_spell_tooltip(d), event.pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()
                
    def _handle_spells_event(self, event: pygame.event.Event):
        """Handle spells selection: scroll, tooltip on hover, click-to-toggle."""
        clicked = self.spell_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.spell_list.get_selected()
            if item:
                idx = item.get("index")
                if idx is not None:
                    if idx in self.build.spells:
                        self.build.spells.remove(idx)
                    elif len(self.build.spells) < self.build.spells_known:
                        self.build.spells.append(idx)
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.spell_list.rect.collidepoint(event.pos) and not self.spell_list._is_in_scrollbar(event.pos)
                       and 0 <= self.spell_list.hovered_index < len(self.spell_list.items))
            if in_list:
                it = self.spell_list.items[self.spell_list.hovered_index]
                sid = it.get("index")
                if sid is not None:
                    if sid not in self.spell_cache:
                        try:
                            self.spell_cache[sid] = self.db.get(f"/spells/{sid}.json")
                        except Exception:
                            self.spell_cache[sid] = {"name": it.get("name", ""), "desc": ["No description"]}
                    d = self.spell_cache[sid]
                    self.tooltip.show(d.get("name", ""), self._format_spell_tooltip(d), event.pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()
                
    def _handle_proficiency_choices_event(self, event: pygame.event.Event):
        """Handle proficiency choices: scroll, tooltip on hover, click-to-toggle."""
        clicked = self.spell_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.spell_list.get_selected()
            if item and (idx := item.get("index")) is not None:
                if idx in self.build.proficiency_choices_selected:
                    self.build.proficiency_choices_selected.remove(idx)
                elif len(self.build.proficiency_choices_selected) < self.build.proficiency_choose:
                    self.build.proficiency_choices_selected.append(idx)
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.spell_list.rect.collidepoint(event.pos) and not self.spell_list._is_in_scrollbar(event.pos)
                       and 0 <= self.spell_list.hovered_index < len(self.spell_list.items))
            if in_list:
                it = self.spell_list.items[self.spell_list.hovered_index]
                pid = it.get("index")
                if pid is not None:
                    txt = self._get_proficiency_tooltip_text(pid)
                    self.tooltip.show(it.get("name", ""), txt, event.pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()
                
    def _handle_background_event(self, event: pygame.event.Event):
        """Handle background step events"""
        if self.background_list.handle_event(event):
            selected = self.background_list.get_selected()
            if selected:
                self._load_background_details(selected.get("index"))
                
    def _handle_abilities_event(self, event: pygame.event.Event):
        """Handle abilities step events"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for ability, counter in self.ability_counters.items():
                action = counter.handle_click(event.pos)
                if action == "increase":
                    self.build.increase_ability(ability)
                elif action == "decrease":
                    self.build.decrease_ability(ability)

    def _confirmation_scrollbar_rects(self) -> tuple:
        """(track_rect, thumb_rect) for confirmation panel. Uses panel rect and content height."""
        pr = self._confirmation_panel_rect
        ch = getattr(self, "_confirmation_content_height", 0)
        if not pr or ch <= pr.height:
            return (None, None)
        sbw = SelectionList.SCROLLBAR_WIDTH
        pad = SelectionList.SCROLLBAR_PAD
        rx = pr.right - sbw - pad
        track = pygame.Rect(rx, pr.y + pad, sbw, pr.height - 2 * pad)
        visible = pr.height / max(1, ch)
        thumb_h = max(24, int(track.height * visible))
        mx = ch - pr.height
        thumb_y = track.y + int((self.confirmation_scroll_offset / mx) * (track.height - thumb_h))
        thumb = pygame.Rect(rx, thumb_y, sbw, thumb_h)
        return (track, thumb)

    def _handle_confirmation_event(self, event: pygame.event.Event):
        """Handle confirmation step: scroll (wheel, scrollbar drag)."""
        pr = self._confirmation_panel_rect
        ch = getattr(self, "_confirmation_content_height", 0)
        if not pr:
            return
        mx = max(0, ch - pr.height)
        sb_left = pr.right - SelectionList.SCROLLBAR_WIDTH - SelectionList.SCROLLBAR_PAD

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if pr.collidepoint(event.pos) and event.pos[0] >= sb_left and mx > 0:
                track, thumb = self._confirmation_scrollbar_rects()
                if thumb and thumb.collidepoint(event.pos):
                    self._confirmation_scroll_dragging = True
                    self._confirmation_scroll_start_y = event.pos[1]
        elif event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._confirmation_scroll_dragging = False
        elif event.type == pygame.MOUSEMOTION and self._confirmation_scroll_dragging and mx > 0:
            track, thumb = self._confirmation_scrollbar_rects()
            if track and thumb:
                rel = event.pos[1] - track.y
                t = max(0, min(1, rel / (track.height - thumb.height))) if track.height > thumb.height else 0
                self.confirmation_scroll_offset = int(t * mx)
        elif event.type == pygame.MOUSEWHEEL and pr.collidepoint(pygame.mouse.get_pos()) and mx > 0:
            step = 40
            if event.y > 0:
                self.confirmation_scroll_offset = max(0, self.confirmation_scroll_offset - step)
            else:
                self.confirmation_scroll_offset = min(mx, self.confirmation_scroll_offset + step)


    def _finish_creation(self):
        """Finish character creation and return Character object"""
        print("=" * 50)
        print("Character Created!")
        print(f"Name: {self.build.name}")
        print(f"Alignment: {self.build.alignment}")
        print(f"Race: {self.build.race}")
        print(f"Subrace: {self.build.subrace}")
        print(f"Class: {self.build.class_type}")
        print(f"Background: {self.build.background}")
        print(f"Abilities: {self.build.abilities}")
        print(f"Cantrips: {self.build.cantrips}")
        print(f"Spells: {self.build.spells}")
        print(f"Proficiency choices: {self.build.proficiency_choices_selected}")
        print(f"Features: {self.build.features}")
        print(f"Feature choices: {self.build.feature_choices}")
        print("=" * 50)
        
        # Create Character from CharacterBuild
        from core.entities.character import Character
        character = self.build.create_character()
        print("=" * 50)
        print("Character Created!")
        print(f"Name: {character.name}")
        print(f"Alignment: {character.alignment}")
        print(f"Race: {character.race.name if character.race else 'None'}")
        print(f"Subrace: {character.subrace.name if character.subrace else 'None'}")
        print(f"Class: {character.class_type.name if character.class_type else 'None'}")
        print(f"Background: {character.background or 'None'}")
        print(f"Abilities: STR={character.abilities.str}, DEX={character.abilities.dex}, CON={character.abilities.con}, INT={character.abilities.int}, WIS={character.abilities.wis}, CHA={character.abilities.cha}")
        if character.sc:
            cantrips = [s.name for s in character.sc.cantrips]
            spells = [s.name for s in character.sc.leveled_spells]
            print(f"Cantrips ({len(cantrips)}): {', '.join(cantrips) if cantrips else 'None'}")
            print(f"Spells ({len(spells)}): {', '.join(spells) if spells else 'None'}")
            print(f"Prepared spells ({len(character.prepared_spells)}): {', '.join([s.name for s in character.prepared_spells]) if character.prepared_spells else 'None'}")
        else:
            print("Cantrips: None (not a spellcaster)")
            print("Spells: None (not a spellcaster)")
        print(f"Proficiencies ({len(character.proficiencies)}): {', '.join([p.name for p in character.proficiencies[:10]])}{'...' if len(character.proficiencies) > 10 else ''}")
        print(f"Features ({len(character.features)}): {', '.join(character.features)}")
        print(f"Inventory items: {len([item for item in character.inventory if item is not None])}")
        for item in character.inventory:
            if item:
                print(f"Item: {item.name}, category: {item.category}, cost: {item.cost}, weight: {item.weight}, equipped: {item.equipped}")
        print("=" * 50)
        return character
        
    def update(self):
        """Update screen"""
        mouse_pos = pygame.mouse.get_pos()
        self.prev_btn.update(mouse_pos)
        self.next_btn.update(mouse_pos)
        self.finish_btn.update(mouse_pos)
        visible = self._get_visible_steps()
        if self.current_step < len(visible) and visible[self.current_step] == "biography":
            self.random_name_btn.update(mouse_pos)
            self.gender_male_btn.update(mouse_pos)
            self.gender_female_btn.update(mouse_pos)
        
    def draw(self):
        """Draw the screen"""
        self.screen.fill(BLACK)
        
        visible_steps = self._get_visible_steps()
        current_step_name = visible_steps[self.current_step] if self.current_step < len(visible_steps) else "abilities"
        
        # Title
        step_names = self._get_step_names()
        title = f"{loc['char_creation_title']} - {step_names.get(current_step_name, '')}"
        title_surface = self.title_font.render(title, True, GOLD)
        self.screen.blit(title_surface, (50, 30))
        
        # Step indicators
        self._draw_step_indicators(visible_steps)
        
        # Step content
        if current_step_name == "biography":
            self._draw_biography()
        elif current_step_name == "race":
            self._draw_race()
        elif current_step_name == "subrace":
            self._draw_subrace()
        elif current_step_name == "class":
            self._draw_class()
        elif current_step_name == "features":
            self._draw_features()
            if self._subfeature_modal_active:
                self._draw_subfeature_modal()
        elif current_step_name == "cantrips":
            self._draw_cantrips()
        elif current_step_name == "spells":
            self._draw_spells()
        elif current_step_name == "background":
            self._draw_background()
        elif current_step_name == "abilities":
            self._draw_abilities()
        elif current_step_name == "proficiency_choices":
            self._draw_proficiency_choices()
        elif current_step_name == "confirmation":
            self._draw_confirmation()
            
        # Navigation
        if self.current_step > 0:
            self.prev_btn.draw(self.screen)
            
        # Show Next or Finish button based on step
        if self.current_step == len(visible_steps) - 1:
            # Last step (confirmation) - show Finish
            self.finish_btn.draw(self.screen)
        else:
            # Not last step - show Next
            self.next_btn.draw(self.screen)
            
        # Tooltip (draw last, on top of everything, including modals)
        self.tooltip.draw(self.screen)
            
    def _draw_step_indicators(self, visible_steps: List[str]):
        """Draw step progress indicators"""
        x = 50
        y = 90
        for i, step in enumerate(visible_steps):
            color = DARK_GREEN if i < self.current_step else (GOLD if i == self.current_step else DARK_GRAY)
            pygame.draw.circle(self.screen, color, (x, y), 12)
            
            step_name = self._get_step_names().get(step, step)[:3]
            text = self.small_font.render(step_name, True, WHITE)
            self.screen.blit(text, (x - 10, y + 18))
            
            if i < len(visible_steps) - 1:
                pygame.draw.line(self.screen, DARK_GRAY, (x + 15, y), (x + 55, y), 2)
            x += 70
            
    def _draw_biography(self):
        """Draw biography step"""
        # Name input
        name_label = self.font.render(f"{loc['char_name']}:", True, WHITE)
        self.screen.blit(name_label, (100, 148))
        
        pygame.draw.rect(self.screen, INPUT_BG, self.name_input_rect, border_radius=6)
        border_color = GOLD if self.name_input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, border_color, self.name_input_rect, width=2, border_radius=6)
        
        name_text = self.font.render(self.build.name or loc["char_name_placeholder"], True, 
                                      WHITE if self.build.name else LIGHT_GRAY)
        self.screen.blit(name_text, (self.name_input_rect.x + 10, self.name_input_rect.centery - 10))
        
        self.random_name_btn.draw(self.screen)
        
        # Gender
        gender_label = self.font.render(f"{loc['gender']}:", True, WHITE)
        self.screen.blit(gender_label, (100, 228))
        for btn in (self.gender_male_btn, self.gender_female_btn):
            btn.draw(self.screen)
        male_sel = (self.build.gender or "").lower() == "male"
        female_sel = (self.build.gender or "").lower() == "female"
        if male_sel:
            pygame.draw.rect(self.screen, GOLD, self.gender_male_btn.rect, width=3, border_radius=8)
        if female_sel:
            pygame.draw.rect(self.screen, GOLD, self.gender_female_btn.rect, width=3, border_radius=8)
        
        # Age
        age_label = self.font.render(f"{loc['age']}:", True, WHITE)
        self.screen.blit(age_label, (100, 282))
        pygame.draw.rect(self.screen, INPUT_BG, self.age_input_rect, border_radius=6)
        bc = GOLD if self.age_input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, bc, self.age_input_rect, width=2, border_radius=6)
        age_val = self.bio_age_buffer if self.age_input_active else (str(self.build.age) if self.build.age is not None else "")
        age_text = self.font.render(age_val or "—", True, WHITE if age_val else LIGHT_GRAY)
        self.screen.blit(age_text, (self.age_input_rect.x + 10, self.age_input_rect.centery - 10))
        
        # Weight
        weight_label = self.font.render(f"{loc['weight']} ({loc['weight_unit']}):", True, WHITE)
        self.screen.blit(weight_label, (200, 282))
        pygame.draw.rect(self.screen, INPUT_BG, self.weight_input_rect, border_radius=6)
        bc = GOLD if self.weight_input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, bc, self.weight_input_rect, width=2, border_radius=6)
        weight_val = self.bio_weight_buffer if self.weight_input_active else (str(self.build.weight) if self.build.weight is not None else "")
        weight_text = self.font.render(weight_val or "—", True, WHITE if weight_val else LIGHT_GRAY)
        self.screen.blit(weight_text, (self.weight_input_rect.x + 10, self.weight_input_rect.centery - 10))
        
        # Alignment
        align_label = self.font.render(f"{loc['alignment']}:", True, WHITE)
        self.screen.blit(align_label, (100, 330))
        self.alignment_list.draw(self.screen)
        
        # Alignment description panel (right side, same vertical as alignment list)
        if self.alignment_data:
            self._draw_info_panel(500, 348, self.alignment_data, height=320)
        
    def _draw_race(self):
        """Draw race step"""
        self.race_list.draw(self.screen)
        
        # Race info panel (description) and stats panel
        if self.build.race_data:
            self._draw_info_panel(470, 150, self.build.race_data)
            self._draw_race_stats_panel(850, 150, self.build.race_data)
            
    def _draw_subrace(self):
        """Draw subrace step"""
        self.subrace_list.draw(self.screen)
        
        if self.build.subrace_data:
            self._draw_info_panel(470, 150, self.build.subrace_data)
            self._draw_subrace_stats_panel(850, 150, self.build.subrace_data)
            
    def _draw_class(self):
        """Draw class step"""
        self.class_list.draw(self.screen)
        
        if self.build.class_data:
            self._draw_info_panel(470, 150, self.build.class_data)
            self._draw_class_stats_panel(850, 150, self.build.class_data)
    
    def _draw_features(self):
        """Draw features step - list of level 1 features with tooltip support"""
        s = self._scale
        label = self.font.render("Классовые особенности (уровень 1):", True, WHITE)
        self.screen.blit(label, (_sc(100, s), _sc(130, s)))
        
        self.feature_rects = []
        y = _sc(180, s)
        item_h = _sc(40, s)
        x = _sc(100, s)
        w = _sc(600, s)
        
        # Show all features from level 1, mark which need choice
        for feat in self.features_list:
            feat_index = feat.get("index", "")
            feat_name = feat.get("name", feat_index)
            
            # Load feature data for checking subfeature options
            if feat_index not in self.features_cache:
                try:
                    self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                except:
                    self.features_cache[feat_index] = {}
            
            # Check if subfeature was chosen
            chosen_sub = self.build.feature_choices.get(feat_index)
            if chosen_sub:
                try:
                    subfeat_data = self.db.get(f"/features/{chosen_sub}.json")
                    feat_name = f"{feat_name} → {subfeat_data.get('name', chosen_sub)}"
                except:
                    pass
            else:
                # Check if feature needs subfeature choice
                feat_data = self.features_cache.get(feat_index, {})
                feature_specific = feat_data.get("feature_specific", {})
                if feature_specific.get("subfeature_options"):
                    feat_name = f"{feat_name} [выберите]"
            
            rect = pygame.Rect(x, y, w, item_h)
            self.feature_rects.append((rect, feat_index))
            
            # Draw feature item
            bg = HOVER_COLOR if rect.collidepoint(pygame.mouse.get_pos()) else DARK_GRAY
            pygame.draw.rect(self.screen, bg, rect, border_radius=6)
            pygame.draw.rect(self.screen, GOLD, rect, width=1, border_radius=6)
            
            txt = self.small_font.render(feat_name[:60], True, WHITE)
            self.screen.blit(txt, (rect.x + 10, rect.centery - txt.get_height() // 2))
            
            y += item_h + _sc(8, s)
            
    def _draw_subfeature_modal(self):
        """Draw modal for choosing subfeature"""
        s = self._scale
        w, h = self._w, self._h
        mw, mh = _sc(500, s), _sc(400, s)
        mr = pygame.Rect(w // 2 - mw // 2, h // 2 - mh // 2, mw, mh)
        
        # Overlay
        overlay = pygame.Surface((w, h))
        overlay.set_alpha(180)
        overlay.fill(BLACK)
        self.screen.blit(overlay, (0, 0))
        
        # Modal
        pygame.draw.rect(self.screen, MODAL_BG, mr, border_radius=12)
        pygame.draw.rect(self.screen, GOLD, mr, width=2, border_radius=12)
        
        # Title
        feat_name = "Выберите подособенность"
        if self._subfeature_modal_feature:
            try:
                feat_data = self.db.get(f"/features/{self._subfeature_modal_feature}.json")
                feat_name = feat_data.get("name", self._subfeature_modal_feature)
            except:
                pass
        title = self.header_font.render(feat_name, True, GOLD)
        self.screen.blit(title, (mr.centerx - title.get_width() // 2, mr.y + _sc(20, s)))
        
        # Options list
        y = mr.y + _sc(70, s)
        item_h = _sc(36, s)
        for opt in self._subfeature_modal_options:
            opt_index = opt.get("index", "")
            opt_name = opt.get("name", opt_index)
            selected = opt_index in self._subfeature_modal_selected
            
            rr = pygame.Rect(mr.x + _sc(20, s), y, mr.w - _sc(40, s), item_h)
            bg = DARK_GREEN if selected else (HOVER_COLOR if rr.collidepoint(pygame.mouse.get_pos()) else DARK_GRAY)
            pygame.draw.rect(self.screen, bg, rr, border_radius=6)
            pygame.draw.rect(self.screen, GOLD, rr, width=1, border_radius=6)
            
            txt = self.small_font.render(opt_name[:50], True, WHITE)
            self.screen.blit(txt, (rr.x + 10, rr.centery - txt.get_height() // 2))
            
            y += item_h + _sc(6, s)
        
        # Confirm button
        btn_w, btn_h = _sc(120, s), _sc(40, s)
        btn_y = mr.bottom - _sc(60, s)
        confirm_rect = pygame.Rect(mr.centerx - btn_w // 2, btn_y, btn_w, btn_h)
        can_confirm = len(self._subfeature_modal_selected) == self._subfeature_modal_choose
        bg = GOLD if can_confirm else DARK_GRAY
        pygame.draw.rect(self.screen, bg, confirm_rect, border_radius=6)
        pygame.draw.rect(self.screen, GOLD, confirm_rect, width=2, border_radius=6)
        confirm_text_str = loc.get("confirm", "Готово")
        confirm_txt = self.font.render(confirm_text_str, True, WHITE if can_confirm else LIGHT_GRAY)
        self.screen.blit(confirm_txt, confirm_txt.get_rect(center=confirm_rect.center))
    
    def _handle_subfeature_modal_event(self, event: pygame.event.Event):
        """Handle events in subfeature choice modal"""
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self._subfeature_modal_active = False
            self.tooltip.hide()
            return
        
        # Tooltip on hover for options
        if event.type == pygame.MOUSEMOTION:
            pos = event.pos
            s = self._scale
            w, h = self._w, self._h
            mw, mh = _sc(500, s), _sc(400, s)
            mr = pygame.Rect(w // 2 - mw // 2, h // 2 - mh // 2, mw, mh)
            
            tooltip_shown = False
            # Check if hovering over an option
            y = mr.y + _sc(70, s)
            item_h = _sc(36, s)
            for opt in self._subfeature_modal_options:
                opt_index = opt.get("index", "")
                rr = pygame.Rect(mr.x + _sc(20, s), y, mr.w - _sc(40, s), item_h)
                if rr.collidepoint(pos):
                    # Load subfeature data
                    if opt_index not in self.features_cache:
                        try:
                            self.features_cache[opt_index] = self.db.get(f"/features/{opt_index}.json")
                        except:
                            self.features_cache[opt_index] = {"name": opt_index, "desc": ["No description"]}
                    
                    subfeat_data = self.features_cache[opt_index]
                    desc = subfeat_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    self.tooltip.show(subfeat_data.get("name", opt_index), desc, pos)
                    tooltip_shown = True
                    break
                y += item_h + _sc(6, s)
            
            if not tooltip_shown:
                self.tooltip.hide()
        
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            s = self._scale
            w, h = self._w, self._h
            mw, mh = _sc(500, s), _sc(400, s)
            mr = pygame.Rect(w // 2 - mw // 2, h // 2 - mh // 2, mw, mh)
            
            # Check option clicks
            y = mr.y + _sc(70, s)
            item_h = _sc(36, s)
            option_clicked = False
            for opt in self._subfeature_modal_options:
                opt_index = opt.get("index", "")
                rr = pygame.Rect(mr.x + _sc(20, s), y, mr.w - _sc(40, s), item_h)
                if rr.collidepoint(pos):
                    option_clicked = True
                    if opt_index in self._subfeature_modal_selected:
                        self._subfeature_modal_selected.remove(opt_index)
                    elif len(self._subfeature_modal_selected) < self._subfeature_modal_choose:
                        self._subfeature_modal_selected.append(opt_index)
                    break
                y += item_h + _sc(6, s)
            
            # Check confirm button (only if option wasn't clicked)
            if not option_clicked:
                btn_w, btn_h = _sc(120, s), _sc(40, s)
                btn_y = mr.bottom - _sc(60, s)
                confirm_rect = pygame.Rect(mr.centerx - btn_w // 2, btn_y, btn_w, btn_h)
                if confirm_rect.collidepoint(pos) and len(self._subfeature_modal_selected) == self._subfeature_modal_choose:
                    # Save choice
                    if self._subfeature_modal_feature:
                        # Store first selected (or all if choose > 1)
                        chosen = self._subfeature_modal_selected[0] if self._subfeature_modal_selected else None
                        if chosen:
                            self.build.feature_choices[self._subfeature_modal_feature] = chosen
                            # Replace parent feature with chosen subfeature in features list
                            if self._subfeature_modal_feature in self.build.features:
                                idx = self.build.features.index(self._subfeature_modal_feature)
                                self.build.features[idx] = chosen
                            elif chosen not in self.build.features:
                                self.build.features.append(chosen)
                    self._subfeature_modal_active = False
            
    def _draw_cantrips(self):
        """Draw cantrips selection"""
        label = self.font.render(f"{loc['select_cantrips']} ({len(self.build.cantrips)}/{self.build.cantrips_known}):", True, WHITE)
        self.screen.blit(label, (100, 130))
        
        self.spell_list.set_items(self.cantrips if hasattr(self, 'cantrips') else [])
        self.spell_list.selected_indices = set(self.build.cantrips)
        self.spell_list.draw(self.screen)
        
        # Selected cantrips
        y = 500
        selected_label = self.font.render(f"{loc['selected']}:", True, GOLD)
        self.screen.blit(selected_label, (100, y))
        y += 30
        for cantrip in self.build.cantrips:
            text = self.small_font.render(f"• {cantrip}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += 25
            
    def _draw_spells(self):
        """Draw spells selection"""
        label = self.font.render(f"{loc['select_spells']} ({len(self.build.spells)}/{self.build.spells_known}):", True, WHITE)
        self.screen.blit(label, (100, 130))
        
        self.spell_list.set_items(self.level_1_spells if hasattr(self, 'level_1_spells') else [])
        self.spell_list.selected_indices = set(self.build.spells)
        self.spell_list.draw(self.screen)
        
        # Selected spells
        y = 500
        selected_label = self.font.render(f"{loc['selected']}:", True, GOLD)
        self.screen.blit(selected_label, (100, y))
        y += 30
        for spell in self.build.spells:
            text = self.small_font.render(f"• {spell}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += 25
            
    def _draw_proficiency_choices(self):
        """Draw proficiency choices (class skills, etc.)."""
        opts = getattr(self, "proficiency_options", [])
        n = self.build.proficiency_choose
        label = self.font.render(
            f"{loc['select_proficiencies']} ({len(self.build.proficiency_choices_selected)}/{n}):",
            True, WHITE
        )
        self.screen.blit(label, (100, 130))
        self.spell_list.set_items(opts)
        self.spell_list.selected_indices = set(self.build.proficiency_choices_selected)
        self.spell_list.draw(self.screen)
        y = 500
        selected_label = self.font.render(f"{loc['selected']}:", True, GOLD)
        self.screen.blit(selected_label, (100, y))
        y += 30
        idx_to_name = {it.get("index"): it.get("name", "") for it in opts}
        for pid in self.build.proficiency_choices_selected:
            name = idx_to_name.get(pid, pid)
            text = self.small_font.render(f"• {name}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += 25
            
    def _draw_background(self):
        """Draw background step"""
        self.background_list.draw(self.screen)
        
        if self.build.background_data:
            self._draw_info_panel(500, 150, self.build.background_data)
            
    def _draw_abilities(self):
        """Draw abilities step"""
        # Points remaining
        points_text = self.font.render(f"{loc['points']}: {self.build.points_remaining}/27", True, GOLD)
        self.screen.blit(points_text, (150, 140))
        
        # Ability counters
        for ability, counter in self.ability_counters.items():
            value = self.build.abilities[ability]
            modifier = self.build.get_ability_modifier(ability)
            can_inc = self.build.can_increase_ability(ability)
            can_dec = self.build.can_decrease_ability(ability)
            counter.draw(self.screen, value, modifier, can_inc, can_dec)
            
        # Racial bonuses info
        if self.build.race_data:
            y = 500
            bonuses_label = self.font.render(f"{loc['racial_bonuses']}:", True, GOLD)
            self.screen.blit(bonuses_label, (150, y))
            y += 30
            for bonus in self.build.race_data.get("ability_bonuses", []):
                ab_name = bonus.get("ability_score", {}).get("name", "")
                ab_bonus = bonus.get("bonus", 0)
                text = self.small_font.render(f"+{ab_bonus} {ab_name}", True, DARK_GREEN)
                self.screen.blit(text, (160, y))
                y += 25
                
    def _draw_info_panel(self, x: int, y: int, data: Dict[str, Any], width: int = 350, height: int = 450):
        """Draw info panel for selected item"""
        panel_rect = pygame.Rect(x, y, width, height)
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Name
        name = data.get("name", "")
        name_surface = self.header_font.render(name, True, GOLD)
        self.screen.blit(name_surface, (x + 15, y + 15))
        
        # Description or other info
        desc = data.get("desc", data.get("alignment", ""))
        if isinstance(desc, list):
            desc = " ".join(desc) if desc else ""
            
        # Word wrap description
        words = str(desc)[:800].split()
        lines = []
        current_line = ""
        for word in words:
            test_line = current_line + " " + word if current_line else word
            if self.small_font.size(test_line)[0] < panel_rect.width - 30:
                current_line = test_line
            else:
                if current_line:
                    lines.append(current_line)
                current_line = word
        if current_line:
            lines.append(current_line)
            
        text_y = y + 60
        max_lines = max(1, (height - 60) // 22)
        for line in lines[:max_lines]:
            line_surface = self.small_font.render(line, True, LIGHT_GRAY)
            self.screen.blit(line_surface, (x + 15, text_y))
            text_y += 22
            
    def _draw_race_stats_panel(self, x: int, y: int, data: Dict[str, Any]):
        """Draw race statistics panel"""
        panel_width = min(_sc(380, self._scale), self._w - x - _sc(20, self._scale))
        panel_rect = pygame.Rect(x, y, panel_width, _sc(450, self._scale))
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Header
        header = self.header_font.render(loc["race_stats"], True, GOLD)
        self.screen.blit(header, (x + 15, y + 15))
        
        text_y = y + 55
        
        # Speed
        speed = data.get("speed", 30)
        speed_text = self.font.render(f"{loc['race_speed']}: {speed} {loc['race_speed_unit']}", True, WHITE)
        self.screen.blit(speed_text, (x + 15, text_y))
        text_y += 35
        
        # Size
        size = data.get("size", "Medium")
        size_text = self.font.render(f"{loc['race_size']}: {size}", True, WHITE)
        self.screen.blit(size_text, (x + 15, text_y))
        text_y += 35
        
        # Ability Bonuses
        bonuses = data.get("ability_bonuses", [])
        if bonuses:
            bonus_label = self.font.render(f"{loc['race_ability_bonuses']}:", True, WHITE)
            self.screen.blit(bonus_label, (x + 15, text_y))
            text_y += 28
            for bonus in bonuses:
                ab_name = bonus.get("ability_score", {}).get("name", "")
                ab_bonus = bonus.get("bonus", 0)
                bonus_text = self.small_font.render(f"  +{ab_bonus} {ab_name}", True, DARK_GREEN)
                self.screen.blit(bonus_text, (x + 20, text_y))
                text_y += 22
            text_y += 10
            
        # Languages
        languages = data.get("languages", [])
        if languages:
            lang_label = self.font.render(f"{loc['race_languages']}:", True, WHITE)
            self.screen.blit(lang_label, (x + 15, text_y))
            text_y += 28
            lang_names = [l.get("name", "") for l in languages]
            lang_text = self.small_font.render(f"  {', '.join(lang_names)}", True, LIGHT_GRAY)
            self.screen.blit(lang_text, (x + 20, text_y))
            text_y += 30
            
        # Traits (with hover)
        traits = data.get("traits", [])
        if traits:
            traits_label = self.font.render(f"{loc['race_traits']}:", True, WHITE)
            self.screen.blit(traits_label, (x + 15, text_y))
            text_y += 28
            
            # Clear old trait rects
            self.trait_rects = []
            
            for trait in traits:
                trait_name = trait.get("name", "")
                trait_index = trait.get("index", "")
                
                # Draw trait name with underline (hoverable)
                trait_surface = self.small_font.render(f"  • {trait_name}", True, GOLD)
                trait_rect = trait_surface.get_rect(topleft=(x + 20, text_y))
                
                # Store rect for hover detection
                self.trait_rects.append((trait_rect, trait_index))
                
                self.screen.blit(trait_surface, trait_rect)
                
                # Underline to indicate hoverable
                pygame.draw.line(self.screen, GOLD, 
                               (trait_rect.left + 20, trait_rect.bottom),
                               (trait_rect.right, trait_rect.bottom), 1)
                text_y += 24
                
    def _draw_subrace_stats_panel(self, x: int, y: int, data: Dict[str, Any]):
        """Draw subrace statistics panel"""
        panel_width = min(_sc(380, self._scale), self._w - x - _sc(20, self._scale))
        panel_rect = pygame.Rect(x, y, panel_width, _sc(300, self._scale))
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Header
        header = self.header_font.render(loc["subrace_bonuses"], True, GOLD)
        self.screen.blit(header, (x + 15, y + 15))
        
        text_y = y + 55
        
        # Ability Bonuses
        bonuses = data.get("ability_bonuses", [])
        if bonuses:
            bonus_label = self.font.render(f"{loc['race_ability_bonuses']}:", True, WHITE)
            self.screen.blit(bonus_label, (x + 15, text_y))
            text_y += 28
            for bonus in bonuses:
                ab_name = bonus.get("ability_score", {}).get("name", "")
                ab_bonus = bonus.get("bonus", 0)
                bonus_text = self.small_font.render(f"  +{ab_bonus} {ab_name}", True, DARK_GREEN)
                self.screen.blit(bonus_text, (x + 20, text_y))
                text_y += 22
            text_y += 10
            
        # Racial Traits (with hover) - note: subraces use "racial_traits" not "traits"
        traits = data.get("racial_traits", [])
        if traits:
            traits_label = self.font.render(f"{loc['subrace_traits']}:", True, WHITE)
            self.screen.blit(traits_label, (x + 15, text_y))
            text_y += 28
            
            # Clear old trait rects
            self.trait_rects = []
            
            for trait in traits:
                trait_name = trait.get("name", "")
                trait_index = trait.get("index", "")
                
                # Draw trait name with underline (hoverable)
                trait_surface = self.small_font.render(f"  • {trait_name}", True, GOLD)
                trait_rect = trait_surface.get_rect(topleft=(x + 20, text_y))
                
                # Store rect for hover detection
                self.trait_rects.append((trait_rect, trait_index))
                
                self.screen.blit(trait_surface, trait_rect)
                
                # Underline to indicate hoverable
                pygame.draw.line(self.screen, GOLD, 
                               (trait_rect.left + 20, trait_rect.bottom),
                               (trait_rect.right, trait_rect.bottom), 1)
                text_y += 24
                
    def _draw_class_stats_panel(self, x: int, y: int, data: Dict[str, Any]):
        """Draw class statistics panel"""
        panel_width = min(_sc(380, self._scale), self._w - x - _sc(20, self._scale))
        panel_rect = pygame.Rect(x, y, panel_width, _sc(500, self._scale))
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Header
        header = self.header_font.render(loc["class_stats"], True, GOLD)
        self.screen.blit(header, (x + 15, y + 15))
        
        text_y = y + 55
        
        # Hit Die
        hit_die = data.get("hit_die", 8)
        hit_die_text = self.font.render(f"{loc['class_hit_die']}: d{hit_die}", True, WHITE)
        self.screen.blit(hit_die_text, (x + 15, text_y))
        text_y += 35
        
        # Saving Throws
        saving_throws = data.get("saving_throws", [])
        if saving_throws:
            st_label = self.font.render(f"{loc['class_saving_throws']}:", True, WHITE)
            self.screen.blit(st_label, (x + 15, text_y))
            text_y += 28
            st_names = [st.get("name", "") for st in saving_throws]
            st_text = self.small_font.render(f"  {', '.join(st_names)}", True, DARK_GREEN)
            self.screen.blit(st_text, (x + 20, text_y))
            text_y += 30
            
        # Proficiencies (grouped by type)
        proficiencies = data.get("proficiencies", [])
        if proficiencies:
            prof_label = self.font.render(f"{loc['class_proficiencies']}:", True, WHITE)
            self.screen.blit(prof_label, (x + 15, text_y))
            text_y += 28
            
            # Group proficiencies by type
            armor = []
            weapons = []
            other = []
            
            for prof in proficiencies:
                name = prof.get("name", "")
                index = prof.get("index", "")
                # Skip saving throws - already shown above
                if "saving-throw" in index:
                    continue
                elif "armor" in index.lower() or "shield" in index.lower():
                    armor.append(name)
                elif "weapon" in index.lower() or index in ["simple-weapons", "martial-weapons"]:
                    weapons.append(name)
                else:
                    other.append(name)
                    
            if armor:
                armor_text = self.small_font.render(f"  {loc['class_armor']}: {', '.join(armor)}", True, LIGHT_GRAY)
                self.screen.blit(armor_text, (x + 20, text_y))
                text_y += 24
            if weapons:
                weap_text = self.small_font.render(f"  {loc['class_weapons']}: {', '.join(weapons)}", True, LIGHT_GRAY)
                self.screen.blit(weap_text, (x + 20, text_y))
                text_y += 24
            if other:
                other_text = self.small_font.render(f"  {loc['class_tools']}: {', '.join(other)}", True, LIGHT_GRAY)
                self.screen.blit(other_text, (x + 20, text_y))
                text_y += 24
            text_y += 10
            
        # Proficiency Choices (skills)
        prof_choices = data.get("proficiency_choices", [])
        for choice in prof_choices:
            choose = choice.get("choose", 0)
            desc = choice.get("desc", "")
            if desc and choose > 0:
                choice_label = self.font.render(f"{loc['class_skill_choices']}:", True, WHITE)
                self.screen.blit(choice_label, (x + 15, text_y))
                text_y += 28
                
                # Wrap desc text if too long
                max_width = panel_width - 40
                words = desc.split()
                lines = []
                current_line = ""
                for word in words:
                    test = current_line + " " + word if current_line else word
                    if self.small_font.size(test)[0] < max_width:
                        current_line = test
                    else:
                        if current_line:
                            lines.append(current_line)
                        current_line = word
                if current_line:
                    lines.append(current_line)
                    
                for line in lines:
                    line_text = self.small_font.render(f"  {line}", True, LIGHT_GRAY)
                    self.screen.blit(line_text, (x + 20, text_y))
                    text_y += 22
                text_y += 10
                break  # Only show first choice
            
        # Spellcasting
        spellcasting = data.get("spellcasting")
        if spellcasting:
            spell_label = self.font.render(f"{loc['class_spellcasting']}:", True, WHITE)
            self.screen.blit(spell_label, (x + 15, text_y))
            text_y += 28
            
            spell_ability = spellcasting.get("spellcasting_ability", {}).get("name", "")
            if spell_ability:
                ability_text = self.small_font.render(f"  {loc['class_spell_ability']}: {spell_ability}", True, GOLD)
                self.screen.blit(ability_text, (x + 20, text_y))
                text_y += 24

    def _truncate_text(self, font: pygame.font.Font, text: str, max_width: int) -> str:
        """Truncate text with '...' if it exceeds max_width."""
        if not text:
            return ""
        if font.size(text)[0] <= max_width:
            return text
        suffix = "..."
        while len(text) > 1 and font.size(text + suffix)[0] > max_width:
            text = text[:-1]
        return text.rstrip() + suffix

    def _wrap_text_lines(self, font: pygame.font.Font, text: str, max_width: int) -> List[str]:
        """Word-wrap text into lines that fit max_width."""
        if not text or max_width <= 0:
            return []
        words = text.split()
        lines = []
        current = ""
        for w in words:
            trial = (current + " " + w).strip() if current else w
            if font.size(trial)[0] <= max_width:
                current = trial
            else:
                if current:
                    lines.append(current)
                current = w
        if current:
            lines.append(current)
        return lines

    def _draw_confirmation(self):
        """Draw confirmation screen: single scrollable panel, truncated/wrapped text."""
        s = self._scale
        panel_x, panel_y = _sc(50, s), _sc(120, s)
        panel_w = self._w - _sc(100, s)
        panel_h = self._h - panel_y - _sc(100, s)  # space for nav buttons
        padding = 20
        row_h = 32
        header_h = 44
        label_w = 220
        value_max_w = panel_w - padding * 2 - label_w - 20
        content_max_w = panel_w - padding * 2

        pr = pygame.Rect(panel_x, panel_y, panel_w, panel_h)
        self._confirmation_panel_rect = pr

        cx = panel_x + padding
        virtual_y = float(panel_y + padding)

        def meas_row(_label_key: str, _value: str, _font=None):
            nonlocal virtual_y
            virtual_y += row_h

        def meas_header(_txt: str):
            nonlocal virtual_y
            if virtual_y > panel_y + padding:
                virtual_y += 12
            virtual_y += header_h

        # Measure content height
        meas_header(loc.get("char_info", "Character Info"))
        meas_row("char_name", self.build.name or "")
        if self.build.alignment:
            try:
                ad = self.db.get(f"/alignments/{self.build.alignment}.json")
                meas_row("alignment", ad.get("name", self.build.alignment) if ad else self.build.alignment)
            except Exception:
                meas_row("alignment", self.build.alignment)
        if self.build.race_data:
            meas_row("step_race", self.build.race_data.get("name", "") or self.build.race or "")
        if self.build.subrace_data:
            meas_row("step_subrace", self.build.subrace_data.get("name", "") or self.build.subrace or "")
        if self.build.class_data:
            meas_row("step_class", self.build.class_data.get("name", "") or self.build.class_type or "")
        if self.build.background_data:
            meas_row("step_background", self.build.background_data.get("name", "") or self.build.background or "")
        meas_header(loc.get("step_abilities", "Abilities"))
        for _ in self.ability_labels:
            virtual_y += row_h
        meas_header(loc.get("proficiencies", "Proficiencies"))
        prof_names = []
        if self.build.class_data:
            for p in self.build.class_data.get("proficiencies", []) or []:
                if isinstance(p, dict):
                    prof_names.append(p.get("name", ""))
        for pid in self.build.proficiency_choices_selected:
            try:
                pd = self.db.get(f"/proficiencies/{pid}.json")
                prof_names.append(pd.get("name", pid))
            except Exception:
                prof_names.append(pid)
        if self.build.background_data:
            for bp in self.build.background_data.get("starting_proficiencies", []) or []:
                if isinstance(bp, dict):
                    prof_names.append(bp.get("name", ""))
        if prof_names:
            prof_text = ", ".join(prof_names)
            for _ in self._wrap_text_lines(self.small_font, prof_text, content_max_w - 20):
                virtual_y += 22
        else:
            virtual_y += 22
        if self.build.class_data and self.build.class_data.get("spellcasting"):
            meas_header(loc.get("spells", "Spells"))
            for _ in [self.build.cantrips, self.build.spells, self.build.prepared_spells]:
                if _:
                    virtual_y += 28
                    names = []
                    for idx in _:
                        try:
                            sd = self.db.get(f"/spells/{idx}.json")
                            names.append(sd.get("name", idx))
                        except Exception:
                            names.append(idx)
                    s = ", ".join(names)
                    for _ in self._wrap_text_lines(self.small_font, s, content_max_w - 20):
                        virtual_y += 22
        virtual_y += padding
        content_height = virtual_y - panel_y
        self._confirmation_content_height = content_height

        mx = max(0, content_height - panel_h)
        self.confirmation_scroll_offset = max(0, min(mx, self.confirmation_scroll_offset))

        # Draw panel background and border
        pygame.draw.rect(self.screen, DARK_GRAY, pr, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, pr, width=2, border_radius=8)

        clip_save = self.screen.get_clip()
        self.screen.set_clip(pr)

        cy = panel_y + padding - self.confirmation_scroll_offset

        def draw_row(label_key: str, value: str, font_used=None):
            nonlocal cy
            f = font_used or self.font
            lbl = loc.get(label_key, label_key) + ":"
            val = self._truncate_text(f, value or loc.get("none", "None"), value_max_w)
            if cy + row_h > panel_y and cy < panel_y + panel_h:
                self.screen.blit(f.render(lbl, True, WHITE), (cx, cy))
                self.screen.blit(f.render(val, True, GOLD), (cx + label_w, cy))
            cy += row_h

        def draw_header(txt: str):
            nonlocal cy
            if cy > panel_y + padding:
                cy += 12
            if cy + header_h > panel_y and cy < panel_y + panel_h:
                self.screen.blit(self.header_font.render(txt, True, GOLD), (cx, cy))
            cy += header_h

        draw_header(loc.get("char_info", "Character Info"))
        draw_row("char_name", self.build.name or "")
        if self.build.alignment:
            try:
                ad = self.db.get(f"/alignments/{self.build.alignment}.json")
                draw_row("alignment", ad.get("name", self.build.alignment) if ad else self.build.alignment)
            except Exception:
                draw_row("alignment", self.build.alignment)
        if self.build.race_data:
            draw_row("step_race", self.build.race_data.get("name", "") or self.build.race or "")
        if self.build.subrace_data:
            draw_row("step_subrace", self.build.subrace_data.get("name", "") or self.build.subrace or "")
        if self.build.class_data:
            draw_row("step_class", self.build.class_data.get("name", "") or self.build.class_type or "")
        if self.build.background_data:
            draw_row("step_background", self.build.background_data.get("name", "") or self.build.background or "")

        draw_header(loc.get("step_abilities", "Abilities"))
        mod = lambda x: (x - 10) // 2
        for ability, label in self.ability_labels.items():
            score = self.build.abilities.get(ability, 10)
            if self.build.race_data:
                for b in self.build.race_data.get("ability_bonuses", []) or []:
                    ab = b.get("ability_score", {}) or {}
                    if ab.get("index") == ability:
                        score += b.get("bonus", 0)
            if self.build.subrace_data:
                for b in self.build.subrace_data.get("ability_bonuses", []) or []:
                    ab = b.get("ability_score", {}) or {}
                    if ab.get("index") == ability:
                        score += b.get("bonus", 0)
            mod_str = f"+{mod(score)}" if mod(score) >= 0 else str(mod(score))
            val = f"{score} ({mod_str})"
            if cy + row_h > panel_y and cy < panel_y + panel_h:
                self.screen.blit(self.font.render(f"{label}:", True, WHITE), (cx, cy))
                self.screen.blit(self.font.render(val, True, GOLD), (cx + label_w, cy))
            cy += row_h

        draw_header(loc.get("proficiencies", "Proficiencies"))
        if prof_names:
            prof_text = ", ".join(prof_names)
            for line in self._wrap_text_lines(self.small_font, prof_text, content_max_w - 20):
                if cy + 22 > panel_y and cy < panel_y + panel_h:
                    self.screen.blit(self.small_font.render("  " + line, True, LIGHT_GRAY), (cx, cy))
                cy += 22
        else:
            if cy + 22 > panel_y and cy < panel_y + panel_h:
                self.screen.blit(self.small_font.render("  " + loc.get("none", "None"), True, LIGHT_GRAY), (cx, cy))
            cy += 22

        if self.build.class_data and self.build.class_data.get("spellcasting"):
            draw_header(loc.get("spells", "Spells"))
            for title_key, lst in [
                ("step_cantrips", self.build.cantrips),
                ("step_spells", self.build.spells),
                ("step_prepared", self.build.prepared_spells),
            ]:
                if not lst:
                    continue
                if cy + 28 > panel_y and cy < panel_y + panel_h:
                    self.screen.blit(self.small_font.render(loc.get(title_key, title_key) + ":", True, GOLD), (cx, cy))
                cy += 28
                names = []
                for idx in lst:
                    try:
                        sd = self.db.get(f"/spells/{idx}.json")
                        names.append(sd.get("name", idx))
                    except Exception:
                        names.append(idx)
                s = ", ".join(names)
                for line in self._wrap_text_lines(self.small_font, s, content_max_w - 20):
                    if cy + 22 > panel_y and cy < panel_y + panel_h:
                        self.screen.blit(self.small_font.render("  " + line, True, LIGHT_GRAY), (cx, cy))
                    cy += 22

        self.screen.set_clip(clip_save)

        if mx > 0:
            track, thumb = self._confirmation_scrollbar_rects()
            if track and thumb:
                pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=4)
                pygame.draw.rect(self.screen, GOLD, thumb, border_radius=4)
