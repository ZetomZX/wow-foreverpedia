# Changelog

This file records notable changes across Foreverpedia versions. The older
entries are based on available build archives. An entry identifies a build
and does not imply that it was publicly released.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses semantic version numbers for public releases.

## [Unreleased]

## [0.9.6] - 2026-11-26

### Fixed

- Alt-left-clicking an item hyperlink in chat now opens that item in
  Foreverpedia. Ordinary clicks and other link types retain their usual
  behavior.

## [0.9.5]

### Changed

- Refreshed recipe data and English and Russian item search for WoW Forever
  build `1.60.1.71139`. Each search index went from 19,400 to 19,403 items.
  The Totem of the Maelstrom is searchable by its new name.
- Added Centaur Hoofwarmers to the crafting index, bringing it to 8,479
  recipe–reagent links.

## [0.9.4]

### Changed

- Updated the client data to WoW Forever build `1.60.1.71037` and expanded
  English and Russian search to 19,400 items per language.
- Updated the built-in quest and item-source data to QuestieDB Forever
  `1.1.6`.

### Fixed

- Prevented the same lootable object from appearing twice when live QuestieDB
  and historical CMaNGOS data describe it with different location metadata.

## [0.9.3]

- Published the first GitHub release of the current addon baseline. This
  version packaged the item reference, bilingual search, crafting chains,
  gamepad navigation, and built-in data snapshot.

## [0.9.2]

- Added a draggable minimap button with a setting to hide it. Running `/fp`
  now focuses the manual search field, while `/fp <itemID>` still opens an
  item directly.
- Added class abilities to item uses, including reagent costs and spell
  details. Added notices when a newer addon version is detected.
- Updated the client data to WoW Forever build `1.60.1.70959` and expanded
  English and Russian search to 19,326 items per language.

## [0.9.1]

- Addon metadata update. The archived runtime files match `0.9.0`.

## [0.9.0]

- Added gamepad navigation, including an R3 hold to open an item and
  controller navigation in the item window and crafting graph.
- Added a built-in QuestieDB snapshot so core lookups work without the optional
  QuestieDB addon. Added supplementary acquisition sources such as
  disenchanting, pickpocketing, spell loot, and mail.
- Added local recipe observations from the profession window. Observations
  supplement the bundled recipe data.

## [0.8.0]

- Split the interface and static data into `Foreverpedia` and
  `Foreverpedia_Data`, which can be updated independently of player
  observations.

## [0.7.8]

- Updated the QuestieDB integration to Forever `1.0.16` and refreshed
  acquisition source data.

## [0.7.7]

- Aligned the crafting-chain button with the ingredient heading.

## [0.7.6]

- Added All, None, and Reset controls to the crafting profession filters.

## [0.7.5]

- Updated the language picker and added access to crafting chains from recipe
  details.

## [0.7.4]

- Updated the addon icon.

## [0.7.3]

- Updated the language selector to use a compact dropdown.

## [0.7.2]

- Added an Apply button to language settings and refined source icons in the
  crafting graph.

## [0.7.1]

- Improved automatic selection of the addon language based on the client
  locale.

## [0.7.0]

- Added English and Russian interface localization and localized item search.
- Added source icons to crafting-graph items.

## [0.6.4]

- Added quest faction and starter details, gathering sources, and quantity
  badges in the crafting graph.

## [0.6.3]

- Automatically enabled the relevant profession filter when opening a
  crafted item in the graph.

## [0.6.2]

- Improved layout and connection routing in crafting chains.

## [0.6.1]

- Added profession filters to the crafting graph and detected the character's
  current professions.

## [0.6.0]

- Added an optional recursive crafting-chain window and a setting for its
  button.

## [0.5.8]

- Added a configurable gamepad shortcut for opening the focused item.

## [0.5.7]

- Added an action for opening the currently focused gamepad item.

## [0.5.6]

- Improved compatibility for opening items from the gamepad bag menu and
  observing merchant prices.

## [0.5.5]

- Added Alt-left-click navigation from a recipe to its crafted item. Going
  back restores the previous selection, expanded groups, and scroll position.

## [0.5.4]

- Added a Foreverpedia action to the gamepad bag item menu.

## [0.5.3]

- Refined detection of reagent clicks in profession windows.

## [0.5.2]

- Added Alt-left-click support for reagents in profession windows.

## [0.5.1]

- Reworked the item page layout with tabs and separate list and detail panes.

## [0.5.0]

- Added client-wide item search and Back navigation.
- Added complete recipe ingredients based on client data for build
  `1.60.1.70888`.

## [0.4.4]

- Expanded fishing sources to distinguish open water from fishing pools and
  record observed catches.

## [0.4.3]

- Improved fishing source details, map waypoints, and return navigation from
  the world map.

## [0.4.2]

- Added clickable source coordinates and grouped recipe acquisition by source.

## [0.4.1]

- Earliest available build archive. It includes item lookups, recipes,
  acquisition sources, and local observations.
