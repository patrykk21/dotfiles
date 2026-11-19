import importlib.util
import io
import json
import os
import re
import tempfile
import time
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location("statusline", os.path.join(os.path.dirname(__file__), "statusline.py"))
sl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sl)


def strip_ansi(s):
    return re.sub(r"\x1b\[[0-9;]*m", "", s)


def render(payload, columns="100"):
    with mock.patch.object(sl, "feed_pilot"), mock.patch.dict(os.environ, {"COLUMNS": columns}), \
            mock.patch("sys.stdin", io.StringIO(json.dumps(payload))), \
            mock.patch("sys.stdout", new_callable=io.StringIO) as out:
        sl.render()
    return strip_ansi(out.getvalue())


class StatusLineTest(unittest.TestCase):
    def test_outside_a_repo_shows_model_and_context_on_one_line(self):
        out = render({"model": {"display_name": "Opus"}, "context_window": {"used_percentage": 42.4},
                      "workspace": {"current_dir": tempfile.gettempdir()}})
        self.assertEqual(out, "Opus · ctx 42%\n")

    def test_in_a_worktree_shows_the_main_repo_name_and_the_worktree_branch(self):
        with tempfile.TemporaryDirectory() as root:
            gitdir = os.path.join(root, "app", ".git", "worktrees", "T-1")
            os.makedirs(gitdir)
            with open(os.path.join(gitdir, "commondir"), "w") as f:
                f.write("../..")
            with open(os.path.join(gitdir, "HEAD"), "w") as f:
                f.write("ref: refs/heads/T-1-fix\n")
            tree = os.path.join(root, "trees", "T-1")
            os.makedirs(tree)
            with open(os.path.join(tree, ".git"), "w") as f:
                f.write(f"gitdir: {gitdir}\n")
            out = render({"model": {"display_name": "Opus"}, "workspace": {"current_dir": tree}}, columns="40")
        self.assertEqual(out, "Opus · ctx -- · app ▸ T-1-fix\n")

    def test_line_is_cut_to_the_terminal_width(self):
        out = render({"model": {"display_name": "Opus " * 20}, "workspace": {"current_dir": tempfile.gettempdir()}},
                     columns="30")
        self.assertEqual(len(out.rstrip("\n")), 29)
        self.assertTrue(out.rstrip("\n").endswith("…"))

    def test_first_render_of_a_session_prunes_pilot_stamps_older_than_a_day(self):
        with tempfile.TemporaryDirectory() as cache, mock.patch.object(sl, "CACHE_DIR", cache), \
                mock.patch.object(sl, "detach") as detach, mock.patch.object(sl, "PILOT", __file__):
            now = time.time()
            for name, age in (("pilot-old", 2 * 86400), ("pilot-recent", 3600)):
                path = os.path.join(cache, name)
                open(path, "w").close()
                os.utime(path, (now - age, now - age))
            sl.feed_pilot("{}", {"session_id": "new"}, now)
            self.assertEqual(sorted(os.listdir(cache)), ["pilot-new", "pilot-recent"])
            self.assertEqual(detach.call_count, 1)


if __name__ == "__main__":
    unittest.main()
