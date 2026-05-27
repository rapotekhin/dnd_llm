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

# Configure logging before anything else imports, so library modules pick up
# the root handler and our excepthooks are in place before any thread spawns.
from core.logging_config import configure_logging, get_logger  # noqa: E402

configure_logging()

from core.game import Game  # noqa: E402


def main():
    """Entry point"""
    log = get_logger("game.main")
    log.info("starting Between the Rolls")
    try:
        game = Game()
        game.run()
    except Exception:
        log.exception("fatal error in main")
        raise


if __name__ == "__main__":
    main()
