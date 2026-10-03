# Dashboard sidebar transparency

The sidebar uses a 78% opaque pale scrim over a clear, nonopaque main window, with
4.5% static grain. This matches the alpha-compositing mechanism of the onboarding intro's
dimming layer. The desktop remains directly visible through the sidebar; this version
does not blur it. The previous native `.sidebar` material passed a color-response check
but washed out background detail enough to look opaque to the user. Recognizable
background structure, not merely a color shift, is now the visual acceptance criterion.

The translucent background extends behind the traffic lights and exposed shell margins.
The content pane, selected navigation row, labels, and controls remain opaque.
Reduce Transparency and Increase Contrast use a solid neutral fallback.

Verification:

- Native Debug build succeeds with code signing disabled; `git diff --check` passes.
- A temporary native harness uses the production backdrop and tokens in a matching
  window shell. Real windows behind it contain alternating light/dark rounded blocks
  and large shapes. These remain visibly recognizable through the sidebar on blue,
  warm, and dark backgrounds, while the workspace hides them completely.
- The harness exercises the solid fallback branches and the 920 × 640 minimum size.
- Sampled sidebar backgrounds give minimum label contrast of about 7.0:1 on blue,
  7.0:1 on warm, 6.4:1 on dark, and 11.3:1 on the solid fallback. These measurements
  apply to the controlled fixtures, not every possible desktop.
- Harness and captures: `/private/tmp/sidebar-glass-check/`. These are simplified
  shell checks, not complete dashboard screenshots. Accessibility branches were
  injected in the harness; system settings were not changed.

The running Xcode debug session was not restarted. Re-run from Xcode to see the new
source. The full signed-in dashboard and cross-app writing workflow were not rerun;
onboarding and overlay behavior were not changed.
