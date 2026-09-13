import copy
import unittest
from unittest.mock import patch

from verify_owner_merge import has_passing_merge_tests, is_owner_merge, release_version


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

    def test_release_tag_must_match_the_app_version(self):
        self.assertEqual("1.4.0", release_version("refs/tags/v1.4.0", "1.4.0"))
        self.assertEqual("1.4", release_version("refs/tags/v1.4", "1.4"))
        for ref, version in [
            ("refs/tags/v1.4.0", "1.3.1"),
            ("refs/tags/v1.4.0-beta", "1.4.0"),
            ("refs/tags/vlatest", "1.4.0"),
            ("refs/tags/cli-v1.4.0", "1.4.0"),
            ("refs/heads/master", "1.4.0"),
        ]:
            with self.subTest(ref=ref, version=version), self.assertRaises(ValueError):
                release_version(ref, version)

    def test_release_requires_successful_merge_tests_for_the_exact_commit(self):
        run = {
            "id": 42,
            "head_sha": self.sha,
            "head_branch": "master",
            "event": "push",
            "status": "completed",
            "actor": {"id": 302437},
            "triggering_actor": {"id": 302437},
        }
        jobs = {"jobs": [{"name": "Unit tests after merge", "conclusion": "success"}]}
        with patch("verify_owner_merge.github_api", side_effect=[{"workflow_runs": [run]}, jobs]):
            self.assertTrue(has_passing_merge_tests(self.sha, "rawcontext/luxel"))

        for key, value in [
            ("head_sha", "b" * 40),
            ("head_branch", "contributor-branch"),
            ("event", "pull_request"),
            ("status", "in_progress"),
            ("actor", {"id": 999}),
            ("triggering_actor", {"id": 999}),
        ]:
            with self.subTest(key=key), patch(
                "verify_owner_merge.github_api", return_value={"workflow_runs": [{**run, key: value}]}
            ):
                self.assertFalse(has_passing_merge_tests(self.sha, "rawcontext/luxel"))

        for job in [
            {"name": "Unit tests after merge", "conclusion": "failure"},
            {"name": "Unit tests after merge", "conclusion": "skipped"},
            {"name": "Unit tests after merge", "conclusion": None},
            {"name": "Build and Upload to TestFlight", "conclusion": "success"},
        ]:
            with self.subTest(job=job), patch(
                "verify_owner_merge.github_api", side_effect=[{"workflow_runs": [run]}, {"jobs": [job]}]
            ):
                self.assertFalse(has_passing_merge_tests(self.sha, "rawcontext/luxel"))

        with patch("verify_owner_merge.github_api", return_value={"workflow_runs": []}):
            self.assertFalse(has_passing_merge_tests(self.sha, "rawcontext/luxel"))


if __name__ == "__main__":
    unittest.main()
