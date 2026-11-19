import shutil
import subprocess
import unittest
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RuntimeModuleTests(unittest.TestCase):
    def test_localization_key_sets_match(self):
        text = (ROOT / "Foreverpedia" / "Localization.lua").read_text(
            encoding="utf-8"
        )
        match = re.search(
            r"ruRU = \{(.*?)\n    \},\n    enUS = \{(.*?)\n    \},\n\}",
            text,
            re.S,
        )
        self.assertIsNotNone(match)
        russian, english = match.groups()

        def keys(block):
            return set(re.findall(
                r"(?:^\s*|,\s*)([a-z][a-z0-9_]*)\s*=", block, re.M
            ))

        russian_keys = keys(russian)
        english_keys = keys(english)
        self.assertEqual(russian_keys, english_keys)

        runtime_text = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "Foreverpedia").glob("*.lua")
            if path.name != "Localization.lua"
        )
        referenced_keys = set(re.findall(r'\bL\("([a-z][a-z0-9_]*)"', runtime_text))
        self.assertEqual(set(), referenced_keys - russian_keys)

    def test_ui_fallback_text_is_localized(self):
        text = (ROOT / "Foreverpedia" / "UI.lua").read_text(encoding="utf-8")
        for localized_call in (
            'L("money", gold, silver, coins)',
            'L("search_result", result.name, result.itemID)',
            'manifest.dataset or L("unknown")',
        ):
            self.assertIn(localized_call, text)
        for hardcoded_text in (
            'string.format("%dg %ds %dc"',
            'string.format("%dз %dс %dм"',
            '"%s  |cff777777ID %d|r"',
            'manifest.dataset or "unknown"',
        ):
            self.assertNotIn(hardcoded_text, text)

    def test_manual_search_and_minimap_settings_are_wired(self):
        core = (ROOT / "Foreverpedia" / "Core.lua").read_text(encoding="utf-8")
        self.assertIn('if argument == "" then', core)
        self.assertIn("ns.UI:OpenSearch()", core)
        self.assertIn("ns.Settings:Initialize()", core)
        self.assertIn("ns.MinimapButton:Initialize()", core)

        ui = (ROOT / "Foreverpedia" / "UI.lua").read_text(encoding="utf-8")
        self.assertIn("function UI:OpenSearch()", ui)
        self.assertIn("frame.searchBox:SetFocus()", ui)
        self.assertIn("ns.Settings:CreateMinimapCheckButton(optionsPanel)", ui)

        settings = (ROOT / "Foreverpedia" / "Settings.lua").read_text(
            encoding="utf-8"
        )
        self.assertIn("RegisterCanvasLayoutCategory", settings)
        self.assertIn("InterfaceOptions_AddCategory", settings)
        self.assertIn("ForeverpediaDB.showMinimapButton", settings)

        minimap = (ROOT / "Foreverpedia" / "MinimapButton.lua").read_text(
            encoding="utf-8"
        )
        self.assertIn("ForeverpediaDB.minimapButtonAngle", minimap)
        self.assertIn('button:RegisterForDrag("LeftButton")', minimap)

    def test_map_close_defers_addon_window_reopen(self):
        text = (ROOT / "Foreverpedia" / "UI.lua").read_text(encoding="utf-8")
        hook = text.index('WorldMapFrame:HookScript("OnHide"')
        timer = text.index("C_Timer.After(0, reopen)", hook)
        show = text.index("UI.frame:Show()", hook)
        self.assertIn("local function reopen()", text[hook:timer])
        self.assertGreater(timer, show)
        self.assertIn("protected map-close", text[hook:timer + 100])
        self.assertIn("ns.Gamepad:OnWindowOpened()", text[hook:timer])

    def test_gamepad_map_open_avoids_tainted_set_map_id_path(self):
        text = (ROOT / "Foreverpedia" / "UI.lua").read_text(encoding="utf-8")
        start = text.index("local function setWaypointAndOpenMap")
        end = text.index("function UI:ClearDetails", start)
        block = text[start:end]
        self.assertIn("C_Map.OpenWorldMap", block)
        self.assertIn("not openedWithMapAPI and not gamepadLayout", block)

    def test_toc_loads_runtime_dependencies_before_consumers(self):
        entries = [
            line.strip()
            for line in (ROOT / "Foreverpedia" / "Foreverpedia.toc").read_text(
                encoding="utf-8"
            ).splitlines()
            if line.strip() and not line.startswith("##")
        ]
        expected = [
            "DataBridge.lua",
            "Config.lua",
            "Util.lua",
            "Localization.lua",
            "Theme.lua",
            "Storage.lua",
            "Settings.lua",
            "MinimapButton.lua",
            "Search.lua",
            "Provider.lua",
            "ObservationCollector.lua",
            "CraftTree.lua",
            "UI.lua",
            "Gamepad.lua",
            "GamepadNavigation.lua",
            "VersionExchange.lua",
            "Core.lua",
        ]
        self.assertEqual(entries, expected)

    def test_version_exchange_uses_hidden_addon_messages(self):
        text = (ROOT / "Foreverpedia" / "VersionExchange.lua").read_text(
            encoding="utf-8"
        )
        self.assertIn('RegisterAddonMessagePrefix', text)
        self.assertIn('SendAddonMessage', text)
        self.assertIn('frame:RegisterEvent("CHAT_MSG_ADDON")', text)
        self.assertIn('self:SendVersion("GUILD")', text)
        self.assertIn('self:SendVersion("WHISPER", sender, true)', text)
        self.assertIn('L("core_update_available", localVersion, remoteVersion)', text)

        ui_text = (ROOT / "Foreverpedia" / "UI.lua").read_text(encoding="utf-8")
        self.assertIn("function UI:SetAvailableUpdate(version)", ui_text)
        self.assertIn('L("update_available_banner", updateVersion)', ui_text)
        self.assertIn("self:UpdateTopNotices()", ui_text)

    def test_gamepad_navigation_uses_requested_button_roles(self):
        text = (ROOT / "Foreverpedia" / "GamepadNavigation.lua").read_text(
            encoding="utf-8"
        )
        for binding in (
            'toggleTop = "PAD3"',
            'craftTree = "PAD4"',
            'previousTab = "PADLSHOULDER"',
            'nextTab = "PADRSHOULDER"',
            'focusList = "PADLTRIGGER"',
            'focusDetails = "PADRTRIGGER"',
        ):
            self.assertIn(binding, text)
        self.assertIn('IsKeyDown("PADRTRIGGER")', text)
        self.assertIn('setSelected(firstInZone("top"))', text)
        self.assertIn('L("gamepad_combo_separator")', text)
        self.assertIn('frame.gamepadListHint', text)
        self.assertIn('frame.gamepadDetailsHint', text)
        self.assertNotIn('kind = "recipeTree"', text)
        self.assertIn('firstInZone("tree_filters")', text)
        self.assertIn('Gamepad:AdjustDepth(-1)', text)
        self.assertIn('Gamepad:AdjustDepth(1)', text)
        self.assertIn('tree.footer:SetShown', text)
        self.assertIn('nearestDirectional(direction, "tree")', text)
        self.assertIn('REPEAT_DELAY = 0.38', text)
        self.assertIn('zone == "list" or zone == "details"', text)
        self.assertIn('holdItem = "PADRSTICK"', text)
        self.assertIn('ForeverpediaGamepadViewBindingOwner', text)
        self.assertIn('applyViewBinding()', text)
        self.assertIn('key == "PAD1"', text)
        self.assertIn('technical:match("^%d+$")', text)
        self.assertNotIn('FrameControlsManager', text)
        self.assertNotIn('HandlePopupShown', text)
        self.assertNotIn('SetUIFocusState', text)
        self.assertNotIn('TempPortraitAlphaMask', text)
        self.assertNotIn('toggleWindow = "PADBACK"', text)

        gamepad = (ROOT / "Foreverpedia" / "Gamepad.lua").read_text(
            encoding="utf-8"
        )
        self.assertIn('Gamepad:GetFocusedControl()', gamepad)
        self.assertIn('focusedAddonItem ~= nil', gamepad)
        self.assertIn('ns.CraftTree.frame:Hide()', gamepad)
        self.assertIn('Gamepad:DeferNativeR3Tap', gamepad)
        self.assertIn('ForeverpediaProfessionR3BindingOwner', gamepad)
        self.assertIn('securecallfunction, callback', gamepad)
        self.assertNotIn('entry.func =', gamepad)
        self.assertNotIn('binding.boundFunction =', gamepad)
        self.assertNotIn('UncacheBindingGroup', gamepad)
        self.assertNotIn('FrameControlsManager', gamepad)
        self.assertNotIn('gamepad_button_tabs', text)
        self.assertNotIn('gamepad_button_scroll', text)

    @unittest.skipUnless(shutil.which("lua"), "Lua interpreter is not installed")
    def test_lua_runtime_specs(self):
        lua = shutil.which("lua")
        for spec in sorted((ROOT / "tests" / "lua").glob("*_spec.lua")):
            with self.subTest(spec=spec.name):
                subprocess.run(
                    [lua, str(spec), str(ROOT)],
                    check=True,
                    cwd=ROOT,
                    text=True,
                )


if __name__ == "__main__":
    unittest.main()
