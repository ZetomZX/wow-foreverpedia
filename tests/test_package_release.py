import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "package_release", ROOT / "tools" / "package_release.py"
)
PACKAGE_RELEASE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(PACKAGE_RELEASE)


class PackageReleaseTests(unittest.TestCase):
    def test_release_metadata_is_loaded_from_toml(self):
        self.assertEqual(PACKAGE_RELEASE.BUNDLE_VERSION, "0.9.6")
        self.assertEqual(PACKAGE_RELEASE.ADDON_VERSION, "0.9.6")
        self.assertEqual(PACKAGE_RELEASE.DATA_ADDON_VERSION, "0.9.5")
        self.assertEqual(PACKAGE_RELEASE.MIN_DATA_ADDON_VERSION, "0.9.1")
        self.assertEqual(PACKAGE_RELEASE.INTERFACE_VERSION, 16001)
        self.assertEqual(PACKAGE_RELEASE.DATA_SCHEMA, 3)
        self.assertEqual(PACKAGE_RELEASE.CLIENT_BUILD, "1.60.1.71139")
        self.assertEqual(PACKAGE_RELEASE.QUESTIEDB_VERSION, "1.1.6")

    def test_release_archive_names_support_independent_component_versions(self):
        paths = PACKAGE_RELEASE.release_output_paths(
            bundle_version="1.2.3",
            core_version="1.2.2",
            data_version="1.1.9",
            dist_dir=Path("dist"),
        )
        self.assertEqual(paths["bundle"].name, "Foreverpedia-1.2.3-WoW-Forever.zip")
        self.assertEqual(paths["core"].name, "Foreverpedia-1.2.2-Core.zip")
        self.assertEqual(paths["data"].name, "Foreverpedia_Data-1.1.9.zip")

    def test_archive_names_reject_traversal(self):
        self.assertTrue(PACKAGE_RELEASE.safe_archive_name("QuestieDB/src/api.lua"))
        self.assertFalse(PACKAGE_RELEASE.safe_archive_name("../outside.lua"))
        self.assertFalse(PACKAGE_RELEASE.safe_archive_name("QuestieDB/../../outside.lua"))

    def test_curseforge_archive_layout_is_verified(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            archive_path = Path(temp_dir) / "valid.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("Example/Example.toc", "## Interface: 16001\n")
                archive.writestr("Example/Core.lua", "")
            PACKAGE_RELEASE.verify_release_archive(archive_path, {"Example"})

    def test_curseforge_archive_layout_rejects_root_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            archive_path = Path(temp_dir) / "invalid.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("Example/Example.toc", "## Interface: 16001\n")
                archive.writestr("README.md", "")
            with self.assertRaisesRegex(ValueError, "root-level item"):
                PACKAGE_RELEASE.verify_release_archive(archive_path, {"Example"})

    def test_pinned_questiedb_artifact_is_verified(self):
        metadata = PACKAGE_RELEASE.verify_questiedb(
            ROOT / "vendor" / PACKAGE_RELEASE.QUESTIEDB_FILENAME,
            ROOT / "vendor" / f"QuestieDB-{PACKAGE_RELEASE.QUESTIEDB_VERSION}-release.json",
        )
        self.assertEqual(metadata["version"], "1.1.6")
        self.assertEqual(metadata["contractVersion"], 4)

    def test_pinned_client_recipe_source_is_verified(self):
        hashes = PACKAGE_RELEASE.verify_client_recipes(
            ROOT / "vendor" / "wago" / PACKAGE_RELEASE.CLIENT_BUILD,
            ROOT / "Foreverpedia_Data" / "Recipes.lua",
        )
        self.assertEqual(set(hashes), set(PACKAGE_RELEASE.CLIENT_TABLES))

    def test_compact_questie_source_index_is_verified(self):
        PACKAGE_RELEASE.verify_source_index(ROOT / "Foreverpedia_Data" / "Sources.lua")

    def test_compact_questie_fallback_is_verified(self):
        PACKAGE_RELEASE.verify_questie_snapshot(
            ROOT / "Foreverpedia_Data" / "QuestieSnapshot.lua"
        )

    def test_client_item_search_index_is_verified(self):
        PACKAGE_RELEASE.verify_search_index(ROOT / "Foreverpedia_Data" / "Search.lua")

    def test_separate_data_addon_is_verified(self):
        PACKAGE_RELEASE.verify_data_addon(
            ROOT / "Foreverpedia_Data",
            ROOT / "Foreverpedia" / "Foreverpedia.toc",
        )

    def test_toc_files_and_versions_are_verified(self):
        PACKAGE_RELEASE.verify_toc(
            ROOT / "Foreverpedia", PACKAGE_RELEASE.ADDON_VERSION
        )
        PACKAGE_RELEASE.verify_toc(
            ROOT / "Foreverpedia_Data", PACKAGE_RELEASE.DATA_ADDON_VERSION
        )

    def test_pinned_cmangos_trainer_source_is_verified(self):
        PACKAGE_RELEASE.verify_cmangos(
            ROOT / "vendor" / "cmangos" / "ClassicDB_1_12_1_z2815.sql.gz"
        )


if __name__ == "__main__":
    unittest.main()

