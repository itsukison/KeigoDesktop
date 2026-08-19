# macOS releases and updates

The first public build must already contain Sparkle's public EdDSA key. Existing
installations use that key to authenticate every later update archive; shipping an
empty or temporary key creates a manual-update break in the chain.

Current release status (2026-08-10):

- **`v0.1.4` is published and is `latest`.** Workflow run `31364148576` succeeded in
  both jobs from commit `f3a842a`. The public
  `/releases/latest/download/KeigoButton.dmg` downloads with SHA-256
  `496b1a2df694b0849c2d2c717849feabb603e7a37867589f2a8383fd853c31e8`, matching
  GitHub's asset digest and 8,600,644-byte asset; `hdiutil verify` and
  `stapler validate` pass, and Gatekeeper reports `Notarized Developer ID`. The mounted
  app passes strict deep code-signature verification, reports version 0.1.4/build 9,
  and sits beside the expected Applications link. The live Pages appcast is valid XML
  with five items and 0.1.4 newest — `sparkle:version` 9, the Japanese release notes,
  and a signed enclosure whose 8,399,451-byte length and SHA-256
  `e06289c982c459433e08a9631776476e872160b43934539d3e160c6e3a60c16f` match the
  released `KeigoButton-0.1.4.zip` exactly.
- **The first real scheduled announcement and install-chain proof is 0.1.4 → 0.1.5.**
  Versions through 0.1.3 did not contain the visible pending-update surfaces, so they
  need a manual update or fresh DMG to reach 0.1.4. Installing this public DMG and then
  completing the two-version Sparkle test below once 0.1.5 exists remain unverified.

Previous release status (2026-08-09):

- The password-protected Developer ID `.p12` remains outside the repository and its
  identity is imported. `security find-identity` confirms `Developer ID Application`
  for team `4KS6YS23KT`.
- The App Store Connect Team API key authenticates successfully with `notarytool`.
- The permanent app-specific Sparkle Ed25519 key is stored in the login Keychain.
- GitHub environments `production` and `github-pages` are restricted to `main`; Pages
  uses GitHub Actions, workflow permissions are write-enabled, and all required
  production secrets plus `SPARKLE_PUBLIC_ED_KEY` are configured.
- Replacement workflow run `31297160268` published `v0.1.0` successfully before public
  announcement. `KeigoButton.app` and the Willow-styled `KeigoButton.dmg` were notarized
  and stapled; the public DMG passed Gatekeeper as `Notarized Developer ID`, its
  downloaded SHA-256 matched GitHub's asset digest, and its mounted contents include the
  saved Finder layout plus the Applications link. The live Pages appcast is valid and
  carries the signed `KeigoButton-0.1.0.zip` enclosure.
- The original 0.1.0 artifact remains verified as recorded above; current install-chain
  testing is tracked in the current-release section.

## One-time setup

1. Create GitHub environments named `production` and `github-pages`. Restrict the
   production environment to `main` and require approval before secrets are released.
2. Enable GitHub Pages with **GitHub Actions** as its source.
3. Import the Developer ID `.p12` locally and verify that this prints a valid
   `Developer ID Application` identity for team `4KS6YS23KT`:

   ```sh
   security find-identity -v -p codesigning
   ```

4. Generate one Sparkle Ed25519 keypair with Sparkle's `generate_keys`. Keep the
   private key in two secure backups. Put the printed public key in the production
   environment variable `SPARKLE_PUBLIC_ED_KEY`.
5. Base64-encode the private Sparkle key, Developer ID `.p12`, and App Store Connect
   API `.p8` without adding line breaks. Configure these production secrets:

   - `CERTIFICATE_P12_BASE64`
   - `CERTIFICATE_P12_PASSWORD`
   - `APP_STORE_CONNECT_KEY_BASE64`
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `SPARKLE_PRIVATE_ED_KEY_BASE64`

The Apple Developer ID key and Sparkle EdDSA key are different trust systems. The
workflow requires both. A `.p12` is a signing identity; notarization is an Apple scan
and ticket issued separately for every released build.

## Publishing

1. Add user-facing notes at `docs/releases/X.Y.Z.md`. The workflow supplies a minimal
   fallback, but production releases should have real notes.
2. Merge and push the exact release commit to `main`. GitHub cannot build uncommitted
   files from a developer Mac.
3. Run **Release macOS** with version `X.Y.Z` and approve the production environment.
4. The workflow tests, archives, Developer ID signs, notarizes and staples the app and
   DMG, signs the update ZIP with Sparkle, creates `vX.Y.Z`, uploads the GitHub release,
   and deploys `appcast.xml` to GitHub Pages.

The public installer is always named `KeigoButton.dmg`, so the website can use the
stable `/releases/latest/download/KeigoButton.dmg` URL. Sparkle update archives remain
versioned as `KeigoButton-X.Y.Z.zip`.

`CFBundleVersion` uses GitHub's monotonically increasing workflow run number. Sparkle
uses that build number for comparisons; the `X.Y.Z` value is the user-facing version.

## Required first-release test

Before advertising the download link, publish two throwaway versions from the same
signing identities and prove the entire chain:

1. Install the older DMG into `/Applications` on a clean macOS account.
2. Grant Accessibility and complete onboarding.
3. Publish the newer version and use `アップデートを確認…`.
4. Confirm the standard Sparkle prompt, release notes, download, replacement, relaunch,
   new version number, and preserved Accessibility permission.
5. Repeat once with the app offline and once while a rewrite/result is active. Scheduled
   checks must wait until the overlay returns to its resting pill.

Do not publish the appcast before its GitHub release assets are public. The workflow
orders them deliberately: release first, appcast deployment second.
