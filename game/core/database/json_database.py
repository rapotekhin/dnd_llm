f"""JSON Database
БД используется только для чтения!

В качестве источника данных используются JSON файлы.
Они были выкачаны из апи https://www.dnd5eapi.co/ и являются полным скрином их монго базы данных в жсон формате.
Данные лежат в `game/dnd_5e_data/api/2014`
Все ссылки в бд начинаются с `/api/2014`

Есть корневой фаил `game/dnd_5e_data/api/2014/_root.json` который является ответом на GET запрос к https://www.dnd5eapi.co/api/2014/ и может быть использован как стартовая точка для бд.
"""


from .base_database import BaseDatabase
import os
import json
from typing import Any


class JsonDatabase(BaseDatabase):
    def __init__(self):
        super().__init__()
        self.db = None

        self.base_path = os.path.join(os.path.dirname(__file__), "..", "..", "dnd_5e_data", "api", "2014")

    def get(self, url: str) -> Any:

        if "/api/2014" in url:
            url = url.replace("/api/2014", "")
        
        # Remove leading slash for proper path joining
        url = url.lstrip("/")
        
        file_path = os.path.join(self.base_path, url)
        if os.path.isfile(file_path):
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            return data
        else:
            raise ValueError(f"File {file_path} not found")

    def get_all(self, name: str) -> Any:

        assert name in [
            'ability-scores', 'alignments', 'backgrounds', 'classes', 'conditions', 
            'damage-types', 'equipment', 'equipment-categories', 'feats', 'features', 
            'languages', 'magic-items', 'magic-schools', 'monsters', 'proficiencies', 
            'races', 'rule-sections', 'rules', 'skills', 'spells', 'subclasses', 
            'subraces', 'traits', 'weapon-properties'], f"Invalid name: {name}"
        
        list_of_dirs = os.listdir(os.path.join(self.base_path, name))
        dict_of_data = {}
        for file in list_of_dirs:
            if file.endswith('.json'):

                with open(os.path.join(self.base_path, name, file), 'r') as f:
                    data = json.load(f)

                dict_of_data[file.replace('.json', '')] = data

        return dict_of_data
