"""Fixture-specific diagnostics, not a general or independent semantic grader."""
import collections
import json
import pathlib
import re
import statistics
import sys

root = pathlib.Path(sys.argv[1])
cases = {c["case"]: c for c in json.loads((root / "manifest.json").read_text())}
def overlaps(a, b):
    return a["x"] < b["x"]+b["width"] and b["x"] < a["x"]+a["width"] and a["y"] < b["y"]+b["height"] and b["y"] < a["y"]+a["height"]
def facts(text, topic):
    text = text.lower()
    if topic == "Cedar":
        return "cedar-482" in text and "thursday" in text and ("14:20" in text or re.search(r"2:20\s*p\.?m", text))
    return "indigo-917" in text and "monday" in text and ("09:45" in text or "9:45" in text)
rows = []
for meta_path in sorted((root / "results").glob("*/*/*/attempt.json")):
    meta = json.loads(meta_path.read_text()); c = cases[meta["case"]]
    response = json.loads(pathlib.Path(meta["responseFile"]).read_text()) if meta.get("responseFile") else {}
    result = response.get("result", {})
    draft = result.get("draft") or ""
    evidence = result.get("evidence", [])
    evidence_text = "\n".join(e["excerpt"] for e in evidence)
    other = "Indigo" if c["expected"] == "Cedar" else "Cedar"
    wrong_tokens = ["indigo", "monday", "09:45", "9:45", "ren:"] if other == "Indigo" else ["cedar", "thursday", "14:20", "mina:"]
    contaminated = any(t in (draft+"\n"+evidence_text).lower() for t in wrong_tokens)
    intent_as_evidence = any("agree, and mention" in e["excerpt"].lower() for e in evidence)
    success = bool(result.get("status") == "ready" and facts(draft, c["expected"]) and facts(evidence_text, c["expected"]) and not contaminated and not intent_as_evidence)
    # A deliberately coarse necessary condition: source boxes must intersect the
    # actual visible source text. Passing does not establish tight/correct boxes.
    if c["family"] == "render":
        source = {"x": c["composerBox"]["x"], "y": 140, "width": 520, "height": 50}
        pane_min = 0 if c["width"] == 600 or c["composerBox"]["x"] < 600 else 600
        pane_max = pane_min + 600
    else:
        cropped = c["variant"] == "corrected-crop"
        source = {"x": 50-(18 if cropped else 0), "y": 302-(177 if cropped else 0), "width": 730, "height": 18}
        pane_min, pane_max = (0, 826) if cropped else (18, 844)
    # Header/composer labels are sometimes returned separately. Evaluate spatial
    # grounding of fact-bearing excerpts, not labels against the message rectangle.
    fact_evidence = [e for e in evidence if any(s in e["excerpt"].lower() for s in ["cedar-482", "indigo-917", "thursday", "monday"])]
    hits = bool(fact_evidence) and all(overlaps(e["box"], source) for e in fact_evidence)
    regions = result.get("conversationRegion", [])
    scoped = bool(regions) and all(r["box"]["x"] >= pane_min-5 and r["box"]["x"]+r["box"]["width"] <= pane_max+5 for r in regions)
    rows.append({"model": meta["expectedModel"], "case": c["case"], "family": c["family"], "variant": c["variant"],
                 "repeat": meta["repeat"], "status": result.get("status", meta["status"]),
                 "factAndScopePass": success, "crossPaneContent": contaminated, "intentAsEvidence": intent_as_evidence,
                 "factEvidenceBoxesIntersectSource": hits, "regionsStayInPane": scoped,
                 "modelMs": response.get("modelMs"), "wallMs": meta["wallMs"], "draft": draft,
                 "evidence": evidence, "conversationRegion": regions, "error": response.get("message"),
                 "responseFile": meta.get("responseFile"), "inputTokens": response.get("inputTokens"), "outputTokens": response.get("outputTokens")})
(root / "scored.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False))
groups = collections.defaultdict(list)
for r in rows: groups[(r["model"], r["family"], r["variant"])].append(r)
summary = []
for key, group in groups.items():
    times = [r["modelMs"] for r in group if r["modelMs"] is not None]
    item = dict(zip(["model", "family", "variant"], key))
    item.update(n=len(group), factAndScopePass=sum(r["factAndScopePass"] for r in group),
                crossPaneContent=sum(r["crossPaneContent"] for r in group),
                rejected=sum(r["status"] == "request_failed" for r in group),
                factEvidenceBoxesIntersectSource=sum(r["factEvidenceBoxesIntersectSource"] for r in group),
                regionsStayInPane=sum(r["regionsStayInPane"] for r in group),
                medianModelMs=statistics.median(times) if times else None)
    summary.append(item)
(root / "summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
