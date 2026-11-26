import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_questie_snapshot", ROOT / "tools" / "build_questie_snapshot.py"
)
BUILDER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILDER)


class QuestieSnapshotTests(unittest.TestCase):
    def test_cbor_decoder_handles_snapshot_shapes(self):
        self.assertEqual(BUILDER.decode_cbor(bytes.fromhex("83010203")), [1, 2, 3])
        self.assertEqual(BUILDER.decode_cbor(bytes.fromhex("a1617001")), {"p": 1})

    def test_pinned_archive_generates_compact_relations(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "QuestieSnapshot.lua"
            BUILDER.generate(
                ROOT / "vendor" / BUILDER.QUESTIEDB_FILENAME,
                output,
            )
            generated = output.read_text(encoding="utf-8")
        self.assertIn("Data.QuestieSnapshot = {", generated)
        self.assertIn("itemCount = 15900", generated)
        self.assertIn("npcCount = 6476", generated)
        self.assertIn("questCount = 3829", generated)
        self.assertIn('[2589]=', generated)
        self.assertIn('Слуга Азоры', generated)
        self.assertRegex(generated, r"\[3693\]=\{[^\n]*\[7\]=\{547\}")
        self.assertRegex(generated, r"\[5085\]=\{[^\n]*\[7\]=\{899\}")


if __name__ == "__main__":
    unittest.main()
