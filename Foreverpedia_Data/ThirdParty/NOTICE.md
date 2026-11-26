# Third-party data notice

`Sources.lua` and `QuestieSnapshot.lua` are compact transforms of QuestieDB
Forever `1.1.6` data, plus the CMaNGOS Classic open-water and
fishing-hole loot tables. Both sources are distributed under GPL-3.0;
QuestieDB is an optional standalone addon. The
CMaNGOS copyright notice is included in `ThirdParty`.

Source: <https://github.com/Questie/QuestieDB>

`Recipes.lua`, including its recipe and class-ability reagent indexes, is
generated from the WoW Forever client DB2 tables
`SpellReagents`, `SpellEffect`, `SkillLineAbility`, `SkillLine`, `ItemEffect`,
`ItemXItemEffect`, and `ItemSparse`, build `1.60.1.71139`, locale `ruRU`, exported
through wago.tools. `Search.lua` uses the `ruRU` and `enUS` exports of
`ItemSparse` for the same build.

Source: <https://wago.tools/db2/>

The historical recipe trainer and fishing mappings are reduced derivations of
the CMaNGOS Classic content database at commit
`22b51464f1625f6ef6275771de1f5466c6f5d19e`, distributed under GPL-3.0.
Corresponding source: <https://github.com/Rockjaw-Bonesnapper-Co/itemtree-era-sources>.
WoW Forever may differ; observed trainers stored locally take precedence.

AtlasLoot is not used by this release.
