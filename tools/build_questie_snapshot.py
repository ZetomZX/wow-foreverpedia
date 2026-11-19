#!/usr/bin/env python3
"""Build the compact QuestieDB fallback used when QuestieDB is not installed."""

from __future__ import annotations

import base64
import hashlib
from pathlib import Path
import re
import struct
import zipfile
import zlib


ROOT = Path(__file__).resolve().parents[1]
QUESTIEDB_VERSION = "1.0.16"
QUESTIEDB_FILENAME = f"QuestieDB-{QUESTIEDB_VERSION}-Forever.zip"
TOC_ENTRY = "QuestieDB/QuestieDB_Forever.toc"
DROP_ENTRY = "QuestieDB/support/Forever/DropTables/classicItemDrops.lua"


class CborDecodeError(ValueError):
    pass


class CborReader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def take(self, size: int) -> bytes:
        end = self.offset + size
        if end > len(self.data):
            raise CborDecodeError("truncated CBOR value")
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def argument(self, additional: int) -> int:
        if additional < 24:
            return additional
        widths = {24: 1, 25: 2, 26: 4, 27: 8}
        width = widths.get(additional)
        if not width:
            raise CborDecodeError(f"unsupported CBOR argument {additional}")
        return int.from_bytes(self.take(width), "big")

    def read(self):
        initial = self.take(1)[0]
        major, additional = initial >> 5, initial & 31
        if major in (0, 1):
            value = self.argument(additional)
            return value if major == 0 else -1 - value
        if major in (2, 3):
            size = self.argument(additional)
            value = self.take(size)
            return value if major == 2 else value.decode("utf-8")
        if major == 4:
            return [self.read() for _ in range(self.argument(additional))]
        if major == 5:
            return {
                self.read(): self.read()
                for _ in range(self.argument(additional))
            }
        if major == 6:
            self.argument(additional)
            return self.read()
        if major == 7:
            if additional in (20, 21):
                return additional == 21
            if additional in (22, 23):
                return None
            if additional == 25:
                return struct.unpack(">e", self.take(2))[0]
            if additional == 26:
                return struct.unpack(">f", self.take(4))[0]
            if additional == 27:
                return struct.unpack(">d", self.take(8))[0]
        raise CborDecodeError(f"unsupported CBOR initial byte {initial:#x}")


def decode_cbor(data: bytes):
    reader = CborReader(data)
    value = reader.read()
    if reader.offset != len(data):
        raise CborDecodeError("trailing bytes after CBOR value")
    return value


class MetadataStore:
    def __init__(self, toc: str):
        self.values = {}
        for line in toc.splitlines():
            match = re.match(r"^## ([^:]+): ?(.*)$", line)
            if match:
                self.values[match.group(1)] = match.group(2)

    def text(self, key: str) -> str | None:
        value = self.values.get(key)
        if value is None:
            return None
        chunked = re.fullmatch(r"~(\d+)~", value)
        if chunked:
            value = "".join(
                self.values[f"{key}-{index}"]
                for index in range(1, int(chunked.group(1)) + 1)
            )
        return value

    def cbor(self, key: str, compressed: bool = False):
        value = self.text(key)
        if value is None:
            return None
        payload = base64.b64decode(value)
        if compressed:
            payload = zlib.decompress(payload)
        return decode_cbor(payload)


ENTITY_FIELDS = {
    "Item": {
        "npcDrops": 2,
        "objectDrops": 3,
        "itemDrops": 4,
        "startQuest": 5,
        "questRewards": 6,
        "class": 12,
        "subClass": 13,
        "vendors": 14,
        "relatedQuests": 15,
        "teachesSpell": 16,
    },
    "Npc": {"name": 1, "minLevel": 4, "maxLevel": 5, "zoneID": 9},
    "Quest": {"name": 1, "questLevel": 5, "objectives": 10, "zoneOrSort": 17},
    "Object": {"name": 1, "zoneID": 5},
}


def entity_ids(store: MetadataStore, entity: str) -> list[int]:
    value = store.cbor(f"X-{entity}-IDS", compressed=True)
    if not isinstance(value, list):
        raise ValueError(f"QuestieDB {entity} ID header is invalid")
    return value


def field(store: MetadataStore, entity: str, entity_id: int, index: int, scalar=None):
    scalar = scalar if scalar is not None else store.cbor(f"X-{entity}-{entity_id}-S")
    if not isinstance(scalar, dict):
        return None
    table_mask = scalar.get("p", scalar.get(b"p", 0))
    if table_mask // (2 ** (index - 1)) % 2 == 1:
        return store.cbor(f"X-{entity}-{entity_id}-{index}")
    return scalar.get(index)


def localized_names(store: MetadataStore, entity: str, ids: list[int]) -> dict[int, str]:
    block = store.cbor(f"X-l10n-ruRU-{entity}", compressed=True)
    if not isinstance(block, list) or not block:
        return {}
    names = block[0]
    if not isinstance(names, list):
        return {}
    return {
        entity_id: text(names[position])
        for position, entity_id in enumerate(ids)
        if position < len(names) and names[position]
    }


def text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8")
    return value


def quest_item_relations(
    store: MetadataStore, quest_ids: list[int]
) -> dict[int, list[int]]:
    """Build the item-to-quest index missing from many QuestieDB item rows."""
    related: dict[int, set[int]] = {}
    objectives_field = ENTITY_FIELDS["Quest"]["objectives"]
    for quest_id in quest_ids:
        objectives = field(store, "Quest", quest_id, objectives_field)
        if not isinstance(objectives, dict):
            continue
        for objective in objectives.get(3, []):
            if not isinstance(objective, list) or not objective:
                continue
            item_id = objective[0]
            if isinstance(item_id, int) and item_id > 0:
                related.setdefault(item_id, set()).add(quest_id)
    return {
        item_id: sorted(quest_ids)
        for item_id, quest_ids in related.items()
    }


def compact_item_rows(
    store: MetadataStore,
    item_ids: list[int],
    objective_quests: dict[int, list[int]] | None = None,
):
    rows = {}
    references = {"Npc": set(), "Quest": set(), "Object": set()}
    fields = ENTITY_FIELDS["Item"]
    objective_quests = objective_quests or {}
    for item_id in item_ids:
        scalar = store.cbor(f"X-Item-{item_id}-S")
        if not isinstance(scalar, dict):
            continue
        related_quests = set(
            field(store, "Item", item_id, fields["relatedQuests"], scalar) or []
        )
        related_quests.update(objective_quests.get(item_id, []))
        values = [
            field(store, "Item", item_id, fields["npcDrops"], scalar),
            field(store, "Item", item_id, fields["objectDrops"], scalar),
            field(store, "Item", item_id, fields["itemDrops"], scalar),
            field(store, "Item", item_id, fields["startQuest"], scalar),
            field(store, "Item", item_id, fields["questRewards"], scalar),
            field(store, "Item", item_id, fields["vendors"], scalar),
            sorted(related_quests) or None,
            field(store, "Item", item_id, fields["teachesSpell"], scalar),
            field(store, "Item", item_id, fields["class"], scalar),
            field(store, "Item", item_id, fields["subClass"], scalar),
        ]
        # Class/subclass alone are not useful in the fallback. They are retained only
        # for items that have a source/use relation, where they identify herbs.
        if not any(values[:8]):
            continue
        rows[item_id] = values
        references["Npc"].update(values[0] or [])
        references["Npc"].update(values[5] or [])
        references["Object"].update(values[1] or [])
        references["Quest"].update(values[4] or [])
        references["Quest"].update(values[6] or [])
        if values[3]:
            references["Quest"].add(values[3])
    return rows, references


def compact_entities(store: MetadataStore, entity: str, wanted: set[int]):
    ids = entity_ids(store, entity)
    translations = localized_names(store, entity, ids)
    fields = ENTITY_FIELDS[entity]
    rows = {}
    for entity_id in sorted(wanted):
        scalar = store.cbor(f"X-{entity}-{entity_id}-S")
        if not isinstance(scalar, dict):
            continue
        english = text(scalar.get(fields["name"]))
        if entity == "Npc":
            values = [english, translations.get(entity_id), scalar.get(fields["minLevel"]),
                      scalar.get(fields["maxLevel"]), scalar.get(fields["zoneID"])]
        elif entity == "Quest":
            values = [english, translations.get(entity_id), scalar.get(fields["questLevel"]),
                      scalar.get(fields["zoneOrSort"])]
        else:
            values = [english, translations.get(entity_id), scalar.get(fields["zoneID"])]
        rows[entity_id] = values
    return rows


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_value(value) -> str:
    if value is None:
        return "nil"
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "{" + ",".join(lua_value(entry) for entry in value) + "}"
    raise TypeError(f"cannot encode {type(value)!r} as Lua")


def encode_sparse_row(values: list) -> str:
    parts = [f"[{index}]={lua_value(value)}" for index, value in enumerate(values, 1)
             if value is not None]
    return "{" + ",".join(parts) + "}"


def build_lua(store: MetadataStore, source_hash: str, drop_npcs: set[int] | None = None) -> str:
    item_ids = entity_ids(store, "Item")
    quest_ids = entity_ids(store, "Quest")
    objective_quests = quest_item_relations(store, quest_ids)
    items, references = compact_item_rows(store, item_ids, objective_quests)
    references["Npc"].update(drop_npcs or ())
    entities = {
        entity: compact_entities(store, entity, references[entity])
        for entity in ("Npc", "Quest", "Object")
    }
    lines = [
        "local _, Data = ...",
        "",
        "-- Generated by tools/build_questie_snapshot.py; do not edit by hand.",
        "-- Compact fallback relations derived from QuestieDB GPL-3.0.",
        "Data.QuestieSnapshot = {",
        "    manifest = {",
        '        source = "QuestieDB",',
        f'        version = "{QUESTIEDB_VERSION}",',
        f'        sha256 = "{source_hash}",',
        f"        itemCount = {len(items)},",
        f"        npcCount = {len(entities['Npc'])},",
        f"        questCount = {len(entities['Quest'])},",
        f"        objectCount = {len(entities['Object'])},",
        "    },",
        "    -- item = {npcDrops, objectDrops, itemDrops, startQuest, questRewards,",
        "    --         vendors, relatedQuests, teachesSpell, class, subClass}",
        "    items = {",
    ]
    for entity_id, row in sorted(items.items()):
        lines.append(f"        [{entity_id}]={encode_sparse_row(row)},")
    for key, entity in (("npcs", "Npc"), ("quests", "Quest"), ("objects", "Object")):
        lines.extend(["    },", f"    {key} = {{"])
        for entity_id, row in sorted(entities[entity].items()):
            lines.append(f"        [{entity_id}]={encode_sparse_row(row)},")
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def generate(archive_path: Path, output_path: Path) -> None:
    with zipfile.ZipFile(archive_path) as archive:
        toc = archive.read(TOC_ENTRY).decode("utf-8")
        drop_source = archive.read(DROP_ENTRY).decode("utf-8")
    drop_npcs = {
        int(match.group(1))
        for match in re.finditer(r"^\s*\[(\d+)\]\s*=\s*[0-9.]+,", drop_source, re.MULTILINE)
    }
    source_hash = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    output_path.write_text(
        build_lua(MetadataStore(toc), source_hash, drop_npcs),
        encoding="utf-8", newline="\n"
    )


if __name__ == "__main__":
    output = ROOT / "Foreverpedia_Data" / "QuestieSnapshot.lua"
    generate(ROOT / "vendor" / QUESTIEDB_FILENAME, output)
    print(f"Generated {output.relative_to(ROOT)}")
