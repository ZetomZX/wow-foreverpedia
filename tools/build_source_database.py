#!/usr/bin/env python3
"""Build a complete, sorted item -> creature drop index from QuestieDB."""

from __future__ import annotations

import hashlib
import gzip
from pathlib import Path
import re
import zipfile


ROOT = Path(__file__).resolve().parents[1]
QUESTIEDB_VERSION = "1.0.16"
QUESTIEDB_FILENAME = f"QuestieDB-{QUESTIEDB_VERSION}-Forever.zip"
DROP_ENTRY = "QuestieDB/support/Forever/DropTables/classicItemDrops.lua"
CMANGOS_PATH = ROOT / "vendor" / "cmangos" / "ClassicDB_1_12_1_z2815.sql.gz"
CMANGOS_SHA256 = "4f92db520868ab4e566726f68b5b2e380ae781209beaf22237b4f7f04600d0c0"
ITEM_PATTERN = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{(?:\s*--.*)?$")
DROP_PATTERN = re.compile(r"^\s*\[(\d+)\]\s*=\s*([0-9.]+),")

FISHING_POOL_NAMES_RU = {
    "School of Fish": "Косяк рыбы",
    "School of Tastyfish": "Косяк вкуснорыбы",
    "Muddy Churning Waters": "Мутные воды",
    "Oily Blackmouth School": "Косяк масляного черноротика",
    "Floating Debris": "Плавающие обломки",
    "Sagefish School": "Косяк шалфокуня",
    "Firefin Snapper School": "Косяк огнеперого луциана",
    "School of Deviate Fish": "Косяк загадочной рыбы",
    "Oil Spill": "Нефтяное пятно",
    "Floating Wreckage": "Плавающие обломки",
    "Greater Sagefish School": "Косяк большого шалфокуня",
    "Stonescale Eel Swarm": "Косяк каменного угря",
    "Patch of Elemental Water": "Вода стихий",
    "Strange Pool": "Странный водоём",
}

MINING_SKILL_ID = 186
HERBALISM_SKILL_ID = 182
SKINNING_SKILL_ID = 393
MINING_OBJECT_RE = re.compile(r"\b(?:vein|deposit)\b", re.IGNORECASE)
CLASSIC_HERB_OBJECT_NAMES = frozenset({
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn",
    "Bruiseweed", "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot",
    "Fadeleaf", "Goldthorn", "Khadgar's Whisker", "Wintersbite", "Firebloom",
    "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom",
    "Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage",
    "Plaguebloom", "Icecap", "Black Lotus", "Stranglekelp",
})


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_drop_table(source: str) -> tuple[dict[int, list[tuple[int, float, int, int]]], int]:
    items: dict[int, list[tuple[int, float, int, int]]] = {}
    current_item: int | None = None
    total = 0
    for line in source.splitlines():
        item_match = ITEM_PATTERN.match(line)
        if item_match:
            current_item = int(item_match.group(1))
            continue
        if current_item is not None:
            drop_match = DROP_PATTERN.match(line)
            if drop_match:
                items.setdefault(current_item, []).append(
                    # QuestieDB's support table contains chance but no stack
                    # range. Zero means "unknown" until an in-game loot
                    # observation supplies a real quantity.
                    (int(drop_match.group(1)), float(drop_match.group(2)), 0, 0)
                )
                total += 1
            elif line.strip() == "},":
                current_item = None
    for item_id, drops in items.items():
        # Lua keeps the final value when the upstream literal repeats an NPC
        # key. Mirror that behavior before sorting so the UI never duplicates
        # a creature source.
        unique = {drop[0]: drop for drop in drops}
        ordered = list(unique.values())
        ordered.sort(key=lambda value: (-value[1], value[0]))
        items[item_id] = ordered
    return items, total


def split_sql_values(line: str, start: int):
    index, depth, field, row, quoted, escaped = start, 0, [], [], False, False
    while index < len(line):
        char = line[index]
        index += 1
        if quoted:
            if escaped:
                field.append(char)
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "'":
                quoted = False
            else:
                field.append(char)
            continue
        if char == "'": quoted = True
        elif char == "(": depth, field, row = depth + 1, [], []
        elif char == ")" and depth:
            depth -= 1
            row.append("".join(field).strip())
            yield row
            field = []
        elif char == "," and depth == 1:
            row.append("".join(field).strip())
            field = []
        elif depth: field.append(char)


def parse_sql_tables(
    path: Path, wanted: set[str]
) -> tuple[dict[str, list[str]], dict[str, list[list[str]]]]:
    if sha256(path) != CMANGOS_SHA256:
        raise ValueError("CMaNGOS source checksum mismatch")
    columns: dict[str, list[str]] = {}
    rows: dict[str, list[list[str]]] = {name: [] for name in wanted}
    pending = None
    create_re = re.compile(r"^CREATE TABLE `([a-z_]+)` \(")
    column_re = re.compile(r"^\s*`([A-Za-z_0-9]+)`")
    insert_re = re.compile(r"^INSERT INTO `([a-z_]+)` VALUES ")
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if pending:
                if line.startswith(")"):
                    pending = None
                else:
                    match = column_re.match(line)
                    if match: columns[pending].append(match.group(1))
                continue
            created = create_re.match(line)
            if created:
                pending = created.group(1) if created.group(1) in wanted else None
                if pending: columns[pending] = []
                continue
            inserted = insert_re.match(line)
            if inserted and inserted.group(1) in wanted:
                rows[inserted.group(1)].extend(split_sql_values(line, inserted.end()))
    return columns, rows


def decode_loot_row(
    columns: dict[str, list[str]], table: str, row: list[str]
) -> tuple[int, int, float, int, int, int]:
    positions = {name: pos for pos, name in enumerate(columns[table])}

    def number(name: str) -> float:
        value = row[positions[name]]
        return 0 if value in ("", "NULL") else float(value)

    return (
        int(number("entry")),
        int(number("item")),
        number("ChanceOrQuestChance"),
        int(number("groupid")),
        int(number("mincountOrRef")),
        int(number("maxcount")),
    )


def reference_loot_rows(
    columns: dict[str, list[str]], rows: dict[str, list[list[str]]]
) -> dict[int, list[tuple[int, int, float, int, int, int]]]:
    references: dict[int, list[tuple[int, int, float, int, int, int]]] = {}
    for row in rows["reference_loot_template"]:
        value = decode_loot_row(columns, "reference_loot_template", row)
        references.setdefault(value[0], []).append(value)
    return references


def expand_loot_row(
    value: tuple[int, int, float, int, int, int],
    references: dict[int, list[tuple[int, int, float, int, int, int]]],
    parent_chance: float | None = None,
    visited: frozenset[int] = frozenset(),
):
    _, item_id, chance, _, minimum, maximum = value
    if minimum < 0:
        reference_id = -minimum
        if reference_id in visited:
            return
        for child in references.get(reference_id, []):
            yield from expand_loot_row(
                child, references, chance, visited | {reference_id}
            )
        return
    if item_id <= 0 or minimum <= 0:
        return
    effective = abs(chance)
    if parent_chance and effective > 0 and parent_chance < 100:
        effective = parent_chance * effective / 100
    yield item_id, effective, max(0, minimum), max(0, maximum)


def parse_supplemental_sources(path: Path) -> dict[str, dict]:
    """Read acquisition mechanisms omitted by Questie's item relations.

    The direct CMaNGOS indexes also cover object and container relations that
    are absent from QuestieDB. Runtime de-duplication keeps Questie's richer
    localized relation whenever both sources describe the same entity.
    """
    wanted = {
        "creature_template",
        "disenchant_loot_template",
        "gameobject_loot_template",
        "gameobject_template",
        "item_loot_template",
        "item_template",
        "mail_loot_template",
        "pickpocketing_loot_template",
        "reference_loot_template",
        "spell_loot_template",
    }
    columns, rows = parse_sql_tables(path, wanted)
    references = reference_loot_rows(columns, rows)

    def source_index(
        table: str, sources_by_entry: dict[int, set[int]] | None = None
    ) -> dict[int, list[tuple[int, float, int, int]]]:
        indexed: dict[int, dict[int, list[float | int]]] = {}
        for row in rows[table]:
            value = decode_loot_row(columns, table, row)
            source_ids = sources_by_entry.get(value[0], set()) if sources_by_entry else {value[0]}
            if not source_ids:
                continue
            for item_id, chance, minimum, maximum in expand_loot_row(value, references):
                target = indexed.setdefault(item_id, {})
                for source_id in source_ids:
                    current = target.get(source_id)
                    if current:
                        current[0] = max(float(current[0]), chance)
                        current[1] = min(int(current[1]), minimum)
                        current[2] = max(int(current[2]), maximum)
                    else:
                        target[source_id] = [chance, minimum, maximum]
        return {
            item_id: sorted(
                (
                    source_id,
                    float(values[0]),
                    int(values[1]),
                    int(values[2]),
                )
                for source_id, values in sources.items()
            )
            for item_id, sources in sorted(indexed.items())
        }

    creature_positions = {
        name: pos for pos, name in enumerate(columns["creature_template"])
    }
    pickpocket_templates: dict[int, set[int]] = {}
    npc_names: dict[int, str] = {}
    for row in rows["creature_template"]:
        loot_id = int(row[creature_positions["PickpocketLootId"]] or 0)
        if loot_id <= 0:
            continue
        npc_id = int(row[creature_positions["Entry"]])
        pickpocket_templates.setdefault(loot_id, set()).add(npc_id)
        npc_names[npc_id] = row[creature_positions["Name"]]

    object_positions = {
        name: pos for pos, name in enumerate(columns["gameobject_template"])
    }
    object_templates: dict[int, set[int]] = {}
    object_names: dict[int, str] = {}
    for row in rows["gameobject_template"]:
        # Type 25 is a fishing pool and already has a richer dedicated index.
        if int(row[object_positions["type"]] or 0) == 25:
            continue
        loot_id = int(row[object_positions["data1"]] or 0)
        if loot_id <= 0:
            continue
        object_id = int(row[object_positions["entry"]])
        object_templates.setdefault(loot_id, set()).add(object_id)
        object_names[object_id] = row[object_positions["name"]]

    item_positions = {
        name: pos for pos, name in enumerate(columns["item_template"])
    }
    disenchant_profiles: dict[int, dict[int, dict[str, int | set[int]]]] = {}
    for row in rows["item_template"]:
        disenchant_id = int(row[item_positions["DisenchantID"]] or 0)
        if disenchant_id <= 0:
            continue
        quality = int(row[item_positions["Quality"]] or 0)
        item_level = int(row[item_positions["ItemLevel"]] or 0)
        item_id = int(row[item_positions["entry"]])
        profile = disenchant_profiles.setdefault(disenchant_id, {}).setdefault(
            quality,
            {"minimumLevel": item_level, "maximumLevel": item_level, "items": set()},
        )
        profile["minimumLevel"] = min(int(profile["minimumLevel"]), item_level)
        profile["maximumLevel"] = max(int(profile["maximumLevel"]), item_level)
        profile["items"].add(item_id)  # type: ignore[union-attr]

    disenchant_aggregate: dict[int, dict[tuple[int, int, int], dict[str, object]]] = {}
    for row in rows["disenchant_loot_template"]:
        value = decode_loot_row(columns, "disenchant_loot_template", row)
        profiles = disenchant_profiles.get(value[0], {})
        for item_id, chance, minimum, maximum in expand_loot_row(value, references):
            for quality, profile in profiles.items():
                key = (
                    quality,
                    int(profile["minimumLevel"]),
                    int(profile["maximumLevel"]),
                )
                aggregate = disenchant_aggregate.setdefault(item_id, {}).setdefault(
                    key,
                    {
                        "items": set(),
                        "chances": [],
                        "minimumQuantity": minimum,
                        "maximumQuantity": maximum,
                    },
                )
                aggregate["items"].update(profile["items"])  # type: ignore[union-attr]
                if chance > 0:
                    aggregate["chances"].append(chance)  # type: ignore[union-attr]
                aggregate["minimumQuantity"] = min(
                    int(aggregate["minimumQuantity"]), minimum
                )
                aggregate["maximumQuantity"] = max(
                    int(aggregate["maximumQuantity"]), maximum
                )

    disenchant: dict[int, list[tuple[int, int, int, int, float, float, int, int]]] = {}
    for item_id, groups in sorted(disenchant_aggregate.items()):
        encoded = []
        for (quality, minimum_level, maximum_level), aggregate in sorted(groups.items()):
            chances = aggregate["chances"]
            encoded.append((
                quality,
                minimum_level,
                maximum_level,
                len(aggregate["items"]),  # type: ignore[arg-type]
                min(chances) if chances else 0,  # type: ignore[arg-type]
                max(chances) if chances else 0,  # type: ignore[arg-type]
                int(aggregate["minimumQuantity"]),
                int(aggregate["maximumQuantity"]),
            ))
        disenchant[item_id] = encoded

    pickpocket = source_index("pickpocketing_loot_template", pickpocket_templates)
    objects = source_index("gameobject_loot_template", object_templates)
    used_npcs = {
        source_id
        for sources in pickpocket.values()
        for source_id, _, _, _ in sources
    }
    used_objects = {
        source_id
        for sources in objects.values()
        for source_id, _, _, _ in sources
    }
    return {
        "containers": source_index("item_loot_template"),
        "disenchant": disenchant,
        "mail": source_index("mail_loot_template"),
        "objects": objects,
        "objectNames": {key: value for key, value in object_names.items() if key in used_objects},
        "pickpocket": pickpocket,
        "npcNames": {key: value for key, value in npc_names.items() if key in used_npcs},
        "spellLoot": source_index("spell_loot_template"),
    }


def parse_fishing_data(path: Path) -> tuple[
    dict[int, list[tuple[int, float, int, int]]],
    dict[int, list[tuple[int, float, int, int]]],
    dict[int, str],
]:
    wanted = {
        "fishing_loot_template",
        "gameobject_loot_template",
        "gameobject_template",
        "reference_loot_template",
    }
    columns, rows = parse_sql_tables(path, wanted)

    def decode(table: str, row: list[str]) -> tuple[int, int, float, int, int, int]:
        positions = {name: pos for pos, name in enumerate(columns[table])}
        def number(name: str) -> float:
            value = row[positions[name]]
            return 0 if value in ("", "NULL") else float(value)
        return (int(number("entry")), int(number("item")), number("ChanceOrQuestChance"),
                int(number("groupid")), int(number("mincountOrRef")), int(number("maxcount")))

    references: dict[int, list[tuple[int, int, float, int, int, int]]] = {}
    for row in rows["reference_loot_template"]:
        value = decode("reference_loot_template", row)
        references.setdefault(value[0], []).append(value)

    def expand(
        value: tuple[int, int, float, int, int, int],
        parent_chance: float | None = None,
        visited: frozenset[int] = frozenset(),
    ):
        entry, item_id, chance, group, minimum, maximum = value
        if minimum < 0:
            reference_id = -minimum
            if reference_id in visited:
                return
            for child in references.get(reference_id, []):
                yield from expand(child, chance, visited | {reference_id})
            return
        if item_id <= 0 or minimum <= 0:
            return
        effective = abs(chance)
        if parent_chance and effective > 0 and parent_chance < 100:
            effective = parent_chance * effective / 100
        yield item_id, effective, minimum, maximum

    result: dict[int, list[tuple[int, float, int, int]]] = {}
    for row in rows["fishing_loot_template"]:
        value = decode("fishing_loot_template", row)
        area_id = value[0]
        for child_item, effective, child_min, child_max in expand(value):
            result.setdefault(child_item, []).append(
                (area_id, effective, max(0, child_min), max(0, child_max))
            )
    for item_id, sources in result.items():
        unique = {(source[0], source[2], source[3]): source for source in sources}
        result[item_id] = sorted(unique.values(), key=lambda value: (-value[1], value[0]))

    template_positions = {
        name: pos for pos, name in enumerate(columns["gameobject_template"])
    }
    pool_templates: dict[int, list[tuple[int, str]]] = {}
    for row in rows["gameobject_template"]:
        if int(row[template_positions["type"]] or 0) != 25:
            continue
        object_id = int(row[template_positions["entry"]])
        loot_id = int(row[template_positions["data1"]] or 0)
        if loot_id > 0:
            pool_templates.setdefault(loot_id, []).append(
                (object_id, row[template_positions["name"]])
            )

    pools: dict[int, list[tuple[int, float, int, int]]] = {}
    pool_names: dict[int, str] = {}
    for row in rows["gameobject_loot_template"]:
        value = decode("gameobject_loot_template", row)
        matching_pools = pool_templates.get(value[0])
        if not matching_pools:
            continue
        expanded = list(expand(value))
        for object_id, english_name in matching_pools:
            pool_names[object_id] = FISHING_POOL_NAMES_RU.get(english_name, english_name)
            for item_id, chance, minimum, maximum in expanded:
                pools.setdefault(item_id, []).append(
                    (object_id, chance, max(0, minimum), max(0, maximum))
                )
    for item_id, sources in pools.items():
        # Several database templates represent the same visible school in
        # different level bands. Keep one row per visible source instead of
        # showing duplicate school names to the player; retain every object ID
        # in fishingPoolNames so runtime loot detection still recognizes them.
        unique = {
            (pool_names[source[0]], source[1], source[2], source[3]): source
            for source in reversed(sources)
        }
        pools[item_id] = sorted(unique.values(), key=lambda value: (-value[1], value[0]))
    return result, pools, pool_names


def parse_fishing_sources(path: Path) -> dict[int, list[tuple[int, float, int, int]]]:
    return parse_fishing_data(path)[0]


def parse_gathering_data(path: Path) -> dict[int, list[tuple[int, tuple[int, ...]]]]:
    """Return item -> (profession skill line, distinct source entity IDs).

    Entity IDs are retained instead of only storing their count so the runtime
    can resolve spawn locations and distinguish profession nodes from ordinary
    lootable objects that happen to contain the same item.
    """
    wanted = {
        "skinning_loot_template",
        "creature_template",
        "gameobject_loot_template",
        "gameobject_template",
        "reference_loot_template",
    }
    columns, rows = parse_sql_tables(path, wanted)

    def decode(table: str, row: list[str]) -> tuple[int, int, float, int, int, int]:
        positions = {name: pos for pos, name in enumerate(columns[table])}

        def number(name: str) -> float:
            value = row[positions[name]]
            return 0 if value in ("", "NULL") else float(value)

        return (
            int(number("entry")),
            int(number("item")),
            number("ChanceOrQuestChance"),
            int(number("groupid")),
            int(number("mincountOrRef")),
            int(number("maxcount")),
        )

    references: dict[int, list[tuple[int, int, float, int, int, int]]] = {}
    for row in rows["reference_loot_template"]:
        value = decode("reference_loot_template", row)
        references.setdefault(value[0], []).append(value)

    def expand(
        value: tuple[int, int, float, int, int, int],
        visited: frozenset[int] = frozenset(),
    ):
        _, item_id, _, _, minimum, _ = value
        if minimum < 0:
            reference_id = -minimum
            if reference_id in visited:
                return
            for child in references.get(reference_id, []):
                yield from expand(child, visited | {reference_id})
            return
        if item_id > 0 and minimum > 0:
            yield item_id

    sources: dict[int, dict[int, set[int]]] = {}

    creature_positions = {
        name: pos for pos, name in enumerate(columns["creature_template"])
    }
    skinning_templates: dict[int, set[int]] = {}
    for row in rows["creature_template"]:
        loot_id = int(row[creature_positions["SkinningLootId"]] or 0)
        if loot_id > 0:
            creature_id = int(row[creature_positions["Entry"]])
            skinning_templates.setdefault(loot_id, set()).add(creature_id)
    for row in rows["skinning_loot_template"]:
        value = decode("skinning_loot_template", row)
        for item_id in expand(value):
            sources.setdefault(item_id, {}).setdefault(SKINNING_SKILL_ID, set()).update(
                skinning_templates.get(value[0], set())
            )

    object_positions = {
        name: pos for pos, name in enumerate(columns["gameobject_template"])
    }
    templates = []
    mining_locks, herbalism_locks = set(), set()
    for row in rows["gameobject_template"]:
        if int(row[object_positions["type"]] or 0) != 3:
            continue
        object_id = int(row[object_positions["entry"]])
        name = row[object_positions["name"]]
        lock_id = int(row[object_positions["data0"]] or 0)
        loot_id = int(row[object_positions["data1"]] or 0)
        if loot_id <= 0:
            continue
        templates.append((object_id, name, lock_id, loot_id))
        if MINING_OBJECT_RE.search(name):
            mining_locks.add(lock_id)
        if name in CLASSIC_HERB_OBJECT_NAMES:
            herbalism_locks.add(lock_id)

    gathering_templates: dict[int, list[tuple[int, int]]] = {}
    for object_id, _, lock_id, loot_id in templates:
        profession_id = None
        if lock_id in mining_locks:
            profession_id = MINING_SKILL_ID
        elif lock_id in herbalism_locks:
            profession_id = HERBALISM_SKILL_ID
        if profession_id:
            gathering_templates.setdefault(loot_id, []).append((profession_id, object_id))

    for row in rows["gameobject_loot_template"]:
        value = decode("gameobject_loot_template", row)
        matches = gathering_templates.get(value[0], [])
        if not matches:
            continue
        for item_id in expand(value):
            for profession_id, object_id in matches:
                sources.setdefault(item_id, {}).setdefault(profession_id, set()).add(object_id)

    return {
        item_id: sorted(
            (profession_id, tuple(sorted(entity_ids)))
            for profession_id, entity_ids in professions.items()
        )
        for item_id, professions in sorted(sources.items())
    }


def build_lua(
    items: dict[int, list[tuple[int, float, int, int]]],
    source_hash: str,
    total_relations: int,
    fishing: dict[int, list[tuple[int, float, int, int]]] | None = None,
    fishing_pools: dict[int, list[tuple[int, float, int, int]]] | None = None,
    fishing_pool_names: dict[int, str] | None = None,
    gathering: dict[int, list[tuple[int, tuple[int, ...]]]] | None = None,
    supplemental: dict[str, dict] | None = None,
) -> str:
    fishing = fishing or {}
    fishing_pools = fishing_pools or {}
    fishing_pool_names = fishing_pool_names or {}
    gathering = gathering or {}
    supplemental = supplemental or {}
    containers = supplemental.get("containers", {})
    disenchant = supplemental.get("disenchant", {})
    mail = supplemental.get("mail", {})
    objects = supplemental.get("objects", {})
    pickpocket = supplemental.get("pickpocket", {})
    spell_loot = supplemental.get("spellLoot", {})
    retained = sum(map(len, items.values()))
    lines = [
        "local _, Data = ...",
        "",
        "-- Generated by tools/build_source_database.py; do not edit by hand.",
        "-- Sources: QuestieDB GPL-3.0 and CMaNGOS ClassicDB GPL-2.0.",
        "Data.SourceData = {",
        "    manifest = {",
        '        source = "QuestieDB",',
        f'        version = "{QUESTIEDB_VERSION}",',
        f'        sha256 = "{source_hash}",',
        "        unlimitedDrops = true,",
        f"        itemCount = {len(items)},",
        f"        relationCount = {retained},",
        f"        sourceRelationCount = {total_relations},",
        f"        fishingItemCount = {len(set(fishing) | set(fishing_pools))},",
        f"        fishingRelationCount = {sum(map(len, fishing.values())) + sum(map(len, fishing_pools.values()))},",
        f"        gatheringItemCount = {len(gathering)},",
        f"        gatheringRelationCount = {sum(map(len, gathering.values()))},",
        f"        objectItemCount = {len(objects)},",
        f"        objectRelationCount = {sum(map(len, objects.values()))},",
        f"        containerItemCount = {len(containers)},",
        f"        containerRelationCount = {sum(map(len, containers.values()))},",
        f"        disenchantItemCount = {len(disenchant)},",
        f"        disenchantRelationCount = {sum(map(len, disenchant.values()))},",
        f"        pickpocketItemCount = {len(pickpocket)},",
        f"        pickpocketRelationCount = {sum(map(len, pickpocket.values()))},",
        f"        spellLootItemCount = {len(spell_loot)},",
        f"        spellLootRelationCount = {sum(map(len, spell_loot.values()))},",
        f"        mailItemCount = {len(mail)},",
        f"        mailRelationCount = {sum(map(len, mail.values()))},",
        "    },",
        "    drops = {",
    ]
    for item_id, drops in sorted(items.items()):
        encoded = ",".join(
            "{%d,%s,%d,%d}" % (npc_id, format(chance, ".6g"), minimum, maximum)
            for npc_id, chance, minimum, maximum in drops
        )
        lines.append(f"        [{item_id}] = {{{encoded}}},")
    lines.extend(["    },", "    fishing = {"])
    for item_id, sources in sorted(fishing.items()):
        encoded = ",".join(
            "{%d,%s,%d,%d}" % (area_id, format(chance, ".6g"), minimum, maximum)
            for area_id, chance, minimum, maximum in sources
        )
        lines.append(f"        [{item_id}] = {{{encoded}}},")
    lines.extend(["    },", "    fishingPools = {"])
    for item_id, sources in sorted(fishing_pools.items()):
        encoded = ",".join(
            "{%d,%s,%d,%d}" % (object_id, format(chance, ".6g"), minimum, maximum)
            for object_id, chance, minimum, maximum in sources
        )
        lines.append(f"        [{item_id}] = {{{encoded}}},")
    lines.extend(["    },", "    fishingPoolNames = {"])
    for object_id, name in sorted(fishing_pool_names.items()):
        escaped = name.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'        [{object_id}] = "{escaped}",')
    lines.extend(["    },", "    gathering = {"])
    for item_id, sources in sorted(gathering.items()):
        encoded = ",".join(
            "{%d,{%s}}" % (
                profession_id,
                ",".join(str(entity_id) for entity_id in entity_ids),
            )
            for profession_id, entity_ids in sources
        )
        lines.append(f"        [{item_id}] = {{{encoded}}},")

    def append_source_index(key: str, index: dict) -> None:
        lines.extend(["    },", f"    {key} = {{"])
        for item_id, sources in sorted(index.items()):
            encoded = ",".join(
                "{%d,%s,%d,%d}" % (
                    source_id, format(chance, ".6g"), minimum, maximum
                )
                for source_id, chance, minimum, maximum in sources
            )
            lines.append(f"        [{item_id}] = {{{encoded}}},")

    append_source_index("objects", objects)
    append_source_index("containers", containers)
    append_source_index("pickpocket", pickpocket)
    append_source_index("spellLoot", spell_loot)
    append_source_index("mail", mail)

    lines.extend(["    },", "    disenchant = {"])
    for item_id, sources in sorted(disenchant.items()):
        encoded = ",".join(
            "{%d,%d,%d,%d,%s,%s,%d,%d}" % (
                quality, minimum_level, maximum_level, source_count,
                format(minimum_chance, ".6g"), format(maximum_chance, ".6g"),
                minimum_quantity, maximum_quantity,
            )
            for quality, minimum_level, maximum_level, source_count,
                minimum_chance, maximum_chance, minimum_quantity, maximum_quantity
            in sources
        )
        lines.append(f"        [{item_id}] = {{{encoded}}},")

    for key in ("npcNames", "objectNames"):
        lines.extend(["    },", f"    {key} = {{"])
        for entity_id, name in sorted(supplemental.get(key, {}).items()):
            escaped = name.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'        [{entity_id}] = "{escaped}",')
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def generate(
    archive_path: Path, output_path: Path, cmangos_path: Path = CMANGOS_PATH
) -> dict[int, list[tuple[int, float, int, int]]]:
    with zipfile.ZipFile(archive_path) as archive:
        source = archive.read(DROP_ENTRY).decode("utf-8")
    items, total = parse_drop_table(source)
    fishing, fishing_pools, fishing_pool_names = parse_fishing_data(cmangos_path)
    gathering = parse_gathering_data(cmangos_path)
    supplemental = parse_supplemental_sources(cmangos_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        build_lua(items, sha256(archive_path), total, fishing, fishing_pools,
                  fishing_pool_names, gathering, supplemental),
        encoding="utf-8", newline="\n"
    )
    return items


if __name__ == "__main__":
    data = generate(
        ROOT / "vendor" / QUESTIEDB_FILENAME,
        ROOT / "Foreverpedia_Data" / "Sources.lua",
    )
    print(f"Generated complete acquisition indexes for {len(data)} creature-drop items")
