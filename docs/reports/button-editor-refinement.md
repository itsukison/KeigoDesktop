# Button setup visual refinement

The purpose selector retains descriptive cards and illustrative examples, with neutral
labels and a common blue selection state. Pink/blue/orange appear only behind the
single white example surface. Before/After body text uses the same size.

Onboarding and dashboard customization now share name/instruction fields, focus borders,
flat selected rows and labeled move controls. The onboarding list no longer uses artwork.
Dashboard visibility and move controls live in the editor; drag ordering remains in the
list. Add is secondary and Delete has a label. Existing save and persistence behavior
is retained. The management row adapts to available width.

## Verification

- Debug native build succeeded with code signing disabled.
- 74 focused Swift tests passed (saved-button release, onboarding, presets and localization).
- Offline saved-button integration harness passed, covering CRUD, ordering, visibility,
  failed writes, identity preservation and account-scoped onboarding drafts.
- Native fixture coverage includes all three languages, 1080 × 700 onboarding,
  1000 × 700 and 920 × 640 dashboard, long/hidden buttons, seven-button onboarding,
  empty/loading/saving/error states. Renders are in `/private/tmp/aside-previews`.
- Initial renders were inspected and the minimum-size dashboard management area was
  tightened. Final visual review and interactive keyboard/focus review are assigned
  to the user; these are not claimed as completed.
- `git diff --check` passed. No backend or overlay implementation changes were made.
