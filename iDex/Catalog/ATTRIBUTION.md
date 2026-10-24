# Offline catalog and visual assets

The app bundles the original 151 Kanto species. Names, genera, English and simplified Chinese Pokédex text, types, height, weight, and base stats were fetched from the PokeAPI data repository on 24 October 2026:

- https://github.com/PokeAPI/pokeapi/tree/master/data/v2/csv
- API/data documentation: https://pokeapi.co/docs/v2

`Resources/pokemon-kanto.json` stores metric values (metres and kilograms). Descriptions use the latest available entry for each language in the upstream data. English and Chinese text can therefore come from different game versions. The catalog is bundled; browsing and speech require no API call.

Sprites were downloaded from the Pokémon Database's Black & White sprite archive, as requested. `Resources/sprite-sources.json` records the exact URL for every sprite. A PokeAPI sprite fallback is supported by the rebuild script for species whose Pokémon Database URL is unavailable.

- https://pokemondb.net/sprites
- https://img.pokemondb.net/sprites/black-white/normal/pikachu.png
- Fallback source: https://github.com/PokeAPI/sprites

Pokémon names, text, artwork and sprites are copyright and trademarks of Nintendo, Creatures Inc., and GAME FREAK inc. iDex is an unofficial fan project and is not endorsed by those companies. These assets require appropriate rights review before public commercial distribution.

Two locally bundled pixel fonts support both interface languages:

- **Press Start 2P**, The Press Start 2P Project Authors, SIL Open Font License 1.1. https://github.com/google/fonts/tree/main/ofl/pressstart2p
- **Fusion Pixel**, TakWolf and contributors, SIL Open Font License 1.1. Simplified Chinese, 12 px proportional OTF, release 2026.10.16. https://github.com/TakWolf/fusion-pixel-font

Full font license texts are bundled beside the font files. `PixelFont.register()` registers the fonts without modifying app metadata. At small sizes, use integer multiples of the source pixel grid for crisp rendering. Chinese font selection uses a Chinese-specific face rather than dropping all Chinese text into an unrelated system font.

To rebuild, run `python3 scripts/catalog/build_catalog.py` from the repository root. The script caches upstream CSVs and the font archive under `.catalog-cache/`, and skips sprite downloads that already exist. The compiled app performs no catalog or sprite downloads.
