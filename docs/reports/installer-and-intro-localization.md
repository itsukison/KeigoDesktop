# Installer and introduction localization

The introductory heading, both supporting sentences, and landing/drag guidance use
Japanese, English and Simplified Chinese through the existing `tr` mechanism. Startup
already activates the saved interface language, or the Mac's preferred supported
language when no choice exists. Landing guidance now wraps to its natural height.
The existing cinematic timing, mascot assets, focus ownership and Reduce Motion
behavior are retained.

The shared Finder installer uses pale cyan, a white icon area, a blue arrow, native
system-font text, and a 2× background. Finder does not dynamically localize background
images: the universal download therefore displays instructions in English and Japanese only.
The volume name is KeigoButton. The app bundle's existing localized names remain
system-controlled. This is bilingual artwork, not automatic DMG language switching. Separate localized
DMGs and language-specific download links could support landing-page language selection.

The Finder window includes 32 pt for its title bar in addition to the 440 pt artwork.
Packaging regenerates the artwork, waits for Finder to save its layout, and fails if
window, icon-view or icon-position records are missing. Do not leave a previous
KeigoButton preview volume mounted while building another; Finder can confuse volumes
with identical names. The persistence guard caught this during verification.

KeigoAppIcon and KeigoAppMark remain the selected blue identity. The legacy AppIcon
and icon-brand assets are now blue aliases, regenerated from the same source by
prepare-app-icon.swift. Historical source artwork outside the bundle is retained.

## Verification

- Debug Xcode build succeeded, signing disabled.
- 11 OnboardingIntroTests and 16 LocalizationTests passed.
- Native text renders covered both intro sentences in all three languages at
  1280×800, 1440×900 and 1920×1080. This offscreen harness verifies copy layout;
  it does not establish live movie playback or the cross-window animation handoff.
- All 12 legacy icon raster files match the corresponding blue assets byte for byte.
- The local DMG built successfully with the Finder persistence guard.
- Shell syntax and git whitespace checks passed.

The generated DMG is a local unsigned Debug preview, not a notarized release.
No production release, account changes, or iOS/website changes were made.
