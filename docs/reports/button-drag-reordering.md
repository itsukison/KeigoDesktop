# Dashboard button drag reordering

The dashboard uses a native NSTableView inside a bounded NSScrollView for button order.
Six-dot handles expose open-hand cursor rectangles and initiate native row dragging;
the title area selects the editor separately. Drag start requests a closed-hand cursor.
The native session provides insertion feedback, cancel animation and autoscrolling.
Drop gaps include the beginning and end of the list. Only drags originating in the same
table with an unchanged source order and matching private pasteboard payload are accepted.

Hover does not mutate the model. A successful changed drop calls the existing serialized
order persistence once. No-op drops and cancellation perform no writes. Button identities,
visibility, instructions and current editor drafts are retained. Accessible move controls
remain available in the editor. Main slot and compact sort order are normalized on drop.

## Validation

- Debug native build passed with code signing disabled; no compiler warnings in the new component.
- 13 focused order/release tests passed, including every insertion gap in a four-row list,
  no-op gaps, stale identifiers, invalid bounds and preservation of non-order fields.
- Offline saved-button integration passed, including move-to-first, move-to-last,
  persistence/reload and no-op write suppression alongside existing CRUD/account checks.
- `git diff --check` passed.
- Hands-on pointer, cursor and drag-autoscroll verification is left to the user as requested.
