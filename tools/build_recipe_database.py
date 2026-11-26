#!/usr/bin/env python3
"""Build the reagent -> recipe index from pinned WoW client DB2 exports."""

from __future__ import annotations

import csv
import gzip
import hashlib
from collections import defaultdict
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CLIENT_BUILD = "1.60.1.71139"
LOCALE = "ruRU"
SOURCE_DIR = ROOT / "vendor" / "wago" / CLIENT_BUILD
TABLES = (
    "SpellReagents", "SpellEffect", "SkillLineAbility", "SkillLine",
    "ItemEffect", "ItemXItemEffect", "ItemSparse",
)
CMANGOS_COMMIT = "22b51464f1625f6ef6275771de1f5466c6f5d19e"
CMANGOS_SHA256 = "4f92db520868ab4e566726f68b5b2e380ae781209beaf22237b4f7f04600d0c0"
CMANGOS_PATH = ROOT / "vendor" / "cmangos" / "ClassicDB_1_12_1_z2815.sql.gz"

# Primary professions plus the Classic secondary crafting skills. Descendant
# skill lines are mapped back to these roots through SkillLine.ParentSkillLineID.
PROFESSION_ROOTS = {40, 129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def client_manifest(source_dir: Path = SOURCE_DIR) -> dict[str, str]:
    return {table: sha256(source_dir / f"{table}.csv") for table in TABLES}


def build_index(
    source_dir: Path = SOURCE_DIR,
) -> tuple[
    dict[int, list[tuple[int, int, int, int]]],
    dict[int, tuple[str, int]],
]:
    skill_rows = read_csv(source_dir / "SkillLine.csv")
    parents: dict[int, int] = {}
    skill_data: dict[int, tuple[str, int]] = {}
    for row in skill_rows:
        skill_id = int(row["ID"])
        parents[skill_id] = int(row["ParentSkillLineID"] or 0)
        skill_data[skill_id] = (
            row["DisplayName_lang"].strip() or f"Профессия #{skill_id}",
            int(row["SpellIconFileID"] or 0),
        )

    def profession_root(skill_id: int) -> int | None:
        visited: set[int] = set()
        while skill_id and skill_id not in visited:
            if skill_id in PROFESSION_ROOTS:
                return skill_id
            visited.add(skill_id)
            skill_id = parents.get(skill_id, 0)
        return None

    spell_professions: dict[int, set[int]] = {}
    for row in read_csv(source_dir / "SkillLineAbility.csv"):
        root = profession_root(int(row["SkillLine"] or 0))
        if root:
            spell_professions.setdefault(int(row["Spell"]), set()).add(root)

    outputs: dict[int, int] = {}
    for row in read_csv(source_dir / "SpellEffect.csv"):
        if int(row["Effect"] or 0) == 24 and int(row["EffectItemType"] or 0) > 0:
            outputs.setdefault(int(row["SpellID"]), int(row["EffectItemType"]))

    index: dict[int, list[tuple[int, int, int, int]]] = {}
    for row in read_csv(source_dir / "SpellReagents.csv"):
        spell_id = int(row["SpellID"])
        professions = spell_professions.get(spell_id)
        if not professions:
            continue
        output_item_id = outputs.get(spell_id, 0)
        for slot in range(8):
            item_id = int(row[f"Reagent_{slot}"] or 0)
            quantity = int(row[f"ReagentCount_{slot}"] or 0)
            if item_id <= 0 or quantity <= 0:
                continue
            for profession_id in professions:
                index.setdefault(item_id, []).append(
                    (spell_id, profession_id, output_item_id, quantity)
                )

    for recipes in index.values():
        recipes.sort(key=lambda recipe: (recipe[1], recipe[0], recipe[2], recipe[3]))
    professions = {
        profession_id: skill_data[profession_id]
        for profession_id in sorted(PROFESSION_ROOTS)
        if profession_id in skill_data
    }
    return index, professions


def build_class_ability_index(
    source_dir: Path = SOURCE_DIR,
) -> dict[int, list[tuple[int, int, int, int]]]:
    """Return item -> (spell, class mask, skill line, quantity).

    Category 7 skill lines are class abilities in the client data.  Requiring
    a non-zero ClassMask keeps weapon and other general skill lines out of the
    index without maintaining hand-authored spell or item exceptions.
    """
    skill_categories = {
        int(row["ID"]): int(row["CategoryID"] or 0)
        for row in read_csv(source_dir / "SkillLine.csv")
    }
    spell_classes: dict[int, set[tuple[int, int]]] = defaultdict(set)
    for row in read_csv(source_dir / "SkillLineAbility.csv"):
        skill_line_id = int(row["SkillLine"] or 0)
        class_mask = int(row["ClassMask"] or 0)
        if skill_categories.get(skill_line_id) == 7 and class_mask > 0:
            spell_classes[int(row["Spell"] or 0)].add((class_mask, skill_line_id))

    uses: dict[int, set[tuple[int, int, int, int]]] = defaultdict(set)
    for row in read_csv(source_dir / "SpellReagents.csv"):
        spell_id = int(row["SpellID"] or 0)
        classes = spell_classes.get(spell_id)
        if not classes:
            continue
        for slot in range(8):
            item_id = int(row[f"Reagent_{slot}"] or 0)
            quantity = int(row[f"ReagentCount_{slot}"] or 0)
            if item_id <= 0 or quantity <= 0:
                continue
            for class_mask, skill_line_id in classes:
                uses[item_id].add((spell_id, class_mask, skill_line_id, quantity))

    return {
        item_id: sorted(relations)
        for item_id, relations in sorted(uses.items())
    }


def split_sql_values(line: str, start: int):
    """Yield extended-INSERT tuples; adapted from itemtree-era-sources (GPL-3.0)."""
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
        if char == "'":
            quoted = True
        elif char == "(":
            depth += 1
            field, row = [], []
        elif char == ")" and depth:
            depth -= 1
            row.append("".join(field).strip())
            yield row
            field = []
        elif char == "," and depth == 1:
            row.append("".join(field).strip())
            field = []
        elif depth:
            field.append(char)


def cmangos_trainers(
    path: Path, recipe_spells: set[int]
) -> dict[int, list[tuple[int, int]]]:
    return cmangos_trainer_data(path, recipe_spells)[0]


def cmangos_trainer_data(
    path: Path, recipe_spells: set[int]
) -> tuple[
    dict[int, list[tuple[int, int]]],
    dict[int, list[tuple[int, int, int]]],
    dict[int, tuple[str, str | None]],
]:
    if sha256(path) != CMANGOS_SHA256:
        raise ValueError("CMaNGOS source checksum mismatch")
    wanted = {
        "creature_template", "locales_creature", "npc_trainer",
        "npc_trainer_template", "spell_template",
    }
    create_re = re.compile(r"^CREATE TABLE `([a-z_]+)` \(")
    column_re = re.compile(r"^\s*`([A-Za-z_0-9]+)`")
    insert_re = re.compile(r"^INSERT INTO `([a-z_]+)` VALUES ")
    columns: dict[str, list[str]] = {}
    pending: str | None = None
    creature_templates: dict[int, int] = {}
    creature_names: dict[int, str] = {}
    creature_names_ru: dict[int, str] = {}
    direct: dict[int, dict[int, tuple[int, int, int]]] = defaultdict(dict)
    templates: dict[int, dict[int, tuple[int, int, int]]] = defaultdict(dict)
    learned: dict[int, int] = {}

    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if pending is not None:
                if line.startswith(")"):
                    pending = None
                    continue
                match = column_re.match(line)
                if match:
                    columns[pending].append(match.group(1))
                continue
            created = create_re.match(line)
            if created:
                pending = created.group(1) if created.group(1) in wanted else None
                if pending:
                    columns[pending] = []
                continue
            inserted = insert_re.match(line)
            if not inserted or inserted.group(1) not in columns:
                continue
            table = inserted.group(1)
            positions = {name: pos for pos, name in enumerate(columns[table])}
            for row in split_sql_values(line, inserted.end()):
                if len(row) != len(columns[table]):
                    continue
                def number(name: str) -> int:
                    value = row[positions[name]]
                    return 0 if value in ("", "NULL") else int(float(value))
                def text(name: str) -> str:
                    value = row[positions[name]]
                    if value in ("", "NULL"):
                        return ""
                    if len(value) >= 2 and value[0] == "'" and value[-1] == "'":
                        value = value[1:-1]
                    return (value.replace("\\'", "'").replace('\\"', '"')
                            .replace("\\\\", "\\"))
                if table == "creature_template":
                    entry = number("Entry")
                    creature_templates[entry] = number("TrainerTemplateId")
                    creature_names[entry] = text("Name")
                elif table == "locales_creature":
                    entry = number("entry")
                    localized = text("name_loc8")
                    if localized:
                        creature_names_ru[entry] = localized
                elif table == "npc_trainer":
                    npc, spell = number("entry"), number("spell")
                    value = (number("spellcost"), number("reqskill"), number("reqskillvalue"))
                    current = direct[npc].get(spell)
                    if not current or value[0] < current[0]: direct[npc][spell] = value
                elif table == "npc_trainer_template":
                    template, spell = number("entry"), number("spell")
                    value = (number("spellcost"), number("reqskill"), number("reqskillvalue"))
                    current = templates[template].get(spell)
                    if not current or value[0] < current[0]: templates[template][spell] = value
                else:
                    for slot in (1, 2, 3):
                        if number(f"Effect{slot}") == 36:
                            trigger = number(f"EffectTriggerSpell{slot}")
                            if trigger:
                                learned[number("Id")] = trigger
                                break

    result: dict[int, dict[int, tuple[int, int, int]]] = defaultdict(dict)
    for npc_id, template_id in creature_templates.items():
        wrappers = dict(templates.get(template_id, {}))
        for wrapper, value in direct.get(npc_id, {}).items():
            current = wrappers.get(wrapper)
            if not current or value[0] < current[0]: wrappers[wrapper] = value
        for wrapper, value in wrappers.items():
            taught = learned.get(wrapper, wrapper)
            if taught in recipe_spells:
                current = result[taught].get(npc_id)
                if not current or value[0] < current[0]: result[taught][npc_id] = value
    trainers = {
        spell: sorted((npc_id, value[0]) for npc_id, value in values.items())
        for spell, values in sorted(result.items())
    }
    requirements = {
        spell: sorted({(value[1], value[2], npc_id) for npc_id, value in values.items()
                       if value[1] > 0 and value[2] > 0})
        for spell, values in sorted(result.items())
    }
    trainer_names = {
        npc_id: (creature_names.get(npc_id, f"NPC #{npc_id}"), creature_names_ru.get(npc_id))
        for values in result.values() for npc_id in values
    }
    return trainers, requirements, dict(sorted(trainer_names.items()))


def recipe_items(
    source_dir: Path, recipe_spells: set[int]
) -> dict[int, list[tuple[int, int, int]]]:
    effect_spells = {
        int(row["ID"]): int(row["SpellID"] or 0)
        for row in read_csv(source_dir / "ItemEffect.csv")
    }
    prices = {
        int(row["ID"]): (int(row["BuyPrice"] or 0), max(1, int(row["VendorStackCount"] or 1)))
        for row in read_csv(source_dir / "ItemSparse.csv")
    }
    items: dict[int, set[int]] = defaultdict(set)
    for row in read_csv(source_dir / "ItemXItemEffect.csv"):
        spell = effect_spells.get(int(row["ItemEffectID"]), 0)
        if spell in recipe_spells:
            items[spell].add(int(row["ItemID"]))
    return {
        spell: [(item_id, *prices.get(item_id, (0, 1))) for item_id in sorted(ids)]
        for spell, ids in sorted(items.items())
    }


def build_learning_sources(
    source_dir: Path, cmangos_path: Path, recipe_spells: set[int],
    trainers: dict[int, list[tuple[int, int]]] | None = None,
) -> dict[int, dict[str, list[tuple]]]:
    trainers = trainers if trainers is not None else cmangos_trainers(cmangos_path, recipe_spells)
    items = recipe_items(source_dir, recipe_spells)
    return {
        spell: {"trainers": trainers.get(spell, []), "items": items.get(spell, [])}
        for spell in sorted(set(trainers) | set(items))
    }


def recipe_item_requirements(
    source_dir: Path, recipe_spells: set[int]
) -> dict[int, list[tuple[int, int, int]]]:
    effect_spells = {
        int(row["ID"]): int(row["SpellID"] or 0)
        for row in read_csv(source_dir / "ItemEffect.csv")
    }
    item_spells: dict[int, set[int]] = defaultdict(set)
    for row in read_csv(source_dir / "ItemXItemEffect.csv"):
        spell = effect_spells.get(int(row["ItemEffectID"]), 0)
        if spell in recipe_spells:
            item_spells[int(row["ItemID"])].add(spell)
    requirements: dict[int, set[tuple[int, int, int]]] = defaultdict(set)
    for row in read_csv(source_dir / "ItemSparse.csv"):
        item_id = int(row["ID"])
        skill = int(row["RequiredSkill"] or 0)
        rank = int(row["RequiredSkillRank"] or 0)
        if skill > 0 and rank > 0:
            for spell in item_spells.get(item_id, ()):
                requirements[spell].add((skill, rank, item_id))
    return {spell: sorted(values) for spell, values in sorted(requirements.items())}


def skill_line_requirements(
    source_dir: Path, recipe_spells: set[int]
) -> dict[int, list[tuple[int, int]]]:
    parents = {
        int(row["ID"]): int(row["ParentSkillLineID"] or 0)
        for row in read_csv(source_dir / "SkillLine.csv")
    }

    def profession_root(skill_id: int) -> int | None:
        visited: set[int] = set()
        while skill_id and skill_id not in visited:
            if skill_id in PROFESSION_ROOTS:
                return skill_id
            visited.add(skill_id)
            skill_id = parents.get(skill_id, 0)
        return None

    requirements: dict[int, set[tuple[int, int]]] = defaultdict(set)
    for row in read_csv(source_dir / "SkillLineAbility.csv"):
        spell = int(row["Spell"] or 0)
        root = profession_root(int(row["SkillLine"] or 0))
        rank = int(row["MinSkillLineRank"] or 0)
        if spell in recipe_spells and root and rank > 0:
            requirements[spell].add((root, rank))
    return {spell: sorted(values) for spell, values in sorted(requirements.items())}


def build_recipe_requirements(
    source_dir: Path, cmangos_path: Path, recipe_spells: set[int],
    trainer_requirements: dict[int, list[tuple[int, int, int]]] | None = None,
) -> dict[int, tuple[int, int, int]]:
    """Return spell -> (profession, required rank, provenance code).

    Provenance codes are 1=teaching item, 2=trainer, 3=SkillLineAbility.
    Teaching items take priority because many item-taught recipes have a
    placeholder MinSkillLineRank of 1 in the client table.
    """
    item_requirements = recipe_item_requirements(source_dir, recipe_spells)
    if trainer_requirements is None:
        _, trainer_requirements, _ = cmangos_trainer_data(cmangos_path, recipe_spells)
    skill_requirements = skill_line_requirements(source_dir, recipe_spells)
    result: dict[int, tuple[int, int, int]] = {}
    for spell in sorted(recipe_spells):
        item_candidates = [(skill, rank) for skill, rank, _ in item_requirements.get(spell, [])]
        trainer_candidates = [
            (skill, rank) for skill, rank, _ in trainer_requirements.get(spell, [])
        ]
        candidates, source = (
            (item_candidates, 1) if item_candidates
            else (trainer_candidates, 2) if trainer_candidates
            else (skill_requirements.get(spell, []), 3)
        )
        if candidates:
            skill, rank = max(candidates, key=lambda value: (value[1], value[0]))
            result[spell] = (skill, rank, source)
    return result


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_lua(
    reagent_index: dict[int, list[tuple[int, int, int, int]]],
    professions: dict[int, tuple[str, int]],
    hashes: dict[str, str],
    learning: dict[int, dict[str, list[tuple]]] | None = None,
    requirements: dict[int, tuple[int, int, int]] | None = None,
    trainer_names: dict[int, tuple[str, str | None]] | None = None,
    class_abilities: dict[int, list[tuple[int, int, int, int]]] | None = None,
) -> str:
    learning = learning or {}
    requirements = requirements or {}
    trainer_names = trainer_names or {}
    class_abilities = class_abilities or {}
    relation_count = sum(len(recipes) for recipes in reagent_index.values())
    combined_hash = hashlib.sha256(
        "".join(f"{key}:{hashes[key]}\n" for key in sorted(hashes)).encode()
    ).hexdigest()
    lines = [
        "local _, Data = ...",
        "",
        "-- Generated by tools/build_recipe_database.py; do not edit by hand.",
        "-- Source: WoW client DB2 tables exported by wago.tools.",
        "Data.RecipeData = {",
        "    manifest = {",
        f"        source = {lua_string('WoW client DB2')},",
        f"        version = {lua_string(CLIENT_BUILD)},",
        f"        locale = {lua_string(LOCALE)},",
        f"        sha256 = {lua_string(combined_hash)},",
        f"        reagentCount = {len(reagent_index)},",
        f"        relationCount = {relation_count},",
        f"        requirementCount = {len(requirements)},",
        "    },",
        "    professions = {",
    ]
    for profession_id, (name, _) in sorted(professions.items()):
        lines.append(f"        [{profession_id}] = {lua_string(name)},")
    lines.extend(["    },", "    professionIcons = {"])
    for profession_id, (_, icon) in sorted(professions.items()):
        lines.append(f"        [{profession_id}] = {icon},")
    lines.extend(["    },", "    trainerNames = {"])
    for npc_id, (english, russian) in sorted(trainer_names.items()):
        localized = russian or english
        lines.append(
            f"        [{npc_id}] = {{{lua_string(english)},{lua_string(localized)}}},"
        )
    lines.extend(["    },", "    learning = {"])
    for spell_id, sources in sorted(learning.items()):
        trainers = ",".join("{%d,%d}" % value for value in sources["trainers"])
        items = ",".join("{%d,%d,%d}" % value for value in sources["items"])
        lines.append(f"        [{spell_id}] = {{trainers={{{trainers}}},items={{{items}}}}},")
    lines.extend(["    },", "    requirements = {"])
    for spell_id, requirement in sorted(requirements.items()):
        lines.append("        [%d] = {%d,%d,%d}," % (spell_id, *requirement))
    lines.extend(["    },", "    outputs = {"])
    output_index: dict[int, set[tuple[int, int]]] = defaultdict(set)
    ingredient_index: dict[int, set[tuple[int, int]]] = defaultdict(set)
    for recipes in reagent_index.values():
        for spell_id, profession_id, output_item_id, _ in recipes:
            if output_item_id > 0:
                output_index[output_item_id].add((spell_id, profession_id))
    for item_id, recipes in reagent_index.items():
        for spell_id, _, _, quantity in recipes:
            ingredient_index[spell_id].add((item_id, quantity))
    for item_id, recipes in sorted(output_index.items()):
        encoded = ",".join("{%d,%d}" % recipe for recipe in sorted(recipes))
        lines.append(f"        [{item_id}] = {{{encoded}}},")
    lines.extend(["    },", "    ingredients = {"])
    for spell_id, ingredients in sorted(ingredient_index.items()):
        encoded = ",".join("{%d,%d}" % ingredient for ingredient in sorted(ingredients))
        lines.append(f"        [{spell_id}] = {{{encoded}}},")
    lines.extend(["    },", "    reagents = {"])
    for item_id, recipes in sorted(reagent_index.items()):
        encoded = ",".join("{%d,%d,%d,%d}" % recipe for recipe in recipes)
        lines.append(f"        [{item_id}] = {{{encoded}}},")
    lines.extend(["    },", "}", "", "Data.ClassAbilityData = {", "    manifest = {"])
    lines.extend([
        f"        source = {lua_string('WoW client DB2')},",
        f"        version = {lua_string(CLIENT_BUILD)},",
        f"        sha256 = {lua_string(combined_hash)},",
        f"        itemCount = {len(class_abilities)},",
        f"        relationCount = {sum(map(len, class_abilities.values()))},",
        "    },",
        "    uses = {",
    ])
    for item_id, relations in sorted(class_abilities.items()):
        encoded = ",".join("{%d,%d,%d,%d}" % relation for relation in relations)
        lines.append(f"        [{item_id}] = {{{encoded}}},")
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def generate(
    source_dir: Path, output_path: Path, cmangos_path: Path = CMANGOS_PATH
) -> dict[int, list[tuple[int, int, int, int]]]:
    missing = [table for table in TABLES if not (source_dir / f"{table}.csv").is_file()]
    if missing:
        raise FileNotFoundError(f"missing DB2 exports: {', '.join(missing)}")
    index, professions = build_index(source_dir)
    class_abilities = build_class_ability_index(source_dir)
    recipe_spells = {recipe[0] for recipes in index.values() for recipe in recipes}
    trainers, trainer_requirements, trainer_names = cmangos_trainer_data(
        cmangos_path, recipe_spells
    )
    learning = build_learning_sources(
        source_dir, cmangos_path, recipe_spells, trainers=trainers
    )
    requirements = build_recipe_requirements(
        source_dir, cmangos_path, recipe_spells,
        trainer_requirements=trainer_requirements,
    )
    hashes = client_manifest(source_dir)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        build_lua(
            index, professions, hashes, learning, requirements, trainer_names,
            class_abilities,
        ),
        encoding="utf-8", newline="\n"
    )
    return index


if __name__ == "__main__":
    index = generate(SOURCE_DIR, ROOT / "Foreverpedia_Data" / "Recipes.lua")
    print(
        f"Generated {sum(map(len, index.values()))} client recipe relations "
        f"for {len(index)} reagents from build {CLIENT_BUILD}"
    )
