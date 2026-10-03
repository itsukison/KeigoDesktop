"""Replay a prepared matrix through the existing app's normal AuthService.

The operator selects the server model before invocation. No credentials are read,
copied, or printed. Independent attempts continue after individual model failures.
"""
import argparse
import json
import pathlib
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument("root", type=pathlib.Path)
p.add_argument("label")
p.add_argument("--model", required=True)
p.add_argument("--repeats", type=int, default=3)
p.add_argument("--app", default="/tmp/keigo-visual-build/Build/Products/Debug/KeigoButton.app/Contents/MacOS/KeigoButton")
a = p.parse_args()
cases = json.loads((a.root / "manifest.json").read_text())
folder = a.root / "results" / a.label
folder.mkdir(parents=True, exist_ok=True)
for case in cases:
    for repeat in range(1, a.repeats + 1):
        dest = folder / case["case"] / str(repeat)
        dest.mkdir(parents=True, exist_ok=False)
        started = time.monotonic()
        try:
            run = subprocess.run([a.app, "--visual-intent-replay", case["request"], "--output", str(dest)],
                                 capture_output=True, text=True, timeout=60)
            returncode = run.returncode
        except subprocess.TimeoutExpired:
            returncode = -1
        meta = {"case": case["case"], "repeat": repeat, "expectedModel": a.model,
                "returncode": returncode, "wallMs": round((time.monotonic()-started)*1000)}
        files = list(dest.glob("*.json"))
        if len(files) == 1:
            response = json.loads(files[0].read_text())
            meta["responseFile"] = str(files[0])
            meta["status"] = response.get("result", {}).get("status", response.get("status"))
            if "model" in response and response["model"] != a.model:
                raise RuntimeError("Server model differs from requested experimental condition; stop.")
        else:
            meta["status"] = "no_response_artifact"
        (dest / "attempt.json").write_text(json.dumps(meta, indent=2))
        print(f'{a.label}: {case["case"]} {repeat}/{a.repeats}: {meta["status"]} ({meta["wallMs"]} ms)', flush=True)
