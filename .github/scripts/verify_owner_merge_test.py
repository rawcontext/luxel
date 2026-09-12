import copy
import unittest

from verify_owner_merge import is_owner_merge


class OwnerMergeTests(unittest.TestCase):
    def setUp(self):
        self.sha = "a" * 40
        self.pull = {
            "merged": True,
            "state": "closed",
            "merge_commit_sha": self.sha,
            "merged_by": {"id": 302437},
            "base": {"ref": "master", "repo": {"id": 1269656539}},
            "head": {"repo": {"full_name": "contributor/luxel"}},
        }

    def test_accepts_owner_merge_including_a_fork(self):
        self.assertTrue(is_owner_merge(self.pull, self.sha))

    def test_rejects_unmerged_other_commits_other_mergers_and_other_targets(self):
        for path, value in [
            (("merged",), False),
            (("state",), "open"),
            (("merge_commit_sha",), "b" * 40),
            (("merged_by", "id"), 999),
            (("base", "ref"), "develop"),
            (("base", "repo", "id"), 999),
        ]:
            with self.subTest(path=path):
                pull = copy.deepcopy(self.pull)
                parent = pull
                for key in path[:-1]:
                    parent = parent[key]
                parent[path[-1]] = value
                self.assertFalse(is_owner_merge(pull, self.sha))

    def test_rejects_missing_merge_metadata(self):
        self.assertFalse(is_owner_merge({}, self.sha))
        for key in ["merged", "state", "merge_commit_sha", "merged_by", "base"]:
            with self.subTest(key=key):
                pull = copy.deepcopy(self.pull)
                del pull[key]
                self.assertFalse(is_owner_merge(pull, self.sha))


if __name__ == "__main__":
    unittest.main()
