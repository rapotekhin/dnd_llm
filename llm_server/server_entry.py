"""The entry point of the frozen server.exe: a script outside the package, so its relative imports work."""

from llm_server.__main__ import main

if __name__ == "__main__":
    main()
