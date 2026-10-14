# DOOM in Pokémon Red (Game Boy)

Adds a **DOOM** entry to the main menu of [pret/pokered](https://github.com/pret/pokered): a small raycaster in SM83 assembly
(Pokémon sprites as enemies, Red's face HUD, gun sprite) plus E1M1 music played on the GB sound channels.

- `engine/doom/doom.asm` – game engine; `engine/doom/doom_music.asm` – music driver
- `tools/gen_doom.py`, `tools/gen_doom_music.py` – generate `gfx/doom/*` (tiles, tables, song data)
- Build the ROM as usual: `make` (needs rgbds) -> `pokered.gbc`. You must supply your own legal copy of nothing: it builds from source.
- `mac/` – optional static recompiler + SDL2 runtime to play the ROM natively on macOS (`cd mac && make`).

Controls: D-pad move/turn, A shoot, B/Select exit. Doom music © id Software / Bobby Prince; personal/educational use.
