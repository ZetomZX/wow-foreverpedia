import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_recipe_database", ROOT / "tools" / "build_recipe_database.py"
)
BUILD_RECIPES = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILD_RECIPES)


class BuildRecipeDatabaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index, cls.professions = BUILD_RECIPES.build_index()
        cls.class_abilities = BUILD_RECIPES.build_class_ability_index()
        cls.spells = {recipe[0] for recipes in cls.index.values() for recipe in recipes}
        cls.requirements = BUILD_RECIPES.build_recipe_requirements(
            BUILD_RECIPES.SOURCE_DIR, BUILD_RECIPES.CMANGOS_PATH, cls.spells
        )

    def test_linen_has_complete_cross_profession_uses(self):
        recipes = self.index[2589]
        self.assertGreaterEqual(len(recipes), 12)
        self.assertEqual(len(recipes), 12)
        self.assertIn((2963, 197, 2996, 2), recipes)
        self.assertIn((2737, 164, 2844, 2), recipes)
        self.assertIn((3275, 129, 1251, 1), recipes)
        self.assertIn((3919, 202, 4358, 1), recipes)
        self.assertIn((8339, 202, 6714, 1), recipes)
        self.assertNotIn((3115, 164, 3239, 1), recipes)

    def test_generated_manifest_is_pinned(self):
        lua = BUILD_RECIPES.build_lua(
            {2589: self.index[2589]}, self.professions, BUILD_RECIPES.client_manifest()
        )
        self.assertIn('version = "1.60.1.71139"', lua)
        self.assertIn('[197] = "Портняжное дело"', lua)
        self.assertIn('[197] = 136249', lua)
        self.assertIn('[3276] = {{2589,2}}', lua)

    def test_recipe_learning_sources_include_trainers_and_items(self):
        learning = BUILD_RECIPES.build_learning_sources(
            BUILD_RECIPES.SOURCE_DIR, BUILD_RECIPES.CMANGOS_PATH, self.spells
        )
        self.assertIn((2326, 100), learning[3276]["trainers"])
        self.assertEqual(learning[8339]["items"], [(6716, 800, 1)])

    def test_trainer_names_are_embedded_in_both_locales(self):
        _, _, names = BUILD_RECIPES.cmangos_trainer_data(
            BUILD_RECIPES.CMANGOS_PATH, self.spells
        )
        self.assertEqual(names[10276][0], "Rotgath Stonebeard")
        lua = BUILD_RECIPES.build_lua(
            {}, self.professions, BUILD_RECIPES.client_manifest(),
            trainer_names={10276: names[10276]},
        )
        self.assertIn("trainerNames = {", lua)
        self.assertIn(
            '[10276] = {"Rotgath Stonebeard","Rotgath Stonebeard"}', lua
        )

    def test_recipe_requirements_prioritize_teaching_items(self):
        self.assertEqual(self.requirements[27832], (164, 300, 1))
        lua = BUILD_RECIPES.build_lua(
            {}, self.professions, BUILD_RECIPES.client_manifest(),
            requirements={27832: self.requirements[27832]},
        )
        self.assertIn("requirementCount = 1", lua)
        self.assertIn("[27832] = {164,300,1}", lua)

    def test_copper_axe_material_branches_are_not_crossed(self):
        self.assertIn((2657, 186, 2840, 1), self.index[2770])
        self.assertIn((2881, 165, 2318, 3), self.index[2934])
        self.assertIn((3293, 164, 3488, 12), self.index[2840])
        self.assertIn((3293, 164, 3488, 2), self.index[2318])

    def test_class_ability_reagents_are_joined_from_client_tables(self):
        self.assertEqual(len(self.class_abilities), 23)
        self.assertEqual(
            sum(map(len, self.class_abilities.values())), 76
        )
        self.assertIn((20608, 64, 374, 1), self.class_abilities[17030])
        self.assertIn((3561, 128, 237, 1), self.class_abilities[17031])
        self.assertIn((21562, 16, 613, 1), self.class_abilities[17028])
        self.assertIn((693, 256, 354, 1), self.class_abilities[6265])

    def test_generated_lua_contains_class_ability_index(self):
        lua = BUILD_RECIPES.build_lua(
            {}, self.professions, BUILD_RECIPES.client_manifest(),
            class_abilities={17030: self.class_abilities[17030]},
        )
        self.assertIn("Data.ClassAbilityData = {", lua)
        self.assertIn("itemCount = 1", lua)
        self.assertIn("relationCount = 2", lua)
        self.assertIn("[17030] = {{20608,64,374,1},{21169,64,374,1}}", lua)


if __name__ == "__main__":
    unittest.main()
