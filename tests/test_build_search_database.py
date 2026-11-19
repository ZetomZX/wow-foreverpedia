import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_search_database", ROOT / "tools" / "build_search_database.py"
)
BUILD_SEARCH = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILD_SEARCH)


class BuildSearchDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items = {
            locale: BUILD_SEARCH.read_items(path)
            for locale, path in BUILD_SEARCH.SOURCE_PATHS.items()
        }

    def test_known_forever_items_are_indexed_in_russian(self):
        self.assertEqual(self.items["ruRU"][2589], ("Льняной материал", "льняной материал"))
        self.assertEqual(self.items["ruRU"][21071], ("Сырой шалфокунь", "сырой шалфокунь"))

    def test_known_forever_items_are_indexed_in_english(self):
        self.assertEqual(self.items["enUS"][2589], ("Linen Cloth", "linen cloth"))
        self.assertEqual(self.items["enUS"][3372], ("Leaded Vial", "leaded vial"))
        self.assertEqual(self.items["enUS"][21071], ("Raw Sagefish", "raw sagefish"))

    def test_search_normalization_is_case_and_yo_insensitive(self):
        self.assertEqual(BUILD_SEARCH.normalize("  ЁЖОВЫЙ   РЕЦЕПТ  "), "ежовый рецепт")

    def test_generated_manifest_is_pinned(self):
        lua = BUILD_SEARCH.build_lua(
            {
                "ruRU": {2589: self.items["ruRU"][2589]},
                "enUS": {2589: self.items["enUS"][2589]},
            },
            {
                locale: BUILD_SEARCH.sha256(path)
                for locale, path in BUILD_SEARCH.SOURCE_PATHS.items()
            },
        )
        self.assertIn('source = "WoW client ItemSparse"', lua)
        self.assertIn('version = "1.60.1.70959"', lua)
        self.assertIn('ruRU = {', lua)
        self.assertIn('enUS = {', lua)
        self.assertIn('[2589] = {"Льняной материал","льняной материал"}', lua)
        self.assertIn('[2589] = {"Linen Cloth","linen cloth"}', lua)


if __name__ == "__main__":
    unittest.main()
