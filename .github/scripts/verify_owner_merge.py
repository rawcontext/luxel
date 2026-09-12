import json
import os
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


def main():
    sha = os.environ["GITHUB_SHA"]
    repository = "rawcontext/luxel"
    authorized = False
    for candidate in github_api(f"repos/{repository}/commits/{sha}/pulls"):
        pull = github_api(f"repos/{repository}/pulls/{candidate['number']}")
        if is_owner_merge(pull, sha):
            authorized = True
            break
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"authorized={str(authorized).lower()}\n")
    print("Owner merge verified." if authorized else "No owner merge: tests and TestFlight will be skipped.")


if __name__ == "__main__":
    main()
