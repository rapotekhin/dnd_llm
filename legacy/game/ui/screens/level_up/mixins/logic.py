"""Level-up: validation and spell tooltip text."""
from typing import Any, Dict, List


class LevelUpLogicMixin:
    def _validate_step(self, step_name: str) -> bool:
        """Validate current step before proceeding"""
        if step_name == "features":
            # Check if all features with subfeature_options have been chosen
            for feat in self.features_list:
                feat_index = feat.get("index", "")
                if feat_index:
                    # Load feature data to check for subfeature options
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {}
                    
                    feat_data = self.features_cache.get(feat_index, {})
                    feature_specific = feat_data.get("feature_specific", {})
                    subfeature_opts = feature_specific.get("subfeature_options", {})
                    if subfeature_opts:
                        # This feature requires a choice
                        choose_count = subfeature_opts.get("choose", 1)
                        # Check if choice was made
                        if feat_index in self.build.feature_choices:
                            chosen = self.build.feature_choices[feat_index]
                            if choose_count > 1:
                                # Multiple choices needed
                                if isinstance(chosen, list):
                                    if len(chosen) != choose_count:
                                        return False
                                else:
                                    # Single value stored but multiple needed
                                    return False
                            else:
                                # Single choice needed
                                if isinstance(chosen, list):
                                    # List stored but single needed
                                    return False
                                elif not chosen:
                                    return False
                        else:
                            # No choice made for this feature
                            return False
            return True
        elif step_name == "abilities":
            # Check if all ability score bonuses are used
            # Can be +2 to one ability or +1 to two abilities
            total_used = sum(self.build.abilities.values())
            if self.build.ability_score_bonuses == 2:
                # Can be +2 to one or +1 to two
                return total_used == 2
            return total_used == self.build.ability_score_bonuses
        elif step_name == "cantrips":
            # Check if required cantrips are selected
            spellcasting_info = self.level_data.get("spellcasting", {})
            cantrips_known = spellcasting_info.get("cantrips_known", 0)
            current_cantrips = len([s for s in self.player.sc.learned_spells if s.level == 0])
            needed = cantrips_known - current_cantrips
            return len(self.build.new_cantrips) >= needed
        elif step_name == "spells":
            # Check if required number of spells are selected
            return len(self.build.new_spells) == self.new_spells_count
        elif step_name == "proficiency_choices":
            # Check if required number of proficiencies are selected
            return len(self.build.proficiency_choices_selected) == self.proficiency_choose_count
        return True
        
    def _format_spell_tooltip(self, data: Dict[str, Any]) -> str:
        """Build tooltip text from spell JSON"""
        parts: List[str] = []
        desc = data.get("desc", [])
        if isinstance(desc, list):
            desc = " ".join(desc)
        if desc:
            parts.append(desc)
        range_val = data.get("range", "")
        if range_val:
            parts.append(f"Range: {range_val}")
        level = data.get("level", 0)
        parts.append(f"Level: {level}")
        return "\n".join(parts)
