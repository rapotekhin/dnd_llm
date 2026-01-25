"""
DnD LLM Game - Entry Point
"""

import sys
from pathlib import Path

# Add paths for imports (runtime)
project_root = Path(__file__).parent.parent
game_dir = Path(__file__).parent
dnd_core_dir = project_root / "dnd-5e-core"
dnd_api_dir = project_root / "DnD-5th-Edition-API"

for path in [game_dir, dnd_core_dir, dnd_api_dir]:
    if path.exists() and str(path) not in sys.path:
        sys.path.insert(0, str(path))

from core.game import Game


def main():
    """Entry point"""
    game = Game()
    game.run()


if __name__ == "__main__":
    main()
