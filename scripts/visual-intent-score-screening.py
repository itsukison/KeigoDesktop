"""Saved-capture screening; synthetic checks plus explicit human real-scene grades."""
import collections
import json
import math
import pathlib
import re
import statistics
import sys

root = pathlib.Path(sys.argv[1])
cases = {c['case']: c for c in json.loads((root / 'manifest.json').read_text())}
conditions = {c['label']: c for c in json.loads((root / 'conditions.json').read_text())}
grades = json.loads((root / 'manual-grades.json').read_text()) if (root / 'manual-grades.json').exists() else {}

def facts(text, topic):
    text = text.lower()
    if topic == 'Cedar':
        return 'cedar-482' in text and 'thursday' in text and ('14:20' in text or bool(re.search(r'2:20\s*p\.?m', text)))
    return 'indigo-917' in text and 'monday' in text and ('09:45' in text or '9:45' in text)

def overlap(a, b):
    return a['x'] < b['x']+b['width'] and b['x'] < a['x']+a['width'] and a['y'] < b['y']+b['height'] and b['y'] < a['y']+a['height']

rows = []
for p in sorted((root / 'results').glob('*/*/*/attempt.json')):
    label = p.relative_to(root / 'results').parts[0]
    condition = conditions[label]
    meta = json.loads(p.read_text())
    case = cases[meta['case']]
    data = json.loads(pathlib.Path(meta['responseFile']).read_text()) if meta.get('responseFile') else {}
    result = data.get('result', {})
    if data.get('model') and data['model'] != condition['model']:
        raise ValueError('Returned model does not match experimental condition')
    row = dict(condition=label, model=condition['model'], reasoning=condition['reasoning'],
               case=meta['case'], repeat=meta['repeat'], family=case['family'],
               requestSucceeded=bool(result), status=result.get('status', meta['status']),
               wallMs=meta['wallMs'], modelMs=data.get('modelMs'),
               inputTokens=data.get('inputTokens'), outputTokens=data.get('outputTokens'),
               responseFile=meta.get('responseFile'), error=data.get('message'))
    i, o = row['inputTokens'], row['outputTokens']
    row['standardUncachedUSD'] = None if i is None or o is None else (
        i * condition['inputUSDPerMillion'] + o * condition['outputUSDPerMillion']) / 1_000_000
    if case['family'] == 'real':
        grade = grades.get(f'{label}/{meta["case"]}/{meta["repeat"]}')
        row['qualityPass'] = grade['pass'] if grade else None
        row['review'] = grade
    else:
        evidence = result.get('evidence', [])
        draft = result.get('draft') or ''
        source_text = '\n'.join(e['excerpt'] for e in evidence)
        bad = ['indigo', 'monday', '09:45', '9:45'] if case['expected'] == 'Cedar' else ['cedar', 'thursday', '14:20']
        wrong = any(s in (draft+'\n'+source_text).lower() for s in bad)
        intent = any('agree, and mention' in e['excerpt'].lower() for e in evidence)
        row.update(crossPaneContent=wrong, intentAsEvidence=intent,
                   qualityPass=bool(result.get('status') == 'ready' and facts(draft, case['expected'])
                                    and facts(source_text, case['expected']) and not wrong and not intent))
        source = ({'x': case['composerBox']['x'], 'y': 140, 'width': 520, 'height': 50}
                  if case['family'] == 'render' else {'x': 50, 'y': 302, 'width': 730, 'height': 18})
        fe = [e for e in evidence if any(s in e['excerpt'].lower() for s in ['cedar-482', 'indigo-917', 'thursday', 'monday'])]
        row['factEvidenceBoxesIntersectSource'] = bool(fe) and all(overlap(e['box'], source) for e in fe)
    rows.append(row)

groups = collections.defaultdict(list)
for row in rows:
    groups[row['condition']].append(row)
summary = []
for label, group in groups.items():
    measured = [r for r in group if r['standardUncachedUSD'] is not None]
    real = [r for r in group if r['family'] == 'real']
    synthetic = [r for r in group if r['family'] != 'real']
    times = sorted(r['modelMs'] for r in group if r['modelMs'] is not None)
    real_costs = [r['standardUncachedUSD'] for r in real if r['standardUncachedUSD'] is not None]
    cost = statistics.mean(r['standardUncachedUSD'] for r in measured) if measured else None
    real_cost = statistics.mean(real_costs) if real_costs else None
    item = dict(condition=label, model=conditions[label]['model'], reasoning=conditions[label]['reasoning'],
                attempts=len(group), returned=len(measured),
                syntheticPass=sum(r['qualityPass'] is True for r in synthetic), syntheticN=len(synthetic),
                realPass=sum(r['qualityPass'] is True for r in real), realN=len(real),
                realUngraded=sum(r['qualityPass'] is None for r in real),
                realMedianModelMs=statistics.median(r['modelMs'] for r in real if r['modelMs'] is not None) if real else None,
                realMedianReplayWallMs=statistics.median(r['wallMs'] for r in real) if real else None,
                realMeanInputTokens=statistics.mean(r['inputTokens'] for r in real if r['inputTokens'] is not None) if real_costs else None,
                realMeanOutputTokens=statistics.mean(r['outputTokens'] for r in real if r['outputTokens'] is not None) if real_costs else None,
                medianModelMs=statistics.median(times) if times else None,
                descriptiveP95ModelMs=times[math.ceil(len(times)*.95)-1] if times else None,
                meanUSDPerReturnedCall=cost, meanRealUSDPerReturnedCall=real_cost,
                yenPer1000RealCalls=real_cost*150*1000 if real_cost is not None else None,
                knownTestUSD=sum(r['standardUncachedUSD'] for r in measured),
                usageMissing=len(group)-len(measured))
    summary.append(item)
(root / 'scored.json').write_text(json.dumps(rows, indent=2, ensure_ascii=False))
(root / 'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False))
print(json.dumps(summary, indent=2))
