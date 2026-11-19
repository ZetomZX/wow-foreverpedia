import importlib.util
import unittest
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_source_database", ROOT / "tools" / "build_source_database.py"
)
BUILD_SOURCES = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILD_SOURCES)


class BuildSourceDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(ROOT / "vendor" / BUILD_SOURCES.QUESTIEDB_FILENAME) as archive:
            source = archive.read(BUILD_SOURCES.DROP_ENTRY).decode("utf-8")
        cls.items, cls.total = BUILD_SOURCES.parse_drop_table(source)
        cls.supplemental = BUILD_SOURCES.parse_supplemental_sources(
            BUILD_SOURCES.CMANGOS_PATH
        )

    def test_linen_drops_are_complete_and_sorted(self):
        drops = self.items[2589]
        self.assertGreater(len(drops), 32)
        self.assertEqual(drops, sorted(drops, key=lambda value: (-value[1], value[0])))
        self.assertEqual(drops[0], (1949, 100.0, 0, 0))

    def test_generated_manifest_records_unlimited_index(self):
        lua = BUILD_SOURCES.build_lua({2589: self.items[2589]}, "abc", self.total)
        self.assertIn("unlimitedDrops = true", lua)
        self.assertIn("[2589] = {{1949,100,0,0}", lua)

    def test_fishing_sources_include_zone_chance_and_quantity(self):
        fishing = BUILD_SOURCES.parse_fishing_sources(BUILD_SOURCES.CMANGOS_PATH)
        self.assertIn((40, 18.0, 1, 1), fishing[6291])

    def test_fishing_pools_include_fish_and_non_fish_loot(self):
        fishing, pools, names = BUILD_SOURCES.parse_fishing_data(
            BUILD_SOURCES.CMANGOS_PATH
        )
        self.assertIn(6291, fishing)
        self.assertIn((180656, 85.0, 1, 1), pools[21071])
        self.assertIn((180684, 85.0, 1, 1), pools[21153])
        self.assertIn((180655, 60.0, 1, 1), pools[20708])
        self.assertIn((180753, 40.0, 1, 3), pools[7070])
        self.assertEqual(names[180656], "Косяк шалфокуня")

    def test_generated_lua_contains_complete_fishing_indexes(self):
        fishing, pools, names = BUILD_SOURCES.parse_fishing_data(
            BUILD_SOURCES.CMANGOS_PATH
        )
        lua = BUILD_SOURCES.build_lua({}, "abc", 0, fishing, pools, names)
        self.assertIn("fishingItemCount = 128", lua)
        self.assertIn("[21071] = {{180656,85,1,1}}", lua)
        self.assertIn("[20708] = {{180655,60,1,1}", lua)
        self.assertIn('[180656] = "Косяк шалфокуня"', lua)

    def test_profession_gathering_sources_cover_resource_families(self):
        gathering = BUILD_SOURCES.parse_gathering_data(BUILD_SOURCES.CMANGOS_PATH)
        skinning = dict(gathering[2934])[393]  # Ruined Leather Scraps
        copper = dict(gathering[2770])[186]  # Copper Ore
        peacebloom = dict(gathering[2447])[182]  # Peacebloom
        self.assertEqual(len(skinning), 158)
        self.assertEqual(len(copper), 5)
        self.assertEqual(dict(gathering[2835])[186], copper)  # Rough Stone
        self.assertEqual(dict(gathering[774])[186], copper)  # Malachite
        self.assertEqual(len(peacebloom), 2)
        self.assertEqual(copper, tuple(sorted(copper)))

    def test_generated_lua_contains_profession_gathering_index(self):
        gathering = BUILD_SOURCES.parse_gathering_data(BUILD_SOURCES.CMANGOS_PATH)
        lua = BUILD_SOURCES.build_lua({}, "abc", 0, gathering=gathering)
        self.assertIn("gatheringItemCount = 119", lua)
        self.assertIn("[2934] = {{393,{", lua)
        self.assertIn("[2770] = {{186,{1731,2055,3763,103713,181248}}}", lua)
        self.assertIn("[2447] = {{182,{1618,3724}}}", lua)

    def test_supplemental_indexes_cover_every_loot_mechanism(self):
        dream_dust = self.supplemental["disenchant"][11176]
        self.assertIn((2, 46, 50, 404, 20.0, 75.0, 1, 2), dream_dust)
        self.assertIn((2, 51, 55, 384, 22.0, 75.0, 2, 5), dream_dust)

        self.assertIn((2846, 0.0, 1, 1), self.supplemental["objects"][38])
        self.assertIn((6827, 0.0, 2, 4), self.supplemental["containers"][3358])
        self.assertEqual(len(self.supplemental["pickpocket"][929]), 228)
        self.assertEqual(self.supplemental["spellLoot"][15924], [(61898, 100.0, 1, 1)])
        self.assertEqual(len(self.supplemental["mail"][21746]), 49)

    def test_generated_lua_contains_supplemental_indexes(self):
        lua = BUILD_SOURCES.build_lua({}, "abc", 0, supplemental=self.supplemental)
        self.assertIn("disenchantItemCount = 24", lua)
        self.assertIn("pickpocketItemCount = 124", lua)
        self.assertIn("containerItemCount = 2395", lua)
        self.assertIn("objectItemCount = 2976", lua)
        self.assertIn("spellLootItemCount = 159", lua)
        self.assertIn("mailItemCount = 19", lua)
        self.assertIn("[11176] = {{2,46,50,404,20,75,1,2}", lua)


if __name__ == "__main__":
    unittest.main()
