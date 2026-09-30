"""Check that the Finder action never overwrites an existing file."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "src" / "new-file.zsh"


class FinderActionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mdrift-finder-test-")
        self.folder = Path(self.temporary.name) / "Folder with spaces and 'quotes'"
        self.folder.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def create_file(self, selected):
        result = subprocess.check_output(["/bin/zsh", str(SCRIPT), str(selected)], text=True)
        return Path(result.rstrip("\n"))

    def test_folder_and_file_selection(self):
        first = self.create_file(self.folder)
        self.assertEqual(first.name, "Untitled.md")
        self.assertEqual(first.read_bytes(), b"")
        first.write_text("Keep these notes.")
        second = self.create_file(first)
        self.assertEqual(second.name, "Untitled 2.md")
        self.assertEqual(first.read_text(), "Keep these notes.")

    def test_concurrent_creation(self):
        with ThreadPoolExecutor(max_workers=4) as pool:
            paths = list(pool.map(self.create_file, [self.folder] * 4))
        self.assertEqual(len(set(paths)), 4)
        self.assertTrue(all(path.read_bytes() == b"" for path in paths))

    def test_symlink_is_not_followed(self):
        target = self.folder / "missing-target"
        (self.folder / "Untitled.md").symlink_to(target)
        self.assertEqual(self.create_file(self.folder).name, "Untitled 2.md")
        self.assertFalse(target.exists())

    def test_no_selection_fails(self):
        result = subprocess.run(["/bin/zsh", str(SCRIPT)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.folder.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
