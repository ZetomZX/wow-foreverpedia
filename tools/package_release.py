#!/usr/bin/env python3
"""Create verified base and optional-QuestieDB Foreverpedia archives."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import struct
import tomllib
import zipfile


ROOT = Path(__file__).resolve().parents[1]
CORE_ADDON_DIR = ROOT / "Foreverpedia"
DATA_ADDON_DIR = ROOT / "Foreverpedia_Data"
ADDON_DIRS = (CORE_ADDON_DIR, DATA_ADDON_DIR)
VENDOR_DIR = ROOT / "vendor"
DIST_DIR = ROOT / "dist"
RELEASE_CONFIG_PATH = ROOT / "release.toml"


def load_release_config(path: Path) -> dict:
    with path.open("rb") as stream:
        config = tomllib.load(stream)
    release = config.get("release")
    if not isinstance(release, dict):
        raise ValueError("release.toml must contain a [release] table")

    required = {
        "core_version": str,
        "data_version": str,
        "minimum_data_version": str,
        "interface": int,
        "data_schema": int,
        "client_build": str,
        "questiedb_version": str,
    }
    for key, expected_type in required.items():
        value = release.get(key)
        if not isinstance(value, expected_type):
            raise ValueError(
                f"release.toml [release].{key} must be {expected_type.__name__}"
            )
    return release


RELEASE_CONFIG = load_release_config(RELEASE_CONFIG_PATH)
ADDON_VERSION = RELEASE_CONFIG["core_version"]
DATA_ADDON_VERSION = RELEASE_CONFIG["data_version"]
MIN_DATA_ADDON_VERSION = RELEASE_CONFIG["minimum_data_version"]
INTERFACE_VERSION = RELEASE_CONFIG["interface"]
DATA_SCHEMA = RELEASE_CONFIG["data_schema"]
CLIENT_BUILD = RELEASE_CONFIG["client_build"]
QUESTIEDB_VERSION = RELEASE_CONFIG["questiedb_version"]
QUESTIEDB_COMMIT = "a444a6418113ae0fce5d30c897674132e756ba1d"
QUESTIEDB_FILENAME = f"QuestieDB-{QUESTIEDB_VERSION}-Forever.zip"
QUESTIEDB_SHA256 = "d073a954c3c7f3f374eb82b0501630998b3f8b7971baad247c8fb360ba538679"
CLIENT_TABLES = (
    "SpellReagents", "SpellEffect", "SkillLineAbility", "SkillLine",
    "ItemEffect", "ItemXItemEffect", "ItemSparse",
)
CMANGOS_COMMIT = "22b51464f1625f6ef6275771de1f5466c6f5d19e"
CMANGOS_SHA256 = "4f92db520868ab4e566726f68b5b2e380ae781209beaf22237b4f7f04600d0c0"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_archive_name(name: str) -> bool:
    path = PurePosixPath(name.replace("\\", "/"))
    return not path.is_absolute() and ".." not in path.parts


def verify_release_archive(
    archive_path: Path,
    expected_roots: set[str],
    toc_roots: set[str] | None = None,
) -> None:
    """Validate the layout expected by the CurseForge WoW addon processor."""
    forbidden_names = {".ds_store", "thumbs.db", "desktop.ini"}
    forbidden_directories = {"__macosx", ".git", ".svn"}

    with zipfile.ZipFile(archive_path, "r") as archive:
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError(f"archive contains a corrupt member: {corrupt}")

        names = [info.filename.replace("\\", "/") for info in archive.infolist()]
        if len(names) != len(set(names)):
            raise ValueError("archive contains duplicate paths")

        roots = set()
        files = set()
        for info, normalized in zip(archive.infolist(), names):
            if not normalized or not safe_archive_name(normalized):
                raise ValueError(f"unsafe archive path: {info.filename}")
            path = PurePosixPath(normalized)
            lowered_parts = {part.lower() for part in path.parts}
            if lowered_parts & forbidden_directories or path.name.lower() in forbidden_names:
                raise ValueError(f"archive contains a forbidden path: {normalized}")
            if len(path.parts) < 2:
                raise ValueError(f"archive contains a root-level item: {normalized}")
            roots.add(path.parts[0])
            if not info.is_dir():
                files.add(normalized)

        if roots != expected_roots:
            raise ValueError(
                f"archive roots mismatch: expected {sorted(expected_roots)}, got {sorted(roots)}"
            )
        for root in toc_roots if toc_roots is not None else expected_roots:
            toc = f"{root}/{root}.toc"
            if toc not in files:
                raise ValueError(f"archive is missing the case-sensitive addon TOC: {toc}")


def verify_questiedb(archive_path: Path, manifest_path: Path) -> dict:
    actual_hash = sha256(archive_path)
    if actual_hash != QUESTIEDB_SHA256:
        raise ValueError(
            f"QuestieDB checksum mismatch: expected {QUESTIEDB_SHA256}, got {actual_hash}"
        )

    release = json.loads(manifest_path.read_text(encoding="utf-8"))
    metadata = release.get("questiedb", {})
    if metadata.get("version") != QUESTIEDB_VERSION:
        raise ValueError("QuestieDB release manifest has an unexpected version")
    if metadata.get("producerCommit") != QUESTIEDB_COMMIT:
        raise ValueError("QuestieDB release manifest has an unexpected commit")
    if metadata.get("contractVersion", 0) < 1:
        raise ValueError("QuestieDB release does not support API contract 1")

    artifact = next(
        (value for value in metadata.get("artifacts", []) if value.get("flavor") == "Forever"),
        None,
    )
    if not artifact or artifact.get("sha256") != QUESTIEDB_SHA256:
        raise ValueError("QuestieDB Forever artifact is absent from release.json")

    with zipfile.ZipFile(archive_path, "r") as archive:
        required = {
            "QuestieDB/QuestieDB_Forever.toc",
            "QuestieDB/QuestieDB_Camelot.toc",
            "QuestieDB/src/api.lua",
            "QuestieDB/src/support/data.lua",
            "QuestieDB/support/Forever/DropTables/classicItemDrops.lua",
            "QuestieDB/LICENSE.md",
            "QuestieDB/gpl-3.0.md",
        }
        missing = required - set(archive.namelist())
        if missing:
            raise ValueError(f"QuestieDB archive is missing: {', '.join(sorted(missing))}")

        forever_toc = archive.read("QuestieDB/QuestieDB_Forever.toc")
        camelot_toc = archive.read("QuestieDB/QuestieDB_Camelot.toc")
        if forever_toc != camelot_toc:
            raise ValueError("QuestieDB Forever and Camelot TOCs are not identical")
        toc_text = forever_toc.decode("utf-8")
        for expected in (
            f"## Interface: {INTERFACE_VERSION}",
            f"## Version: {QUESTIEDB_VERSION}",
            "## X-Contract-Version: 4",
            "## X-Flavor: Forever",
            f"## X-BUILD-COMMIT: {QUESTIEDB_COMMIT}",
        ):
            if expected not in toc_text:
                raise ValueError(f"QuestieDB TOC does not contain {expected!r}")

        drop_text = archive.read(
            "QuestieDB/support/Forever/DropTables/classicItemDrops.lua"
        ).decode("utf-8")
        linen_marker = "[2589] = { -- Linen Cloth"
        if linen_marker not in drop_text:
            raise ValueError("QuestieDB support drop table has no Linen Cloth entry")
    return metadata


def verify_client_recipes(source_dir: Path, generated_path: Path) -> dict[str, str]:
    hashes = {}
    for table in CLIENT_TABLES:
        path = source_dir / f"{table}.csv"
        if not path.is_file():
            raise ValueError(f"client DB2 export is missing: {path.name}")
        hashes[table] = sha256(path)
    generated = generated_path.read_text(encoding="utf-8")
    for expected in (
        f'version = "{CLIENT_BUILD}"',
        'source = "WoW client DB2"',
        "[2589] = {{3275,129,1251,1},{3276,129,2581,2},{2737,164,2844,2}",
        "{8339,202,6714,1},{1266905,202,260792,1}",
        "[3276] = {trainers={{2326,100},{2327,100}",
        "[8339] = {trainers={},items={{6716,800,1}}}",
        "[3276] = {{2589,2}}",
        "requirementCount = 2519",
        "[27832] = {164,300,1}",
        "Data.ClassAbilityData = {",
        "itemCount = 23",
        "relationCount = 76",
        "[6265] = {{691,256,354,1},{693,256,354,1}",
        "[17030] = {{20608,64,374,1},{21169,64,374,1}}",
        "[17031] = {{3561,128,237,1},{3562,128,237,1}",
    ):
        if expected not in generated:
            raise ValueError(f"generated recipe database does not contain {expected!r}")
    return hashes


def verify_search_index(generated_path: Path) -> None:
    generated = generated_path.read_text(encoding="utf-8")
    for expected in (
        'source = "WoW client ItemSparse"',
        f'version = "{CLIENT_BUILD}"',
        "locales = {",
        'ruRU = {sha256="00c371a9456519fa401d15fb07f8d7875096cfd1fdb14584c5d1894819e8332d",itemCount=19326}',
        'enUS = {sha256="0e194578bca2289558a133fe6d4184b1baba848327c0fa0442ba2846b9b39a55",itemCount=19326}',
        '[2589] = {"Льняной материал","льняной материал"}',
        '[21071] = {"Сырой шалфокунь","сырой шалфокунь"}',
        '[2589] = {"Linen Cloth","linen cloth"}',
        '[3372] = {"Leaded Vial","leaded vial"}',
        '[21071] = {"Raw Sagefish","raw sagefish"}',
    ):
        if expected not in generated:
            raise ValueError(f"generated search index does not contain {expected!r}")


def verify_addon_icon(icon_path: Path, toc_path: Path) -> None:
    data = icon_path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("Foreverpedia icon is not a valid PNG")
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    if (width, height) != (256, 256):
        raise ValueError(f"Foreverpedia icon must be 256x256, got {width}x{height}")
    if color_type not in (4, 6):
        raise ValueError("Foreverpedia icon PNG does not contain an alpha channel")
    toc = toc_path.read_text(encoding="utf-8")
    expected = "## IconTexture: Interface\\AddOns\\Foreverpedia\\Media\\ForeverpediaIcon.png"
    if expected not in toc:
        raise ValueError("Foreverpedia TOC does not reference the addon icon")


def verify_toc(addon_dir: Path, version: str) -> None:
    toc_path = addon_dir / f"{addon_dir.name}.toc"
    toc = toc_path.read_text(encoding="utf-8")
    for expected in (
        f"## Interface: {INTERFACE_VERSION}",
        f"## Version: {version}",
    ):
        if expected not in toc:
            raise ValueError(f"{toc_path.name} does not contain {expected!r}")

    entries = [
        line.strip().replace("\\", "/")
        for line in toc.splitlines()
        if line.strip() and not line.startswith("##")
    ]
    if len(entries) != len(set(entries)):
        raise ValueError(f"{toc_path.name} contains duplicate file entries")

    actual_files = {
        path.relative_to(addon_dir).as_posix()
        for path in addon_dir.rglob("*")
        if path.is_file()
    }
    for entry in entries:
        if not safe_archive_name(entry) or entry not in actual_files:
            raise ValueError(f"{toc_path.name} references a missing or unsafe file: {entry}")

    unlisted_lua = {
        path for path in actual_files if path.lower().endswith(".lua")
    } - set(entries)
    if unlisted_lua:
        raise ValueError(
            f"{toc_path.name} does not load: {', '.join(sorted(unlisted_lua))}"
        )


def verify_data_addon(data_dir: Path, core_toc_path: Path) -> None:
    toc_path = data_dir / "Foreverpedia_Data.toc"
    bootstrap_path = data_dir / "Bootstrap.lua"
    toc = toc_path.read_text(encoding="utf-8")
    bootstrap = bootstrap_path.read_text(encoding="utf-8")
    core_toc = core_toc_path.read_text(encoding="utf-8")

    for expected in (
        f"## Version: {DATA_ADDON_VERSION}",
        f"## X-Foreverpedia-Data-Schema: {DATA_SCHEMA}",
        "Bootstrap.lua\nSearch.lua\nRecipes.lua\nSources.lua\nQuestieSnapshot.lua",
    ):
        if expected not in toc:
            raise ValueError(f"Foreverpedia_Data TOC does not contain {expected!r}")
    if "## SavedVariables:" in toc:
        raise ValueError("Foreverpedia_Data must not own player SavedVariables")

    for expected in (
        f'schema = {DATA_SCHEMA}',
        f'version = "{DATA_ADDON_VERSION}"',
        "_G.ForeverpediaData = Data",
    ):
        if expected not in bootstrap:
            raise ValueError(f"Foreverpedia_Data bootstrap does not contain {expected!r}")

    for filename, assignment in (
        ("Search.lua", "Data.ItemSearchData ="),
        ("Recipes.lua", "Data.RecipeData ="),
        ("Sources.lua", "Data.SourceData ="),
        ("QuestieSnapshot.lua", "Data.QuestieSnapshot ="),
    ):
        generated = (data_dir / filename).read_text(encoding="utf-8")
        if "local _, Data = ..." not in generated or assignment not in generated:
            raise ValueError(f"{filename} is not bound to Foreverpedia_Data")
    recipes = (data_dir / "Recipes.lua").read_text(encoding="utf-8")
    if "Data.ClassAbilityData =" not in recipes:
        raise ValueError("Recipes.lua has no generated class-ability index")

    for expected in (
        "## Dependencies: Foreverpedia_Data",
        "## OptionalDeps: QuestieDB",
        f"## X-Foreverpedia-Data-Min-Version: {MIN_DATA_ADDON_VERSION}",
        f"## X-Foreverpedia-Data-Schema: {DATA_SCHEMA}",
        "DataBridge.lua",
    ):
        if expected not in core_toc:
            raise ValueError(f"Foreverpedia TOC does not contain {expected!r}")

    old_data_dir = CORE_ADDON_DIR / "Data"
    if old_data_dir.exists():
        raise ValueError("static data must not remain inside the Foreverpedia core addon")


def verify_cmangos(path: Path) -> None:
    actual = sha256(path)
    if actual != CMANGOS_SHA256:
        raise ValueError(f"CMaNGOS checksum mismatch: expected {CMANGOS_SHA256}, got {actual}")


def verify_source_index(generated_path: Path) -> None:
    generated = generated_path.read_text(encoding="utf-8")
    for expected in (
        f'version = "{QUESTIEDB_VERSION}"',
        "unlimitedDrops = true",
        "[2589] = {{1949,100,0,0},{2361,100,0,0}",
        "[6291] = {{40,18,1,1}",
        "fishingItemCount = 128",
        "fishingPools = {",
        "[21071] = {{180656,85,1,1}}",
        "[21153] = {{180684,85,1,1},{184956,85,1,1}}",
        "[20708] = {{180655,60,1,1}",
        '[180656] = "Косяк шалфокуня"',
        "gatheringItemCount = 119",
        "gatheringRelationCount = 119",
        "gathering = {",
        "[2934] = {{393,{",
        "[2770] = {{186,{1731,2055,3763,103713,181248}}}",
        "[2447] = {{182,{1618,3724}}}",
        "objectItemCount = 2976",
        "containerItemCount = 2395",
        "disenchantItemCount = 24",
        "pickpocketItemCount = 124",
        "spellLootItemCount = 159",
        "mailItemCount = 19",
        "[11176] = {{2,46,50,404,20,75,1,2},{2,51,55,384,22,75,2,5}}",
        "[15924] = {{61898,100,1,1}}",
    ):
        if expected not in generated:
            raise ValueError(f"generated source database does not contain {expected!r}")


def verify_questie_snapshot(generated_path: Path) -> None:
    generated = generated_path.read_text(encoding="utf-8")
    for expected in (
        "Data.QuestieSnapshot = {",
        f'version = "{QUESTIEDB_VERSION}"',
        "itemCount = 15601",
        "npcCount = 6538",
        "questCount = 3688",
        "objectCount = 940",
        "[2589]=",
        "[3693]={[1]={2344,2345,2346,14275},[7]={547}",
        "[5085]={[1]={3258,3260,3261,3263,3259,3262,268624},[7]={899}",
        "Слуга Азоры",
    ):
        if expected not in generated:
            raise ValueError(f"QuestieDB snapshot does not contain {expected!r}")


def write_addon_archive(output: Path, addon_dirs: tuple[Path, ...]) -> None:
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
        for addon_dir in addon_dirs:
            for source in sorted(addon_dir.rglob("*")):
                if source.is_file():
                    target.write(source, source.relative_to(ROOT).as_posix())


def build_release() -> tuple[Path, Path]:
    questie_archive = VENDOR_DIR / QUESTIEDB_FILENAME
    questie_manifest = VENDOR_DIR / f"QuestieDB-{QUESTIEDB_VERSION}-release.json"
    metadata = verify_questiedb(questie_archive, questie_manifest)
    client_hashes = verify_client_recipes(
        VENDOR_DIR / "wago" / CLIENT_BUILD, DATA_ADDON_DIR / "Recipes.lua"
    )
    verify_cmangos(VENDOR_DIR / "cmangos" / "ClassicDB_1_12_1_z2815.sql.gz")
    verify_source_index(DATA_ADDON_DIR / "Sources.lua")
    verify_questie_snapshot(DATA_ADDON_DIR / "QuestieSnapshot.lua")
    verify_search_index(DATA_ADDON_DIR / "Search.lua")
    verify_addon_icon(
        CORE_ADDON_DIR / "Media" / "ForeverpediaIcon.png",
        CORE_ADDON_DIR / "Foreverpedia.toc",
    )
    verify_toc(CORE_ADDON_DIR, ADDON_VERSION)
    verify_toc(DATA_ADDON_DIR, DATA_ADDON_VERSION)
    verify_data_addon(DATA_ADDON_DIR, CORE_ADDON_DIR / "Foreverpedia.toc")

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    core_output = DIST_DIR / f"Foreverpedia-{ADDON_VERSION}-Core.zip"
    data_output = DIST_DIR / f"Foreverpedia_Data-{DATA_ADDON_VERSION}.zip"
    output = DIST_DIR / f"Foreverpedia-{ADDON_VERSION}-WoW-Forever.zip"
    questie_output = DIST_DIR / f"Foreverpedia-{ADDON_VERSION}-With-QuestieDB.zip"

    write_addon_archive(core_output, (CORE_ADDON_DIR,))
    write_addon_archive(data_output, (DATA_ADDON_DIR,))

    write_addon_archive(output, ADDON_DIRS)

    with zipfile.ZipFile(questie_output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
        for addon_dir in ADDON_DIRS:
            for source in sorted(addon_dir.rglob("*")):
                if source.is_file():
                    archive_name = source.relative_to(ROOT).as_posix()
                    target.write(source, archive_name)

        with zipfile.ZipFile(questie_archive, "r") as questie:
            for info in questie.infolist():
                normalized = info.filename.replace("\\", "/")
                if not safe_archive_name(normalized):
                    raise ValueError(f"unsafe QuestieDB archive path: {info.filename}")
                if normalized and not normalized.startswith("QuestieDB/"):
                    raise ValueError(f"unexpected QuestieDB archive path: {info.filename}")
                if not info.is_dir():
                    info.filename = normalized
                    target.writestr(info, questie.read(info))

    verify_release_archive(core_output, {"Foreverpedia"})
    verify_release_archive(data_output, {"Foreverpedia_Data"})
    verify_release_archive(output, {"Foreverpedia", "Foreverpedia_Data"})
    verify_release_archive(
        questie_output,
        {"Foreverpedia", "Foreverpedia_Data", "QuestieDB"},
        {"Foreverpedia", "Foreverpedia_Data"},
    )

    output_manifest = {
        "addon": {
            "name": "Foreverpedia",
            "version": ADDON_VERSION,
            "interface": INTERFACE_VERSION,
        },
        "dataAddon": {
            "name": "Foreverpedia_Data",
            "version": DATA_ADDON_VERSION,
            "schema": DATA_SCHEMA,
            "clientBuild": CLIENT_BUILD,
            "ownsSavedVariables": False,
        },
        "database": {
            "name": "QuestieDB",
            "optional": True,
            "version": QUESTIEDB_VERSION,
            "producerCommit": QUESTIEDB_COMMIT,
            "contractVersion": metadata["contractVersion"],
            "sourceSha256": QUESTIEDB_SHA256,
        },
        "recipes": {
            "name": "WoW client DB2",
            "build": CLIENT_BUILD,
            "locale": "ruRU",
            "exporter": "wago.tools",
            "tables": client_hashes,
        },
        "search": {
            "name": "WoW client ItemSparse",
            "build": CLIENT_BUILD,
            "locales": {
                "ruRU": {"itemCount": 19326},
                "enUS": {"itemCount": 19326},
            },
        },
        "dropIndex": {
            "name": "QuestieDB",
            "version": QUESTIEDB_VERSION,
            "limit": None,
            "grouping": "zone",
        },
        "trainerSources": {
            "name": "CMaNGOS Classic DB",
            "commit": CMANGOS_COMMIT,
            "sourceSha256": CMANGOS_SHA256,
            "confidence": "historical Classic Era; augmented by local Forever observations",
        },
        "fishingSources": {
            "name": "CMaNGOS Classic DB fishing_loot_template + fishing-hole gameobject_loot_template",
            "commit": CMANGOS_COMMIT,
            "confidence": "historical Classic Era",
            "itemCount": 128,
            "includesNonFishLoot": True,
        },
        "gatheringSources": {
            "name": "CMaNGOS Classic DB skinning and gathering object loot",
            "commit": CMANGOS_COMMIT,
            "confidence": "historical Classic Era",
            "professions": ["Herbalism", "Mining", "Skinning"],
            "itemCount": 119,
        },
        "archive": {
            "file": output.name,
            "sha256": sha256(output),
            "bytes": output.stat().st_size,
        },
        "optionalQuestieArchive": {
            "file": questie_output.name,
            "sha256": sha256(questie_output),
            "bytes": questie_output.stat().st_size,
        },
        "componentArchives": {
            "core": {
                "file": core_output.name,
                "sha256": sha256(core_output),
                "bytes": core_output.stat().st_size,
            },
            "data": {
                "file": data_output.name,
                "sha256": sha256(data_output),
                "bytes": data_output.stat().st_size,
            },
        },
    }
    manifest_output = output.with_suffix(".manifest.json")
    manifest_output.write_text(
        json.dumps(output_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return output, manifest_output


if __name__ == "__main__":
    archive, manifest = build_release()
    print(DIST_DIR / f"Foreverpedia-{ADDON_VERSION}-Core.zip")
    print(DIST_DIR / f"Foreverpedia_Data-{DATA_ADDON_VERSION}.zip")
    print(archive)
    print(DIST_DIR / f"Foreverpedia-{ADDON_VERSION}-With-QuestieDB.zip")
    print(manifest)

