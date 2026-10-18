# SRD 5e source (API 2014)

JSON copy of the [D&D 5e SRD API](https://www.dnd5eapi.co) (`/api/2014`, project [5e-bits/5e-database](https://github.com/5e-bits/5e-database)).
The content is the System Reference Document 5.1 by Wizards of the Coast, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode).

`tools/srd_import.py build` reads it and writes `game/data/srd/` and the item catalog; the game never reads this folder.
It came from the pygame prototype (`legacy/game/dnd_5e_data/`, removed in v0.5.4).
