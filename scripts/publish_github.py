#!/usr/bin/env python3
"""
Script: publish_github.py
Description: Creates GitHub repository via GitHub REST API, sets topics & description,
             configures git remote with PAT, and pushes all 24 commits.
"""

import os
import sys
import json
import subprocess
import urllib.request
import urllib.error

ENV_FILE = os.path.expanduser("~/.env")

def load_pat():
    pat = os.getenv("GITHUB_PAT") or os.getenv("GITHUB_TOKEN")
    if pat:
        return pat.strip()
    
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("GITHUB_PAT=") or line.startswith("GITHUB_TOKEN="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    
    return None

def main():
    pat = load_pat()
    if not pat:
        print("ERROR: GITHUB_PAT not found in environment or ~/.env file.", file=sys.stderr)
        print("Please save your Personal Access Token first.", file=sys.stderr)
        sys.exit(1)

    headers = {
        "Authorization": f"token {pat}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "Antigravity-Agent"
    }

    # 1. Get authenticated user login
    req = urllib.request.Request("https://api.github.com/user", headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            user_data = json.loads(resp.read().decode("utf-8"))
            username = user_data["login"]
            print(f"✓ Authenticated to GitHub as: {username}")
    except urllib.error.HTTPError as e:
        print(f"ERROR: Failed to authenticate to GitHub API (HTTP {e.code}): {e.read().decode()}", file=sys.stderr)
        sys.exit(1)

    repo_name = "aws-secrets-zerotrust"
    description = (
        "Secretless app architecture on AWS — HashiCorp Vault + Secrets Manager, "
        "IRSA, KMS CMK, VPC endpoints, zero hardcoded credentials, least-privilege IAM with explicit denies"
    )
    topics = [
        "security",
        "zero-trust",
        "hashicorp-vault",
        "aws-secrets-manager",
        "iam",
        "terraform",
        "aws",
        "kms",
        "irsa",
        "devsecops"
    ]

    # 2. Create repository
    repo_payload = json.dumps({
        "name": repo_name,
        "description": description,
        "private": False,
        "has_issues": True,
        "has_projects": True,
        "has_wiki": True
    }).encode("utf-8")

    req = urllib.request.Request("https://api.github.com/user/repos", data=repo_payload, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            repo_info = json.loads(resp.read().decode("utf-8"))
            print(f"✓ Created repository: {repo_info['html_url']}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        if "name already exists" in err_body:
            print(f"ℹ Repository '{repo_name}' already exists on GitHub. Continuing setup...")
        else:
            print(f"ERROR: Failed to create repository (HTTP {e.code}): {err_body}", file=sys.stderr)
            sys.exit(1)

    # 3. Add topics
    topics_payload = json.dumps({"names": topics}).encode("utf-8")
    topics_url = f"https://api.github.com/repos/{username}/{repo_name}/topics"
    headers_topics = dict(headers)
    headers_topics["Accept"] = "application/vnd.github.mercy-preview+json"

    req = urllib.request.Request(topics_url, data=topics_payload, headers=headers_topics, method="PUT")
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"✓ Updated topics: {', '.join(topics)}")
    except urllib.error.HTTPError as e:
        print(f"Warning: Failed to set topics (HTTP {e.code}): {e.read().decode()}", file=sys.stderr)

    # 4. Configure git remote & push
    remote_url = f"https://x-access-token:{pat}@github.com/{username}/{repo_name}.git"
    
    # Check if remote origin exists
    res = subprocess.run(["git", "remote"], capture_output=True, text=True)
    if "origin" in res.stdout.split():
        subprocess.run(["git", "remote", "set-url", "origin", remote_url], check=True)
    else:
        subprocess.run(["git", "remote", "add", "origin", remote_url], check=True)

    print("Pushing all commits to GitHub...")
    subprocess.run(["git", "push", "-u", "origin", "master"], check=True)
    print("✓ Successfully pushed repository to GitHub!")
    print(f"Repo URL: https://github.com/{username}/{repo_name}")

if __name__ == "__main__":
    main()
