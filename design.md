# KeigoButton — Desktop Design System

> A quiet writing companion: a translucent glass frame, a clear white workspace,
> precise dark type, and controls whose emphasis follows the user's next action.

## 1. Authority and scope

This is the visual direction for the **native macOS app**: main window, preferences,
account, writing styles, first-run onboarding, and their relationship to the floating
overlay. It replaces the Willow visual system for those light surfaces. The landing
page, `../web`, iOS app, marketing layouts, and web typography are outside this scope.

**Status: implementation direction.** Native visual verification and behavioral results
are recorded separately under `docs/reports/`; this specification alone is not proof of
end-to-end verification.

### Degree of change by surface

| Surface | Design scope | Preserve |
|---|---|---|
| Floating bar and companion panels | Smoked-glass bar and notices, edge-attached generation and opaque answer panels (§9). | Compact controls, font, geometry, focus, placement and behavior |
| Main dashboard and its settings pages | Visual refinement: Aside colors, fonts, sizing, spacing, borders, radii and component details. | Existing page layouts, navigation, content order, groupings and interaction patterns |
| Onboarding | Full visual rebuild: frame, typography, spacing, components and screen compositions. | Existing step semantics, native behavior and practice gates |

For the dashboard, start from the working layout. Aside informs its visual treatment;
its browser screens do not justify rearranging ours. Size and spacing adjustments are
local refinements, not a requirement to adopt every proposed measurement. Preserve
existing dimensions when a change has no clear visual or readability benefit.

Authority is divided deliberately:

- **This file:** visual hierarchy, materials, type, components, assets, and composition.
- **`AGENTS.md`:** product behavior, focus/capture ordering, native window geometry,
  persistence, authentication, billing, localization, and accessibility integration.
- **`reference/aside/`:** supplied visual evidence; observations are recorded below.
- **`onboarding_reference/`:** first-run interaction evidence, subordinate to existing
  product behavior and the visual treatment here.
- **`docs/design.md`:** historical Willow reference; not the current visual authority.

The floating desktop overlay keeps the independent dark palette and sanctioned
exceptions in `AGENTS.md` §8. Aside's translucent app frame is not evidence for a pale-blue
pill over arbitrary desktop wallpaper. Preserve never-key hover states,
capture-before-focus, four docking positions, and insertion behavior.

Proposed app dimensions are **logical macOS points**. Screenshot measurements are
**source-image pixels**; the images do not establish the original display scale.
Color samples are stored RGB values, not official Aside design tokens. Font family,
blur implementation, animation, and exact alpha cannot be established from still images.

## 2. What the references actually show

### Reference inventory

| ID | Supplied image | Size | Evidence and relevance |
|---|---|---|---|
| A | [Download page](reference/aside/Screenshot%202026-09-24%20at%2023.37.37.png) | 1920 × 1080 | Website, not an app layout. Only cyan glow, soft illustration stages, and restrained object shadows inform desktop artwork. Website spacing and browser chrome are excluded. |
| B | [Account / welcome](reference/aside/Screenshot%202026-09-24%20at%2023.38.34.png) | 897 × 554 | Pale atmospheric field; large regular-weight heading left; form lower left; nearly full-height scenic product stage right. White outlined Google control; gray disabled Continue. |
| C | [Subscription choice](reference/aside/Screenshot%202026-09-24%20at%2023.41.06.png) | 887 × 554 | Centered heading and white grouped options; blue radio and link; black Continue; quiet Back; bottom progress. The composition transfers, not its providers or subscription model. |
| D | [Main workspace](reference/aside/Screenshot%202026-09-24%20at%2023.41.43.png) | 1184 × 921 | Translucent sidebar colored by the desktop behind it, white selected navigation row, pale working field, white floating composer, illustrated task cards with restrained shadows. |
| E | [Settings](reference/aside/Screenshot%202026-09-24%20at%2023.42.34.png) | 1177 × 600 | Translucent app sidebar, pale secondary navigation, nearly white content; white grouped rows, gray-blue local selection, dark text, and a saturated blue information banner. |

### Spatial observations

- D's sidebar ends near **x = 274**; E's near **x = 264**: approximately 22–23% of
  those captures, not a mandate for a 274 pt sidebar.
- E's local settings navigation occupies approximately **214 px**, between x = 264
  and x = 478. Its content sheet begins near y = 32 with a rounded top-left corner.
- D's selected sidebar row is about **33 px high**, with white fill and a thin edge.
  E's local selection is about **30 px high**, with gray-blue fill. These are different
  selection treatments for different backgrounds.
- D's composer spans roughly **x = 352–1088, y = 343–397**. Floating treatment is
  reserved for the action surface; ordinary settings rows are flatter.
- B's split begins near **x = 418**, with about 28 px left padding and a small inset
  around the visual. C's choice group is approximately **418 × 155 px**.
- E's content groups start near x = 510, about **32 px inside the content pane**.
  Rows have generous horizontal breathing room and compact vertical spacing.

These observations inform the proportions below. Keep KeigoButton's existing window
sizes and information architecture. Do not add a browser address bar, tab tree, chat
list, provider picker, or fake search control.

### Color evidence

Modal RGB samples within flat regions are listed below. Coordinates use top-left origin
and `(left, top, right, bottom)`, excluding right/bottom. This avoids treating antialiased
text as a palette value. These are source-image values, not a recovered implementation.

| Reference / region | Sample rectangle | Stored RGB | Interpretation |
|---|---|---|---|
| E — upper sidebar | `(70,30,210,45)` | `#B7E2F2` | Blue desktop showing through translucent glass; not a sidebar fill |
| E — main canvas | `(650,90,950,130)` | `#FCFEFE` | Stable, almost-white working plane |
| E — card interior | `(760,275,960,285)` | `#FEFFFF` | Effectively white; normalize to white |
| E — blue banner | `(700,160,960,194)` | `#009AF5` | Saturated interaction/information accent |
| E — local selection | `(315,103,450,127)` | `#E6EDF0` | Local selection darkens on pale secondary plane |
| D — workspace | `(800,140,1000,200)` | `#F0F9FC`, then `#F1F9FC` | Atmospheric pale plane |
| D — selected sidebar | `(80,270,220,289)` | `#FFFFFF` | App-level selection lifts to white on glass |
| C — environment | `(250,140,500,170)` | `#EEFAFF`, then `#EFFAFF` | Pale cyan onboarding field |
| C — Continue interior | `(790,507,860,514)` | `#161717` | Primary navigation is near-black, not universally blue |

The user clarified that the blue in D/E comes from their desktop wallpaper. It is
**not a prescribed sidebar color or bundled landscape**. The sidebar is translucent,
lightly textured translucent glass with only a trace of blue tint; it reveals the real background.
`#F1F9FC`, `#FCFEFE`, and `#009AF5` still inform the opaque surfaces and interaction
accent. The exact material implementation remains a native KeigoButton choice.

## 3. Philosophy: atmosphere around work, clarity at the point of work

**The application should feel like a small, calm place to prepare writing.** Its main
window configures the companion and helps people revisit work. The floating bar remains
the fastest way to act in another app. Home should not become a second chat product,
and settings should not become a marketing page.

1. **Use the environment to carry personality.** Cool sky, snow, diffuse light, and
   depth belong at the edges or on a dedicated illustration stage. They should not
   compete with the user's text.
2. **Increase solidity near an action.** Translucent glass frame → pale local navigation →
   almost-white workspace → white field or card. Text entry and reading surfaces are
   the most stable and least transparent parts of the interface.
3. **Establish hierarchy with placement first.** Group related controls, leave space
   between decisions, then use type weight and surface contrast. Add a border or shadow
   only when it explains a boundary or floating layer.
4. **Separate action from selection.** Near-black is the default primary action on
   light surfaces. Blue identifies selection, focus, links, progress, and occasional
   meaningful callouts. A selected writing style is not a green success state.
5. **Keep familiar native behavior.** Traffic lights, text editing, keyboard navigation,
   scrolling, permission handoff, and a stationary action shelf are part of the design.
6. **Keep KeigoButton's identity.** Retain its keycap character, product name, mascot
   motion, and official app/provider marks. Do not copy Aside's logo or features.
7. **State only what the product knows.** Actual history, saved style, permission,
   subscription, and quota drive the UI. No invented time saved, placeholder entitlements,
   fake installed apps, or decorative controls.

The signature is the relationship between translucent desktop glass and white working surfaces.
Replacing indigo with cyan while keeping every old gray container, tinted preview,
and accent-filled button would not achieve this direction.

## 4. Semantic color and material system

### Light tokens — proposed implementation targets

These are target roles, not declarations already present in `DesignTokens.swift`.
**Choice** means a KeigoButton decision informed by evidence, not a measured Aside token.

| Token | Value | Role / provenance |
|---|---|---|
| `environment` | `#EDFAFF` | Pale onboarding/window field; normalized from B/C |
| `sidebarBase` | `#EFF1F2` | Neutral opaque fallback for Reduce Transparency / Increase Contrast |
| `sidebarGlassTint` | `#EFF6FA` at 78% | Pale, slightly cool translucent scrim over the actual desktop |
| `secondaryPanel` | `#F1F9FC` | Preferences navigation, quiet backing; observed family |
| `canvas` | `#FCFEFE` | Working plane; sampled in E |
| `surface` | `#FFFFFF` | Cards, fields, chosen sidebar destination |
| `surfaceHover` | `#F3F8FA` | Quiet hover on white; choice |
| `selectionLocal` | `#E6EDF0` | Selected local navigation; sampled in E |
| `selectionTint` | `#E5F4FE` | Selected option/badge plate; choice |
| `textPrimary` | `#111111` | Near-black text; normalized choice |
| `textSecondary` | `#606A70` | Descriptions and important metadata; contrast-adjusted choice |
| `textMuted` | `#6F7578` | Less prominent captions on white; initial estimate retained |
| `textOnSidebar` | `#27343B` | Inactive navigation on translucent glass; contrast-adjusted choice |
| `actionPrimary` | `#171919` | Main button; normalized from C's `#161717` |
| `actionPrimaryHover` | `#2B3032` | Hover without fading label; choice |
| `actionPrimaryPressed` | `#080A0B` | Pressed; choice |
| `accent` | `#009AF5` | Bright indicator / controlled callout; sampled in E |
| `accentText` | `#006FC9` | Small links, selected labels, focus/selection boundaries; choice |
| `success` | `#26735C` | Confirmed saved/granted/complete; choice |
| `warning` | `#8A5700` | Recoverable attention state; choice |
| `error` | `#B42332` | Error/destructive emphasis; choice |
| `controlOff` | `#DDE4E7` | Inactive tracks; choice |
| `disabledSurface` | `#E6ECEF` | Disabled button fill; choice |
| `disabledText` | `#77838A` | Disabled label only; choice |
| `borderSubtle` | `#111111` at 8% | Cards/separators on controlled light surfaces |
| `borderControl` | `#111111` at 12% | Input/button outline; stronger than grouping lines |
| `edgeLight` | white at 45% | Highlight only where a translucent edge needs definition |
| `scrim` | black at 24% | Centered preferences modal; choice, not observed in E |

**Blue is not the universal button fill.** Prefer black Continue, Save, Grant access,
and Upgrade buttons; white or quiet gray secondary actions; blue text links. Use one
dominant action per local task. A blue banner is for a specific actionable condition,
such as missing permission, not a permanent brand stripe.

**Contrast governs the rendering.** White text on `#009AF5` has only about **3.03:1**
contrast; do not copy the reference's banner as a small-text recipe. Use `#111111` text
on bright blue (**6.24:1**), or a pale blue callout with dark text. `#006FC9` reaches
approximately **5.10:1** on white and **4.78:1** on `#F1F9FC`. `#27343B` on the opaque
sidebar fallback reaches approximately **11.3:1**. These are calculated solid-color sRGB
pairs, not validation of a composited screen. The project gate is at least 4.5:1 for
ordinary text and 3:1 for meaningful control indicators/focus boundaries. Recheck actual
backgrounds wherever imagery or alpha changes the pair. Disabled controls never carry
essential instructions.

### Surface hierarchy and material recipe

| Plane | Treatment | Contents |
|---|---|---|
| Environment | Live desktop glass around the workspace; pale scenic stages in onboarding | Shell, onboarding stage |
| App navigation | Translucent pale scrim, fine static grain, barely blue tint | Brand, Home, Buttons, account/settings |
| Local navigation | Opaque `secondaryPanel` | Preferences categories, local selectors |
| Workspace | Opaque `canvas` | Headings, history, instructions, style layout |
| Interactive surface | White, controlled border, occasional lift | Fields, cards, groups, dialogs |

For the main sidebar and exposed shell margins, use a **78% opaque pale scrim**
(`sidebarGlassTint`). This uses the same alpha-compositing mechanism as the onboarding
intro's dimming layer, with a pale fill instead of black. The actual desktop or window
behind remains visibly present at approximately 22%. Do not use `NSVisualEffectView`
`.sidebar` material here: its heavy system wash made the sidebar read as solid gray.
This treatment is transparent, not blurred; do not claim it provides a custom blur.

The main window has a clear backing and `isOpaque = false`. The background extends
behind the traffic lights. The workspace and selected navigation row remain opaque;
never lower the whole window's alpha or the opacity of foreground labels/controls.
Use the existing fixed `.aqua` appearance, supported on macOS 14.

Add fine monochrome grain at 4.5% opacity: a cached, deterministic 256 × 256 pixel tile
at 128 × 128 pt, without animation or per-layout regeneration. Keep the grain subdued
so it does not turn the glass into a gray texture. Use dark sidebar labels to maintain
contrast over the darkest composite.

With Reduce Transparency **or Increase Contrast**, replace the scrim and grain with
opaque neutral `sidebarBase`. Keep white selection and all boundaries. Onboarding
retains its pale environment and illustration stages; this sidebar correction does not
restyle onboarding or the independently dark overlay.

## 5. Typography, rhythm, shape, and elevation

### Typography

Use **SF Pro through the system font API**, with native Japanese and Simplified Chinese
fallbacks. This is a native-app choice; the screenshots do not identify Aside's font.
Replace Inter as the light-window default when implementing. Use system monospaced
digits where counters/dates need alignment, and system mono only for actual technical
identifiers. Do not turn all captions into mono.

| Role | Main window | Onboarding | Weight |
|---|---|---|---|
| Page heading | 22 pt | 32 pt | Medium on dashboard; regular on onboarding |
| Welcome headline | — | 40 pt | Regular |
| Section heading | 16 pt | 20 pt | Medium |
| Body / instruction | 14 pt | 18 pt for essential instructions | Regular |
| Navigation / row label | 14 pt | 14 pt progress label | Regular; Medium when selected |
| Form label / action | 13–14 pt | 16 pt action | Medium |
| Secondary description | 13 pt | 14–16 pt | Regular |
| Caption / metadata | 12 pt; 11 only for nonessential compact metadata | 13 pt | Regular |
| Counted statistic | 26 pt | — | Medium, monospaced digits |
| Introductory display | — | Up to 32 pt on account welcome | Regular or Medium |

Use approximately 1.4–1.5 line height for explanatory Latin text and 1.5–1.65 for longer
Japanese/Chinese text. Verify native line metrics rather than equating these ratios to
SwiftUI `lineSpacing`. Do not tighten CJK tracking. Avoid thin or oversized display type
on functional screens. Preserve readable practice-text sizes.

Existing `opticalCentre`/`opticalPadding` helpers were measured for previous fonts.
Retain their purpose but remeasure all three languages before carrying the same offset
into SF. Never vertically offset editable text to fix icon alignment.

### Layout tokens

| Role | Target |
|---|---|
| Spacing steps | 4, 8, 12, 16, 20, 24, 28, 32, 48 pt; 2/6/10 for optical details |
| Main window | Existing 1000 × 700 pt; minimum 920 × 640 pt |
| Main sidebar | Existing 218 pt, full height; reference proportion is guidance |
| Content inset | 4 pt top/right/bottom; no extra outer border |
| Content panel radius | 16 pt continuous |
| Page gutter | Preserve existing 32 pt; consider a local adjustment only for demonstrated fit/readability benefit |
| Section gap | Preserve existing 28 pt; refine locally where the grouping needs it |
| Card padding | 16 pt; 20 for large text/summary cards |
| Related item gap | 8–12 pt |
| Main navigation row | 34 pt high, 10 pt outer gutter, 10 pt radius |
| Standard control | 36 pt high; 40 in onboarding |
| Compact row control | 28–32 pt high, with intentional click target |
| Settings row | 56 pt minimum; grows for wrapped descriptions |
| Input/button radius | 10 pt |
| Card radius | 14 pt; 16 for larger groups |
| Preferences modal radius | 20 pt |
| Badge radius | 6 pt; capsule only for keycaps or genuinely pill-shaped UI |
| Onboarding stage | 20 pt radius; stable full available height |

The 36/40 pt scale belongs to light windows. Overlay 28/34 pt geometry, side composer
dimensions, notch shape, and panel size limits remain under `AGENTS.md`.

With the existing 32 pt gutters, the content budget is `1000 − 218 − 4 − 64 = 714 pt`.
At the 920 pt minimum it is **634 pt**. Three style options with two 12 pt gaps get
about **203 pt each** at minimum size. Keep examples readable; let pages scroll vertically.
Do not shrink all text to fit more cards.

### Elevation

- **Ordinary groups:** 1 pt subtle border; no shadow.
- **Main content plane:** black 4%, radius 8, y = 1. Glass/white contrast does most of
  the separation; do not add a divider alongside the panel edge.
- **Floating light action surface / illustrated task card:** black 6%, radius 16,
  y = 6. Only where elevation explains the object, not every settings row.
- **Preferences modal:** black 14%, radius 28, y = 10, over the 24% scrim.
- **Press/selection:** change fill and indicator, not layout or elevation.
- **Overlay:** AppKit shadows and generating-glow exception from `AGENTS.md` §8.

These are proposed SwiftUI parameters, not CSS blur measurements from Aside. Use 1 pt
whole-point colored outlines for focus and selection. Reserve outline space so states
cannot move content.

## 6. Components and states

| Component | Resting / selected appearance | Behavior |
|---|---|---|
| Primary action | Near-black, white medium label, 10 pt radius | Dedicated dark hover/press fills. Explicit disabled tokens. Loading retains width, names the action, prevents repeat submission. |
| Secondary action | White, primary text, control border | Quiet hover; no shadow. Back/Cancel stay secondary. |
| Text action | `accentText` | Clear hover/focus affordance; names a real action/destination. |
| Main sidebar row | Clear on glass; active white plate, subtle edge, primary text | Light white hover wash. Selected weight and accessibility state accompany fill. |
| Local settings row | Clear on pale panel; active `selectionLocal` | Constant geometry. Do not blindly reuse main sidebar white selection. |
| Card / row group | White, subtle outline, 14–16 pt radius | Group label above. Dividers only separate independently actionable rows. |
| Text field | White, 1 pt control border, 10 pt radius | Focus changes edge to `accentText`, without resizing. Visible label. Error edge plus explanation. Placeholder is not a label. |
| Search | White rounded field with search icon | Actual history search only; clear action when populated. No decorative global/settings search. |
| Segmented control | Pale track, white active segment, dark label | Constant widths; accessible selection and keyboard operation. |
| Style option | White/dark text; selected pale blue backing, darker-blue edge and indicator | Whole card clickable. Selection is blue, confirmed success is green. Constant borders and heights. |
| Switch | Native, blue when on, neutral when off | Native keyboard/accessibility behavior. Thumb position also conveys state. |
| Radio | White center, blue indicator | Darker blue edge where needed for contrast. Entire labeled option selects it. |
| Badge | Neutral plate and secondary text by default | Blue for meaningful active/new state; green for confirmed success. 12 pt label, 8/4 pt optical padding. |
| Icon button | 16 pt outline glyph, 28–32 pt click area | Neutral until hover; accessible name, tooltip and visible focus. Avoid large decorative discs. |
| Status callout | Pale semantic tint and dark readable text | Explicit message plus icon; useful recovery action. Color alone never explains state. |
| Progress | Quiet track, blue completed/current indication | Preserve current step semantics and announcements; do not copy Aside's four dots into nine-step setup. |

Retain **Reicon Outline** for product glyphs through role-based `Icon.Name`. Native
widgets, official app/provider logos, and the keycap mark are deliberate exceptions.
Migrate incidental SF Symbols in style options to existing role icons where available;
do not generate raster UI glyphs. Use 16–17 pt navigation icons, 14–16 pt controls,
and 20 pt explanatory plates. Icon plates are neutral by default.

Every interactive component needs default, hover, pressed, keyboard-focus, disabled,
and relevant loading/error states. Hover must not be the only route to discover or
operate a main-window action. Visible focus in key windows does not authorize taking
focus in a never-key overlay.

## 7. Apply the system to the existing desktop product

### Main shell

Keep the current dashboard composition. Refine its surfaces, typography, scale and
details in place; do not move sections or introduce a new layout to resemble Aside.

Keep Home and Buttons in the persistent sidebar, account/settings pinned below.
Reserve 36 pt for native traffic lights; use the existing keycap mark and product name.
The active destination is a white plate on the translucent glass frame. Use the account's
real initial/name on a quiet neutral avatar plate.

The workspace is a nearly white rounded plane. Preserve full-size content-view safe-area
handling and drag-region clearance. Content uses the pane's available width; constrain
individual forms/readable text, not the whole page. No browser toolbar or permanent
third pane merely because Aside is a browser.

### Home: orientation, actual activity, history

Preserve the sequence: one-line explanation of the bar and real used-app icons,
applicable update notice, actual statistics, entitlement-backed offer/quota information,
conditional setup recovery, then searchable history grouped by day.

- Keep the usage hint compact; no welcome hero or second command box.
- Four statistic columns use a plain white card, dark medium numbers, quiet labels.
  Replace the old lavender `StatsBackdrop`; the sidebar already carries atmosphere.
  No mountain or dotted glow behind numbers.
- Shared update, permission, and billing components keep their distinct meaning; do
  not make all of them bright blue banners. Derive offer deadlines, currency, renewal
  terms, quotas, and reset dates from existing models.
- History uses dark excerpts, readable time/app metadata, quiet separators, expansion
  in place, and persistent search. Keep the user's writing on opaque surfaces.
- Empty history names the next actual bar action. Distinguish history-disabled,
  search-empty, loading, and failure from no activity.
- Preserve insertion/copy status truth. Do not invent time saved or example history.

### Buttons: ordered list and explicit editor

Use an ordered list at left and a name/multiline instruction editor at right. The
selected row uses a pale blue local selection; text stays dark on white. Expose a drag
handle, accessible move-up/down controls, enabled toggle and first-item main identity.
Save and Cancel belong below the editor. A new button is only persisted after a valid
save; require both fields. Confirm deleting from Mac and phone. Handle dirty edits
before changing selection, opening settings, closing the window or leaving the page.

The shared account configuration is authoritative. Show loading, signed-out, empty,
saving and recoverable-error states. Preserve user IDs, instructions and customizations.
Language realignment is a deliberate choice; opening the page never reseeds buttons.
Allow the main content to scroll at smaller sizes while keeping the editor readable.

The four-context style editor is preserved on the universal experiment branch only.

### Account and sign-in

The main-window account page remains a settings page, including signed-out state.
Use captioned white groups and labeled forms. Keep all supported sign-in, sign-up,
Google, sign-out and recovery behavior. Do not insert the onboarding split scene here.

First-run account setup may use B's split: form/instruction left, the existing mascot
on the gradient stage right. Google keeps its official colored G and white outlined
button; prominence comes from placement and width. Group authentication in white with
20 pt padding and 16 pt corners, 24 pt below the introduction; avoid a flexible gap
between copy and form. Keep progressive email/password
disclosure and validation. Authentication remains the existing browser-session handoff.

### Preferences and plan

Keep the centered **780 × 540 pt** in-window modal and its dismissal behavior. Adapt
E's internal surface hierarchy: the existing **216 pt local navigation**, now pale,
white content, dark heading,
quiet close button, captioned groups. E shows an embedded browser settings page, not
this modal; the container is our existing product choice.

Preserve the existing 28 pt content gutters: `780 − 216 − 56 = 508 pt` of content.
Keep General / Plan / History / About, all current controls, and vertical scrolling.
Descriptions wrap; trailing controls have deliberate widths. Preserve Escape,
outside-click dismissal, keyboard navigation and focus return. The modal fits the
920 × 640 minimum window with 70 pt horizontal and 50 pt vertical outer space.

Plan choices use white cards, blue selection, and a black purchase/upgrade action.
Preserve billing truth, server-derived currency/dates, annual/monthly choice, existing
restore/manage flows, and explicit terms. Aside's provider choices do not authorize
adding providers, changing plans, or hiding price information.

## 8. First-run composition

Onboarding shares main-window materials and control roles at its readable type scale.
Keep the **1080 × 700 pt fixed window**, saved step IDs, completion version, step order,
and nine-step progress semantics. Paying is not a setup-completion step. Preserve
the desktop introduction and practice gates rather than inventing a new flow.

Use one continuous pale-cyan environment, without the former inset white panel or
labeled top rail. The fixed 1080 × 700 window has 32 pt horizontal margins (1016 pt
composition width), 48 pt top clearance, and a 58 pt navigation shelf 24 pt above the
bottom edge. Content ends 16 pt above the shelf. The standard split is 420 pt copy,
32 pt gap, and 564 pt visual stage. Stage bounds never follow content measurement.
Only overflowing content scrolls; the footer stays fixed.

Nine quiet progress markers sit at the bottom center; the current marker elongates.
Language has no setup marker, and Offer retains its preceding setup position rather
than counting purchase as installation. Back is left, skip beside the black forward
action at right. Google authentication remains attached to its form.

| Step | Composition |
|---|---|
| Language | Small static mascot, semibold centered heading, 480 pt white grouped rows with script glyphs and tinted selection |
| Account | Split; medium headline and compact white form group left, mascot on glow right |
| Name / permission | Split; field/status left, white native scene on mountain right |
| Purpose | Three purpose cards left: Everyday (recommended), Work, Friends & Social. Each contains four buttons. Blue selection, neutral labels and recommendation badge; matching pink/blue/orange artwork only behind a single white demo window and a compact dark four-button bar, with the keycap mark left and pencil right. Only returning desktop accounts with saved buttons see Keep current |
| Button review | Flat full-row selectors on a pale neutral panel, with soft gray-blue selection; selected-name heading and white name/instruction editor beside it. Labeled move controls sit below the fields. Fixed bottom-right Delete label with trash icon and no separator; no Before/After text |
| Saved button / custom / reply | Compact semibold instruction, secondary explanation, live white editor on mountain stage; hover taught in practice |
| Attribution | Centered heading, 640 pt two-column choice group |
| Offer | Centered heading, 560 pt grouped plans, full renewal information and clear decline |
| Completion | Split readiness message and mascot on glow; no claims about skipped lessons |

Onboarding uses 40 pt welcome type, 32 pt page titles, 20 pt section titles, 18 pt live
practice text/instructions, 16 pt body/action labels, and 13 pt metadata. Page headings are
medium; Language and practice actions use semibold for emphasis. Body copy stays regular.
Shared gaps use 8/12/16/24/32/48 pt. Controls are
40 pt tall with 10 pt corners, grouped choices have 16 pt corners, and stages 20 pt.
Every button row selects its own editor, including its surrounding whitespace.
The two customization pages share 10 pt white fields with subtle borders and blue focus,
8 pt label-to-field gaps, 16 pt field gaps and 24 pt group gaps. Onboarding uses 20 pt
editor headings and 16 pt editable text; dashboard uses 16 pt headings and 14 pt editable
text. Field labels are 13 pt medium. Lists have no decorative numbers/checkmarks/chevrons;
retain Main button and Hidden metadata. Dashboard uses six-dot handles with an open-hand cursor and native insertion feedback
in a bounded, autoscrolling reorder list, and
places visibility and labeled move controls in the selected editor. Add is secondary;
Save is primary, with a quiet labeled Delete action. Selection-page Before/After examples
use equal 16 pt body text and a single white preview frame. Customization has no artwork. Show the
main-button role on the first row; keep selection and draft bindings tied to identity
through reordering. Keep instructions concise while retaining necessary tone and format
requirements. Existing saved instructions remain untouched. Illustrative examples belong
on the introduction page, not below the customization editor. Never present a stock
example as a live result of a customized instruction. Keep all choices reachable by scrolling and retain
the fixed navigation shelf.

Practice headers use 28 pt semibold instructions, 16 pt secondary explanations, a
104 pt minimum height aligned toward the stage, and a 16 pt gap before it. Allow longer
translations to grow; never clip or truncate instructions. Mail and reply scenes have
uniform 24 pt outer insets. The retired bar-discovery step resumes at first practice;
keep saved step IDs and completion version unchanged.

The cinematic intro retains its dark scrim, timing, cancellation, Reduce Motion
alternative, and focus ownership. Do not replace the user's real desktop with scenic
art: that moment teaches where the companion lives.

## 9. The dark companion overlay

The overlay belongs to the same product through its character, restrained hierarchy,
and action clarity. Over arbitrary apps it has different contrast needs from a light
workspace. Retain this ramp and the geometry/behavior in `AGENTS.md`:

| Role | Retained value |
|---|---|
| Canvas / surface / hairline | `#141312` / `#1E1C1A` / `#2E2B28` |
| Primary / secondary / tertiary text | `#FDFCFC` / `#A59F97` / `#777169` |
| Notch tab | Pure black; joins hardware housing |
| Density | 11/12/13 pt labels; 14 pt result text; existing 12–16 pt insets |
| Shape | Existing pill and 10 pt input; result corners: bottom 20 pt, sides 18 pt exposed, top 8 pt exposed |

No mountain, dots, light-blue glass, or black-on-blue action treatment enters this
surface. Do not globally recolor `Tokens.Overlay` or change its type through shared
light-window helpers. A modest font refinement is optional, not a migration requirement:
evaluate it separately at the actual compact size in all three languages, preserving
label fit, hit targets, window dimensions and focus behavior. This redesign retains the existing overlay font without changes. Retained secondary/tertiary colors still need legibility review;
they are not a blanket contrast certification.

The bar and auxiliary notices use a 78–84% opaque charcoal tint with a subtle light
edge and opaque accessibility fallback. A native behind-window material blended at 70%
(`glassBlurBlend = 0.70`) softens desktop detail beneath the tint while foreground text
and controls remain crisp. The notch attachment stays pure black.
Error messages remain separate never-key panels, 8 pt inward from their live anchor:
above bottom, below top, right of left, and left of right. Center on the other axis and
keep the entire message inside the anchor's owning-screen work area. A saved button with no
text shows localized guidance without opening the composer; the pencil still composes
from scratch.

Generation and answers expand from their selected edge and replace the bar. Bottom
retains the 176 × 36 pt generation capsule; sides use 176 × 60 pt status panels;
notch/top uses a 40 pt-tall tab at least 208 pt or the housing width. Sides are straight
at attachment with 18 pt exposed corners; top is square against the housing/menu bar
with 8 pt bottom corners. The mascot, Writing/Replying status, and Cancel stay horizontal.
Use the colorful rainbow native BorderBeam palette with the existing timing on exposed edges,
without a luminous seam against the screen. The shell stays stationary. Fade bloom
before window boundaries without fading the attached shell; no native generation shadow.
Reduce Motion uses a static rim and still mascot.

Answers use the shared smoked glass at bottom and side positions, or solid black at
the notch/top, with native shadows. Keep the same `glassBlurBlend` setting as the bar
and retain the exposed-edge border without adding a second material border.
They are 320 pt wide at the sides and 420 pt at bottom/top (at least the housing width
at the top), with 16 pt text insets.
Keep the 14 pt body and compact type. Bottom grows up with 20 pt corners; top grows
down; sides grow inward while keeping vertical center, with ordinary horizontal prose.
Height follows content up to 440 pt at bottom/top, with a 240 pt answer viewport.
Sides can grow to 520 pt with a 320 pt answer viewport. Cap to the available work area
and reserve controls before measuring answer space. Short answers have no artificial
minimum-height slab.

Header: quiet unboxed pager, context label, Close. All results proceed directly to the
answer without a prompt summary or separate instruction editor. The footer regenerate
control handles reruns and additional guidance. Keep hover-to-refine, feedback,
page history and destination-aware Insert/Copy. Secondary icons are quiet until hover
or keyboard focus; the white primary action remains prominent. The localized destination
notice wraps above the footer and reserves its measured height to prevent action movement.

Fade only overflowing answer text, and remove the fade when the last line is reached.
There is no footer divider or decorative scroll control. Generation/results use a brief
opacity handoff without scaling text; Reduce Motion is immediate. Result windows are
attached and cannot be dragged freely. `AGENTS.md` governs screen ownership, geometry,
capture-before-focus, cancellation/recovery and insertion. Visual changes never change
the write destination. No scenic imagery or light-window surface treatment enters them.

Copied text is quiet availability: a static neutral dot in the unchanged collapsed
pill, then a dismissible Reply action alongside the normal hover actions. Hover never
opens a reply editor or steals focus. Clicking Reply reveals the source excerpt and
guidance field inside one dark surface, separated by a fine divider. Bottom grows up,
top grows down, and sides grow inward while staying vertically centered. The 34 pt
source header has a 28 pt dismiss target; side actions widen to 80 pt while Reply is
available, and the side reply composer is 208 × 287 pt. No copied-content window appears
at rest. §16 of `AGENTS.md` owns lifecycle and capture behavior.

## 10. Asset system and placement

### Approved source assets

| Source | Verified properties | Use | Avoid |
|---|---|---|---|
| [`public/moutain.png`](public/moutain.png) | 1672 × 941 RGB PNG; 1,364,669 bytes. Cyan sky and white snow ridge | Native onboarding illustration stages only | Statistics, reading cards, inputs, overlay, stretching or tiling |
| [`public/gradient.png`](public/gradient.png) | 1672 × 941 RGB PNG; 1,188,987 bytes. Diffuse cyan/blue glow with dot field | Bounded mascot/account/completion illustration stage | Repeated card fills, text fields, controls, animated wallpaper |
| `public/pink.png`, `public/blue.png`, `public/orange.png` | Supplied soft atmospheric artwork | Everyday, Work, and Friends & Social purpose demo stages, respectively | Text surfaces, controls, or the live overlay |
| Existing keycap/mascot catalog assets | Brand tile, template mark, alpha character and sprites | Identity and established teaching moments | Aside logo or a second mascot style |
| Existing Reicon and official app/provider assets | Already integrated | Navigation, controls, recognizable app/provider identity | Generated UI glyphs or text baked into images |

**The actual filename is `moutain.png`**, not `mountain.png` or a `public/mountain/`
directory. Keep the supplied file intact; give its future catalog entry a clear name.
Do not silently rename a user's source asset.

### Release education

What's new uses the existing 780 × 540 pt centered modal footprint, with a quiet header,
264 pt copy column, 24 pt gap, and 436 × 376 pt illustration stage. A fixed footer holds
Back, centered page indicators and a black Next/Done action. Use one to three concise
feature lessons; single-feature releases use one page without page indicators. No preferences sidebar.
The repositioning lesson rehearses dragging inside a miniature desktop with the real
picker’s 64% black scrim and dotted white landing areas. Highlight the nearby destination
and snap on release; do not substitute directional buttons for the drag interaction.

Mountain and glow artwork are also approved for these bounded educational stages.
Pink (`#FBE7F0`, ink `#A03A69`) and orange (`#FFEDDC`, ink `#99501D`) may distinguish
illustration topics; blue retains navigation/focus roles. Use opaque white demo text
surfaces, one image family per stage, and native controls/sample text. These accents
do not become global action colors or change the actual dark overlay. Local interactive
previews never operate on the user's desktop. Reduce Motion removes movement and
Reduce Transparency follows the shared backdrop's solid fallback.

### Crop and compositing rules

- Aspect-fill and clip; never distort. Mountain focal point starts near **(46%, 44%)**
  of source, around the peak. Preserve sky above and let the ridge ground the scene.
- The main sidebar uses the actual desktop behind the window, never the mountain
  asset. Apply the translucent scrim and grain recipe in §4.
- A tall onboarding stage may crop around the peak independently. Place white native
  scene windows over detailed imagery so readable content has a stable background.
- Gradient focal point starts near **(50%, 54%)**. Place the mascot over the glow, keep
  prose outside the stage, and avoid cropping dots into a hard band.
- One image family per onboarding stage. Do not layer glow on mountain or add grain
  to that artwork. The main sidebar has its own subtle cached glass grain (§4).
- Backgrounds neither scroll nor parallax behind writing. They are decorative,
  accessibility-hidden, non-interactive, and have no intrinsic effect on window size.

### Native delivery and sufficiency

`public/` is source artwork, not an automatically served directory in a SwiftUI app.
During implementation, add catalog entries such as `AsideMountain` and `AsideGlow`
under `App/Resources/Assets.xcassets`, with shared bounded background views in
`BrandVisuals.swift`. Verify target resource membership and offline rendering. Cache
decoded imagery and the sidebar grain; no per-frame disk reads or background timers.

The resolution suits atmosphere and modest stages. It is not a full 2× sharp source
for a 1080 × 700 pt hero (at least 2160 × 1400 pixels before crop). Resizing does not
create detail. Check actual stage crops at Retina scale; request/generate larger source
only if sharp large-stage use demonstrates a need. The sidebar does not use these images.

**No new bitmap is required for this specification.** These backgrounds plus existing
mascot, scene, and icon assets cover the roles. Draw controls, shadows, borders, focus,
and mock-window geometry natively. Additional generation needs a specific missing
composition or demonstrated resolution problem, not more decoration.

## 11. Motion, accessibility, and content

The screenshots establish no timing. Proposed light-window timings: 120 ms hover/press
color, 160 ms selection/focus, 180–220 ms modal/page fades. Use opacity and contained
changes, not scenic movement. Selection/save feedback cannot resize rows/windows.
Preserve overlay timing, including its 300 ms hover grace and capture/placement rules.

Reduce Motion uses immediate states or brief opacity transitions, no decorative movement,
and the existing static intro alternative. Reduce Transparency uses §4's solid fills.
Check these preferences together as well as independently.

All three interface languages must preserve meaning and layout. Keep writing-language
behavior, profile semantics, currency handling, and error recovery. Let labels wrap
before reducing type size. Never truncate instructions, choice labels, prices, or the
action that sends text back to another app.

Use concise verbs and useful states: Polish, Save, Continue, Grant access, Copied,
Could not save. Explain recovery without exposing classes, prompt modules, or capture
diagnostics. Permission copy accurately describes the capability. Preserve destructive
confirmations and genuine errors; atmospheric styling must not imply premature success.

## 12. Implementation map and acceptance gate

### Migration sequence

| Area | Implement next | Preserve |
|---|---|---|
| `App/Design/DesignTokens.swift` | Semantic light tokens, SF type, separate action/selection, spacing/radii | Overlay palette, geometry, timing |
| `App/Design/Components.swift` | Black primary actions, white fields/cards, blue focus/selection, complete states | Editing, callbacks, cursor/focus behavior |
| `App/Design/BrandVisuals.swift` and catalog | Approved backgrounds, neutral avatar/icon plates, shared bounded stages | Keycap identity, alpha/sprites, official marks |
| `App/Main/MainWindowView.swift` / controller | Translucent desktop glass, white active row, light panel, typography/detail refinements | Existing layout, sidebar width, page gutters, window sizes, safe areas, close/reopen behavior |
| `HomeView.swift` | Plain stats, coherent callouts/history | Real counts/history, quotas, valid offers/recovery |
| `WritingStyleView.swift` | Neutral previews, blue selection, consistent states | Four profiles, IDs/defaults, persistence/shared editor |
| `AccountView.swift`, `PreferencesSheet.swift`, `PlanView.swift` | Refine existing forms/groups and local-nav surfaces in place | Layout, pane widths, auth/billing/confirmations, destinations/dismissal |
| `App/Onboarding/` | Shared light materials, mountain/glow stages, black forward action | Fixed window size, step IDs/order/progress semantics, intro/practice |
| `App/Overlay/` | Edge-attached generation/results with footer refinement (§9) | Existing font, controls, focus/capture/insertion, history and recovery |

Changing the old `accent` constant alone is insufficient: primary actions, links,
selection, badges, icons, and focus currently share roles that this system separates.
Isolate those roles before replacing values. Shared `Tokens.Font` helpers also need
separation so light-window typography cannot silently restyle the overlay. Replace
stale Willow explanations in touched source comments.

### Visual and behavioral acceptance

- Compare the dashboard before/after: navigation, section order and groupings remain
  familiar; differences should be color, type, local sizing and detail refinement.
- The bar should retain its existing appearance and usability. Any optional font
  change must demonstrate a readability benefit without changing its geometry.
- Compare D/E for hierarchy and B/C for onboarding. Match relationships, not browser
  features or an unknown pixel-to-point scale.
- Capture Home, Buttons, signed-in/out Account, all preferences sections, and
  representative onboarding steps at real native sizes and Retina scale.
- Check 1000 × 700 and minimum 920 × 640 main windows, fixed 1080 × 700 onboarding,
  long localized strings, empty/populated history, wrapped descriptions, and every
  selected/disabled/loading/error state. A build alone is not visual verification.
- Confirm visibly transparent sidebar, white app selection, gray-blue local selection, opaque
  controls, and one clear primary action for each task.
- Measure actual text/control contrast after compositing. Check Increase Contrast,
  Reduce Transparency, Reduce Motion, and the fixed-light app on a dark desktop.
- Verify keyboard traversal, focus, VoiceOver names/selection, editing shortcuts,
  Escape/outside-click dismissal, and focus return. Remeasure glyph alignment in all
  three languages after the font change.
- Verify artwork loads offline from the bundle, never resizes a window, and remains
  sufficiently sharp at the chosen crop and display scale.
- Exercise real pill/hover/composer/generation/result/copy/insert/error states and all
  docking positions after shared-token edits. No background art enters the overlay;
  visual polish is not evidence that cross-app text insertion still works.
- No landing/iOS files, backend contracts, saved choices, entitlement semantics, or
  generated writing behavior change as a side effect of the visual migration.

The end state is one native product with two intentional contexts: a calm light place
to configure and review writing, and a compact dark companion beside the work itself.
