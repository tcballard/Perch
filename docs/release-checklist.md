# Perch release checklist

Perch is distributed directly as a Developer ID-signed and Apple-notarized ZIP.
The release process never publishes, tags, or updates Homebrew automatically.

## One-time Apple setup

In Certificates, Identifiers & Profiles, confirm:

- App ID `com.tcballard.perch` exists.
- App ID `com.tcballard.perch.widget` exists.
- App Group `R8HXTBY3NM.com.tcballard.perch` exists.
- Both App IDs have the App Group capability and are assigned to that group.
- Xcode can create or download the required Developer ID provisioning profiles.
- `Developer ID Application: Thomas Ballard (R8HXTBY3NM)` is present in the
  login Keychain with its private key.

Store notarization credentials in Keychain. Use an app-specific password, not
the Apple Account password:

```sh
xcrun notarytool store-credentials "PerchNotary" \
  --apple-id "tom@armytage.co" \
  --team-id "R8HXTBY3NM" \
  --password "APP-SPECIFIC-PASSWORD"
```

Never put the password or a notary API private key in the repository.

## Release-candidate gates

- [ ] `main` is clean and matches `origin/main`.
- [ ] Version and build number match in the host app and widget extension.
- [ ] Full native XCTest suite executes successfully.
- [ ] Provider-state Python probes pass.
- [ ] Codex working, input, permission, response, completion/abort, and focus
      transitions pass on the documented supported version.
- [ ] Claude working, question, response, interruption, permission, and honest
      focus-unavailable presentation pass on the documented supported version.
- [ ] Waiting appears within approximately three seconds and clears promptly.
- [ ] Ambiguous or failed evidence never remains urgent.
- [ ] Small, Medium, Large, and Extra Large widgets are inspected in Widget
      Gallery.
- [ ] Light mode, Dark mode, Increase Contrast, Reduce Motion, full keyboard
      traversal, and VoiceOver hierarchy/action labels pass.
- [ ] A normal run opens no network connection and records no session content.

## Prepare without notarizing

Use this to validate archive, automatic Developer ID export, Hardened Runtime,
secure timestamps, nested signatures, and release entitlements:

```sh
./script/release.sh --version 0.1.0 --build 8 --prepare-only
```

The resulting `*-notary-upload.zip` is explicitly not a release artifact.

## Build the notarized release

```sh
./script/release.sh \
  --version 0.1.0 \
  --build 8 \
  --notary-profile PerchNotary
```

The script archives the Release configuration, exports with Developer ID,
checks Hardened Runtime and release entitlements, submits with `notarytool`,
staples the ticket, verifies Gatekeeper, recreates and extracts the final ZIP,
and writes its SHA-256 checksum.

Expected outputs:

```text
dist/Perch-0.1.0.zip
dist/Perch-0.1.0.sha256
```

Do not publish if notarization, stapling, extracted-ZIP verification, or any
release-candidate gate fails.

## GitHub release

After owner approval:

1. Tag the exact verified commit as `v0.1.0`.
2. Create a draft GitHub release for that tag.
3. Attach the ZIP and checksum.
4. Document macOS 14+ and Apple Silicon requirements, validated provider
   versions, local/read-only privacy behavior, and known focus limitations.
5. Download the draft assets on a clean account or second Mac and repeat
   Gatekeeper and launch checks.
6. Publish only after the owner explicitly approves the final release.

Homebrew Cask is a follow-up distribution channel. It must reference the
immutable published ZIP URL and exact checksum rather than rebuilding Perch.
