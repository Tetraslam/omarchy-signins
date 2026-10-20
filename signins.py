#!/usr/bin/env python3
"""Which of your command-line sign-ins have lapsed, as one JSON object.

Each check runs only when its tool is installed and configured, never
prompts, and comes with the command that fixes it.
"""

import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def run(command, timeout=15):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout,
                                stdin=subprocess.DEVNULL, env={**os.environ, "CLOUDSDK_CORE_DISABLE_PROMPTS": "1"})
        return result.returncode, (result.stdout + result.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except OSError as exc:
        return 127, str(exc)


def gcloud_detail(text):
    lowered = text.lower()
    if "reauth" in lowered:
        return "Your organization wants you to sign in again"
    if "invalid_grant" in lowered or "refresh" in lowered:
        return "Session expired"
    return first_line(text)


def first_line(text):
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line.removeprefix("ERROR: ")[:160]
    return ""


def gcloud():
    if not shutil.which("gcloud"):
        return []
    code, account = run(["gcloud", "config", "get-value", "account"])
    account = account.splitlines()[-1].strip() if code == 0 and account else ""
    checks = []
    fix = "gcloud auth login --update-adc"
    if account and account != "(unset)":
        code, out = run(["gcloud", "auth", "print-access-token", "--quiet"])
        checks.append({"id": "gcloud", "name": "Google Cloud", "account": account, "ok": code == 0,
                       "detail": "" if code == 0 else gcloud_detail(out), "fix": fix})
    adc = Path(os.environ.get("CLOUDSDK_CONFIG") or Path.home() / ".config/gcloud") / "application_default_credentials.json"
    if adc.exists():
        code, out = run(["gcloud", "auth", "application-default", "print-access-token"])
        checks.append({"id": "gcloud-adc", "name": "application default credentials", "account": account,
                       "ok": code == 0, "detail": "" if code == 0 else gcloud_detail(out), "fix": fix})
    return checks


def github():
    if not shutil.which("gh"):
        return []
    code, out = run(["gh", "auth", "status", "--active"])
    if code == 0:
        return [{"id": "gh", "name": "GitHub CLI", "account": "", "ok": True, "detail": "", "fix": "gh auth login"}]
    if "not logged" in out.lower() and "github.com" not in out.lower():
        return []
    return [{"id": "gh", "name": "GitHub CLI", "account": "", "ok": False, "detail": first_line(out), "fix": "gh auth login"}]


def tailscale():
    if not shutil.which("tailscale"):
        return []
    code, out = run(["tailscale", "status", "--json"])
    if code not in (0, 1):
        return []
    try:
        state = json.loads(out).get("BackendState", "")
    except ValueError:
        return []
    if state not in ("NeedsLogin", "NeedsMachineAuth"):
        return [{"id": "tailscale", "name": "Tailscale", "account": "", "ok": True, "detail": "", "fix": "tailscale login"}]
    detail = "Waiting for admin approval" if state == "NeedsMachineAuth" else "Logged out"
    return [{"id": "tailscale", "name": "Tailscale", "account": "", "ok": False, "detail": detail, "fix": "tailscale login"}]


def opencode_mcp():
    if not shutil.which("opencode"):
        return []
    code, out = run(["opencode", "api", "get", "/api/mcp"])
    if code != 0:
        return []
    try:
        servers = json.loads(out).get("data", [])
    except ValueError:
        return []
    checks = []
    for server in servers:
        status = (server.get("status") or {}).get("status")
        if status in ("disabled", None):
            continue
        name = server.get("name", "")
        checks.append({"id": "mcp:" + name, "name": f"OpenCode · {name}", "account": "",
                       "ok": status != "needs_auth", "detail": "Needs sign-in" if status == "needs_auth" else "",
                       "fix": f"opencode mcp auth {name}"})
    return checks


CHECKS = [gcloud, github, tailscale, opencode_mcp]


def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(CHECKS)) as pool:
        results = [check for group in pool.map(lambda f: f(), CHECKS) for check in group]
    json.dump({"ok": True, "checks": results}, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
