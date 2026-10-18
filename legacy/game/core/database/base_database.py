from typing import Any

class BaseDatabase:
    def __init__(self):
        self.db = None

    def get(self, name: str) -> Any:
        pass
