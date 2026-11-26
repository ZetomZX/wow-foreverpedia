# Foreverpedia data architecture

## Shipped data

Foreverpedia uses five complementary layers:

1. a compact built-in snapshot of QuestieDB Forever `1.1.6` for basic item,
   quest, NPC, object, vendor and container relations;
2. optional compatible QuestieDB Forever for full coordinates, quest metadata,
   localized entity data and tooltips;
3. client DB2 tables from WoW Forever build `1.60.1.71139` for every recipe;
4. local observations stored in `ForeverpediaDB` for loot, merchants,
   quest objectives/rewards, and recipes exposed by profession windows;
5. historical CMaNGOS Classic DB acquisition indexes, clearly marked as
   historical: trainers, disenchanting, pickpocketing, spell loot, mail,
   containers, objects, fishing and professional gathering.

Foreverpedia does not contain hand-authored item-source exceptions. New source
relations must be imported from a versioned dataset with provenance or observed
through the game API.

AtlasLoot is not a dependency or data source.

The release separates code and data into two addons. `Foreverpedia` owns the
UI, provider, observation collector, and the `ForeverpediaDB` SavedVariables.
`Foreverpedia_Data` owns the generated search, recipe, source, and compact
QuestieDB snapshot indexes and
has no SavedVariables. WoW loads the data addon first through a required
dependency; its bootstrap exposes a versioned schema that the core validates
before reading the indexes. This lets either addon be updated independently
without deleting observations collected by players.

Packaging produces separate core and data archives for incremental updates and
a standalone archive containing both required addons. QuestieDB is installed
separately. WoW stores player observations outside the addon folders, so they
survive component updates.

QuestieDB is pinned to producer commit
`4377c981ac368d1593ec92788218e0a689a6a02b`, contract `4`, SHA-256
`4d3e043e3c8d28014ec6f5d4d894d476769e1be99d060a174e14ca46038ebe50`.
To rebuild the indexes, download `QuestieDB-1.1.6-Forever.zip` and
`release.json` from the [upstream release](https://github.com/Questie/QuestieDB/releases/tag/v1.1.6).
Place them in `vendor/`, naming the manifest `QuestieDB-1.1.6-release.json`.

The client inputs are the `ruRU` exports of `SpellReagents`, `SpellEffect`,
`SkillLineAbility`, `SkillLine`, `ItemEffect`, `ItemXItemEffect`, and
`ItemSparse` from
`wago.tools/db2`.

## Build-time indexes

`tools/build_recipe_database.py` joins reagent spells to profession skill
lines and created items. It emits both reagent-first and recipe-first Lua
indexes, so unknown and unlearned recipes are available without opening a
profession window and every recipe can list its ingredients.

The same generator joins `SpellReagents` to category-7 `SkillLineAbility`
records with a non-zero class mask. It emits a separate item-first class
ability index containing spell ID, class mask, skill line and reagent count.
This contains 23 items and 76 relations in client build `1.60.1.71139`.
Spells without a verifiable class skill-line relation are omitted rather than
assigned through hand-authored exceptions.

`tools/build_search_database.py` converts the pinned client `ItemSparse`
exports into Russian and English name indexes. Autocomplete therefore covers
all 19,403 named items per locale in build `1.60.1.71139`, not only items
cached by the current character.

`tools/build_source_database.py` transforms QuestieDB's creature drop table
into an item-first index with no per-item cap. The index uses the base support
table. Questie's separate drop-correction module is outside the import. In addition,
`tools/build_questie_snapshot.py` extracts compact item relations and the
Russian/English names plus levels/zones of referenced entities. This is the
standalone runtime fallback. Optional QuestieDB enriches those relations with
spawn coordinates, race masks, quest starters and objective text.

The snapshot builder also reverse-indexes item objectives from Quest records.
This supplements QuestieDB's incomplete item-first `relatedQuests` field, and
the provider retains the generated relations even when optional QuestieDB is
loaded.

The same generator joins CMaNGOS `fishing_loot_template` with every game object
of type `FISHINGHOLE` and its `gameobject_loot_template`. The resulting 128-item
index intentionally includes non-fish catches: trunks, rum, Stranglekelp,
elemental materials, debris and tournament items. Fishing-pool names are
stored with the index because QuestieDB does not contain those pool objects.

The generator also builds a compact 119-item professional gathering index.
Skinning loot is joined through each creature's exact `SkinningLootId`;
mining and herbalism loot is joined through gathering game objects and their
shared lock definitions. This classifies resource families such as leather
scraps, ore, stone and herbs without maintaining one-off item overrides. These
relations retain their source entity IDs. At runtime, mining and herbalism
nodes use the compatible QuestieDB spawn tables to produce a per-zone point
count; those exact node IDs are suppressed from generic object and observed
loot relations, while unrelated chests and objects remain visible. The
relations are historical Classic Era evidence and are labelled accordingly in
the interface.

The same build pass audits every CMaNGOS loot table that represents an item
acquisition path. `disenchant_loot_template` is joined through each source
item's `DisenchantID` and summarized by quality and item-level band;
`pickpocketing_loot_template` is joined through exact creature templates.
Direct indexes for item containers, lootable objects, spell-created loot and
mail rewards fill relations that are missing from Questie's compact item
metadata. Stable entity IDs de-duplicate these rows at runtime, retaining the
richer Questie relation when both datasets describe the same source.

For Linen Cloth (`2589`) the reference dataset contains 12 recipes. It includes
spell `8339`, excludes spell `3115`, and contains every creature source known
to the pinned QuestieDB table.

Recipe learning sources join client `ItemEffect` relations to QuestieDB vendor,
drop, object and quest data. Trainer mappings come from pinned CMaNGOS commit
`22b51464f1625f6ef6275771de1f5466c6f5d19e`; these are historical Classic Era
leads, not claims about the Forever server. Opening a trainer window records
the real NPC and location for each matched recipe in `ForeverpediaDB`.

## Runtime merge

The core addon is split into narrow runtime layers. `Config.lua` owns client
contracts and bounded UI limits, `Util.lua` contains side-effect-free helpers,
`Storage.lua` owns observation persistence and schema migration, and
`Search.lua` owns locale-aware ranking. `Provider.lua` is the only module that
merges external databases into the relation model; UI modules consume that
model without reading QuestieDB directly. `Theme.lua` keeps shared visual
primitives out of the main window and crafting graph implementations.

The public namespace remains deliberately small: `DataProvider`, `Storage`,
`Search`, `CraftTree`, and `UI`. New source adapters should produce the same
relation records, implement a provider reader, and register it in
`DataProvider.RELATION_READERS` rather than adding source-specific branches to
the UI.

The provider selects either the compact snapshot facades or compatible live
QuestieDB APIs, then combines those relations with generated indexes and local
observations. Matching local loot observations
augment quantity and location instead of creating duplicate rows. Local facts
remain labelled as observations.

Profession-window observations store their client build, output item and
quantity, profession, and reagent list. They override the same recipe from the
older static snapshot and add recipes absent from that snapshot. The runtime
build is compared with the recipe-data build at login; a mismatch is reported
instead of silently presenting the snapshot as current.

Class-ability uses are static client facts rather than per-character
observations. The provider expands class masks into ordinary `uses` relations;
the UI groups them by localized class and collapses spell ranks that share the
same localized name and reagent quantity.

The compact snapshot supplies quest names, levels and zones. With QuestieDB
installed, quest relations are further enriched with race-mask faction,
starting NPC or object, spawn locations and objective text. The details panel
then shows clickable coordinates and the additional quest metadata.

The collector recognizes both the Fishing Bobber game object and all indexed
fishing holes. A recent successful Fishing cast is the fallback for Forever
clients that do not return a useful loot-source GUID; this also records custom
Forever fishing loot that is absent from the historical Classic database.

QuestieDB's support drop table does not contain stack ranges. The UI therefore
shows an unknown quantity until the local loot collector has observed it; it
never invents a numeric value from the drop chance.

The game client supplies current item and spell names, icons, quality and
tooltips. WoW addons cannot query web services or SQLite while running, so all
external transforms happen before packaging.

Questie spawn keys are AreaIDs, not map IDs. When QuestieDB is installed, the
UI resolves them through its `areaIdToUiMapId` support table before opening the
world map or setting a waypoint.

## Future staging database

SQLite remains appropriate for a future versioned Forever evidence store:

```text
items(id, build, locale, provenance)
entities(id, type, name, zone_id)
relations(item_id, direction, kind, entity_id, detail, chance, min_qty, max_qty)
sources(id, name, version, license, imported_at)
relation_sources(relation_id, source_id, source_key)
```

Only locale-specific compact Lua chunks are shipped to the game.
