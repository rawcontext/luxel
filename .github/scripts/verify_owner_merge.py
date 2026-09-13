import json
import os
import plistlib
import re
import subprocess


def is_owner_merge(pull, sha):
    return (
        pull.get("merged") is True
        and pull.get("state") == "closed"
        and pull.get("merge_commit_sha") == sha
        and pull.get("merged_by", {}).get("id") == 302437
        and pull.get("base", {}).get("ref") == "master"
        and pull.get("base", {}).get("repo", {}).get("id") == 1269656539
    )


def github_api(path):
    return json.loads(subprocess.check_output(["gh", "api", path], text=True))


def release_version(ref, app_version):
    match = re.fullmatch(r"refs/tags/v(\d+\.\d+(?:\.\d+)?)", ref)
    if not match or match[1] != app_version:
        raise ValueError(f"Release tag {ref} must match the app version {app_version}.")
    return match[1]


def has_passing_merge_tests(sha, repository):
    runs = github_api(
        f"repos/{repository}/actions/workflows/testflight.yml/runs"
        f"?head_sha={sha}&event=push&branch=master&per_page=100"
    )["workflow_runs"]
    for run in runs:
        if not (
            run["head_sha"] == sha
            and run["head_branch"] == "master"
            and run["event"] == "push"
            and run["status"] == "completed"
            and run["actor"]["id"] == 302437
            and run["triggering_actor"]["id"] == 302437
        ):
            continue
        jobs = github_api(f"repos/{repository}/actions/runs/{run['id']}/jobs?per_page=100")["jobs"]
        if any(job["name"] == "Unit tests after merge" and job["conclusion"] == "success" for job in jobs):
            return True
    return False


def main():
    sha = os.environ["GITHUB_SHA"]
    repository = "rawcontext/luxel"
    authorized = False
    for candidate in github_api(f"repos/{repository}/commits/{sha}/pulls"):
        pull = github_api(f"repos/{repository}/pulls/{candidate['number']}")
        if is_owner_merge(pull, sha):
            authorized = True
            break
    version = ""
    if authorized and os.environ["GITHUB_REF"].startswith("refs/tags/"):
        plist = subprocess.check_output(["git", "show", f"{sha}:apps/macos/Configuration/Luxel/Info.plist"])
        version = release_version(os.environ["GITHUB_REF"], plistlib.loads(plist)["CFBundleShortVersionString"])
        if not has_passing_merge_tests(sha, repository):
            raise ValueError("The tagged commit needs passing merge tests. Rerun after its master checks pass.")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"authorized={str(authorized).lower()}\n")
        output.write(f"marketing_version={version}\n")
    print("Owner merge and release checks verified." if authorized else "No owner merge: tests and TestFlight will be skipped.")


if __name__ == "__main__":
    main()
