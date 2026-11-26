# Foreverpedia

Foreverpedia is a WoW Forever item reference inspired by Factorio's
Factoriopedia. Hold `Alt` and left-click an item link or an item in a bag to
open a separate window with categorized uses and acquisition sources.

The window also has a client-wide item search with autocomplete. Use `Options`
to switch the interface and every displayed/searchable item name between the
pinned `ruRU` and `enUS` client indexes; changing the language reloads the UI.
Recipe details show every ingredient; hold `Alt` and left-click an ingredient
to open its own Foreverpedia page, then use the Back button to return.

The base release contains the lightweight `Foreverpedia` interface addon and
the versioned `Foreverpedia_Data` static database addon. The data addon includes
a compact QuestieDB snapshot, so QuestieDB itself is optional. When a compatible
QuestieDB is installed, Foreverpedia automatically adds spawn coordinates,
quest faction/starter details, objective tooltips, and other extended data.
Without it, the window shows a small installation hint and continues to expose
the snapshot's quests, objects, vendors, containers, and creature sources.
Updating either Foreverpedia addon does not touch observations in
`ForeverpediaDB`.
The complete reagent index is generated directly from the WoW Forever client
DB2 tables for build `1.60.1.71139`, so recipes do not depend on the
character's learned professions. AtlasLoot is not used.

The same pinned client tables identify items consumed by class abilities.
Foreverpedia lists these uses by class, shows the localized spell tooltip, and
collapses duplicate ranks with the same localized spell name and reagent count.

Historical CMaNGOS indexes fill acquisition mechanisms that Questie does not
fully expose: disenchanting, pickpocketing, spell-created loot, mail rewards,
containers and lootable objects, as well as open-water and fishing-hole loot.
Actual Forever catches are learned locally as fishing sources as well.
When QuestieDB is present, its AreaIDs are converted through the Forever map
table before opening the map or placing a waypoint. Foreverpedia does not ship hand-authored
item-source exceptions; source relations must come from a versioned dataset or
an in-game observation.

## Install

Download the latest `Foreverpedia-<version>-WoW-Forever.zip` from
[GitHub Releases](https://github.com/ZetomZX/wow-foreverpedia/releases/latest)
and extract it into:

```text
World of Warcraft\_forever_\Interface\AddOns
```

On first launch, `ruRU` clients select Russian and `enUS`/`enGB` clients select
English automatically. Unknown or unavailable client locales fall back to
English. A manual language choice in `Options` is saved and takes priority.

The result must contain `AddOns\Foreverpedia` and
`AddOns\Foreverpedia_Data`. `Foreverpedia_Data` contains generated, read-only
indexes and deliberately has no SavedVariables. To enable extended information,
install QuestieDB separately. Restart the game after installing. Lua-only edits
can normally be tested with `/reload`.

For later independent updates, use
`Foreverpedia-<core-version>-Core.zip` to replace only the interface code or
`Foreverpedia_Data-<data-version>.zip` to replace only the generated database.
The `WoW-Forever` archive is the standalone clean-install package; the
QuestieDB addon is never embedded in Foreverpedia release archives.

## Use

- `Alt + left click` an item in a bag or an item link.
- Hold `R3` for 0.7 seconds on the gamepad-focused item. The watcher does not
  bind or consume R3, so a short press keeps its normal game action.
- In gamepad layout, Foreverpedia takes focus when it opens. `View` switches
  focus between the game and the still-visible addon window. Use the D-pad to
  move between the top bar, tabs, source/use list, and details; `A` selects,
  `B` goes back or closes, `X` switches between the top bar and content,
  `Y` opens the crafting chain, and `LB/RB` changes tabs. `LT/RT` switches
  focus between the list and details; in the crafting-chain window it changes
  tree depth. The footer legend and focus outline are hidden completely in
  mouse layout.
- `Alt + left click` a reagent in a profession or crafting window.
- `Alt + left click` a recipe in Foreverpedia to open its crafted result.
- Type an item name in the top search field and choose a suggestion.
- Click the movable button around the minimap, or enter `/fp`, to open the
  window with the search field focused. The button can be hidden either in
  Foreverpedia's `Options` panel or under the game's AddOns settings.
- `Alt + left click` a recipe ingredient to follow it; `< Назад` restores the
  previous item and tab.
- The `Uses` tab groups client-verified class abilities by class. Select an
  ability to see its spell tooltip and the number of items it consumes.
- Use the subtle `Цепочка крафта` button to open the optional recursive
  crafting graph. The graph opens only when requested and can be closed without
  changing the main item page. Its profession filters initially enable the current character's professions;
  every other profession remains available as a toggleable icon. Centering a
  crafted item automatically enables its production profession, while the
  selected item's first ingredient level is always visible. Leaf reagents use
  corner icons to summarize every available vendor, drop, object, fishing,
  herb, quest, gathering, disenchanting, pickpocketing, mail, spell, or
  container source. Multiple source types are shown together, with vendors
  first.
- `/fp 2589` opens Linen Cloth for the reference check.
- `/fp status` prints the client, database, and local observation status.
- Opening a profession window records the recipes currently exposed by the
  client. These observations supplement the versioned DB2 snapshot until the
  next data-addon update. The Options panel shows the active QuestieDB source,
  database/client builds, observation count, and live-recipe count.

## Development

The CSV files under `vendor/wago/1.60.1.71139` are pinned exports from
`wago.tools/db2`: `SpellReagents`, `SpellEffect`, `SkillLineAbility`, and
`SkillLine`, plus `ItemEffect`, `ItemXItemEffect`, and `ItemSparse` for recipe
items and prices (`ruRU`). The autocomplete/name index is generated from both
the `ruRU` and `enUS` ItemSparse exports of the same build.
Historical trainer and acquisition mappings come from the pinned GPL-3.0
CMaNGOS Classic DB. They include disenchanting, pickpocketing, spell loot,
mail, containers, objects, fishing, and professional gathering. The gathering index connects skinning loot
to skinnable creatures and mining/herbalism loot to their gathering objects;
the object IDs are retained so live QuestieDB coordinates can be grouped by
zone and counted as gathering points. Matching profession nodes are removed
from the generic object sources while genuine chests remain there.
actual Forever trainer visits are saved locally and take precedence. Generate
both indexes, test, and package with:

```powershell
python tools/build_recipe_database.py
python tools/build_search_database.py
python tools/build_source_database.py
python tools/build_questie_snapshot.py
python -m unittest discover -s tests -v
python tools/package_release.py
```

Runtime Lua specs are also executed automatically when a `lua` interpreter is
available on `PATH`; the Python suite still validates module load order on
machines without one.

The package step verifies QuestieDB `1.1.6`, its compact fallback snapshot,
producer commit and SHA-256,
the DB2 inputs, the generated client-name search index, the Linen Cloth
recipe/ingredient reference records, and the versioned boundary between
`Foreverpedia` and `Foreverpedia_Data`.

See [docs/DATA_ARCHITECTURE.md](docs/DATA_ARCHITECTURE.md) for provenance and
merge rules.

See [docs/RELEASE.md](docs/RELEASE.md) for versioning, changelog, packaging,
tagging, and GitHub Release instructions.

## License

Foreverpedia is distributed under the
[GNU General Public License v3.0 or later](LICENSE.md). Third-party data notices
are included with the Data addon.
