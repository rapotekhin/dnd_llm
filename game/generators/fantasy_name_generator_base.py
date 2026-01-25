import FantasyNameGenerator.DnD as DnD
from typing import Optional

class FantasyNameGenerator:
    def __init__(self) -> None:

        # FantasyNameGenerator.DnD race index -> generator class name
        self._FNG_RACE_MAP = {
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

    def generate_random_name(self, race: str, gender: str) -> Optional[str]:
        """Generate a random fantasy name via FantasyNameGenerator, based on selected race."""
        gen_name = self._FNG_RACE_MAP.get(race, "Human")
        try:
            gen = getattr(DnD, gen_name, None)
            gender_class = getattr(gen, gen_name + "Type", None)
            if gender_class and gender == "male":
                gender = gender_class.Male
            elif gender_class and gender == "female":
                gender = gender_class.Female
            else:
                gender = None

            if gen is None:
                gen = DnD.Human
            return str(gen.generate(gender))
        except Exception:
            try:
                return str(DnD.Human())
            except Exception:
                return None

fantasy_name_generator = FantasyNameGenerator()