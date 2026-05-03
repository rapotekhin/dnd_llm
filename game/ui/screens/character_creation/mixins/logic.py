"""Character creation: detail loaders and tooltip text."""
from typing import Any, Dict, List, Optional


class CharacterCreationLogicMixin:
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
            self._subfeature_modal_scroll = 0  # Scroll position for options list
            
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
