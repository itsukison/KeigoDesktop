# macOS releases and updates

The first public build must already contain Sparkle's public EdDSA key. Existing
installations use that key to authenticate every later update archive; shipping an
empty or temporary key creates a manual-update break in the chain.

Current release status (2026-08-09):

- The password-protected Developer ID `.p12` remains outside the repository and its
  identity is imported. `security find-identity` confirms `Developer ID Application`
  for team `4KS6YS23KT`.
- The App Store Connect Team API key authenticates successfully with `notarytool`.
- The permanent app-specific Sparkle Ed25519 key is stored in the login Keychain.
- GitHub environments `production` and `github-pages` are restricted to `main`; Pages
  uses GitHub Actions, workflow permissions are write-enabled, and all required
  production secrets plus `SPARKLE_PUBLIC_ED_KEY` are configured.
- Workflow run `31295352067` published `v0.1.0` successfully. The app and DMG were
  notarized and stapled, the public DMG passed Gatekeeper as `Notarized Developer ID`,
  its downloaded SHA-256 matched GitHub's asset digest, and the live Pages appcast is
  valid and carries the signed `0.1.0` enclosure.
- The remaining proof is installing that public DMG and completing the two-version
  Sparkle test below.

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
