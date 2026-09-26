# Release and experiment branch map

The integration branch is intentionally **not merged into main**. Live cross-app and
telemetry acceptance remain open. No remote branches, release tags, deployments, or
published releases were changed.

| Branch | Commit / baseline | Purpose and replacement |
|---|---|---|
| `main` | `5bbc2e0` | Verified baseline; still unchanged |
| `codex/redesign-multiple-buttons` | implementation `7a107f2` plus this handoff | Multiple saved buttons, phone sync, redesign, placement, intro, copy-to-reply, rebuilt Buttons/setup |
| `codex/universal-button-experiment` | `1d33d6c`, based on `7a107f2` | Universal action, local styles, context resolver, settings/setup, additive backend, evaluation tools; automatic Reply hard-off |
| `codex/reply-context-experiment` | `1803e03`, based on `7a107f2` | Multiple-button release plus automatic AX/DOM Reply, development bridge, browser extension and backend research; enabled in Debug only |
| `codex/reply-context-original` | `b23ea7c` | Original mixed experiment, renamed to free the requested independent experiment name |
| `codex/bar-glass-exploration` | `2f3dd7c` | Audited checkpoint of the original dirty product work; original branch tip was `f203233` |
| `bar-positioning` | `63f57f5` | Retained pending acceptance; approved placement work is in the integration branch |
| `reply-context-v1` | `4f763c4` | Original mixed universal/Reply/marketing implementation; retained pending acceptance |
| `release/0.1.6` | `c9c8884` | Historical local release branch; retained pending acceptance |

The experiment code baseline is the final release implementation, `7a107f2`.
Subsequent integration commits containing only this handoff do not change that baseline.
The experiments are independent siblings, not stacked on each other.

## Recovery references

Every original local branch tip has a `recovery/20260925/<original-branch-name>` tag:

- `main` → `5bbc2e0d1ecdc83a2e3180123319342901bbe8eb`
- `bar-positioning` → `63f57f5ff66afb7931819ab4c56b421a18489156`
- `codex/bar-glass-exploration` → `f203233c0f2acaf303f128f6058f350f5ee67bf8`
- `codex/reply-context-experiment` → `b23ea7cc27b337a60a35e9e3801186dcbf01c108`
- `reply-context-v1` → `4f763c44e5b15ad78391bf12c2470fc555f6fc46`
- `release/0.1.6` → `c9c88846c8f6e0a8ee0f1fd900aa8b3008f1a16a`

`recovery/20260925/product-checkpoint` points to
`2f3dd7c2ca6298d8b39ef3f621c0e2edf442d606`, preserving all audited product changes
that were dirty before separation. Original mixed implementations and unrelated
marketing work remain recoverable from those refs.

The private, ignored local archive is `.local-recovery/20260925/`:

- `history.bundle`: verified complete Git history including the original stash.
- `workspace.tar.gz` and `manifest.json`: all 679 originally inventoried nonignored
  tracked/untracked files, each verified against its SHA256 hash with zero mismatches.
- Initial branch, worktree, stash, status and diff inventories.
- `untracked/reply-diagnostics.json` and the original writing-preference study files.

The study sources are also preserved on the universal experiment. Diagnostics stay
outside Git. Existing ignored configuration/private files were left in place.

The existing stash remains untouched at
`adff9b0a490f7f8025a6e1f6b93cec9b737315e4`
(`On main: codex-preserve-local-before-reply-context`).

## After acceptance

Merge `codex/redesign-multiple-buttons` into local `main` only after the checks listed
in [verification.md](verification.md) pass. Then remove obsolete local names
`bar-positioning`, `codex/bar-glass-exploration`, `codex/reply-context-original`,
`reply-context-v1`, and `release/0.1.6`, checking their tips against the recovery refs
first. Keep the two experiments, all recovery/release tags, remotes and the stash.

Concurrent update-introduction work is intentionally left uncommitted in the original
checkout. Do not reset it or include it accidentally when merging. Its shared-file
changes, new What's New views/store/tests, localized appcast scripts, release workflow
and release documentation remain separate from these commits.
