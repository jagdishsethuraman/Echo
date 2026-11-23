# Publishing signed Echo updates

Echo’s public release channel uses Sparkle 2 and GitHub Releases. The stable feed is `https://github.com/jagdishsethuraman/Echo/releases/latest/download/appcast.xml`. Each enclosure points to the version-specific ZIP. Reserve GitHub's “latest release” designation for releases published by this workflow.

## One-time owner setup

1. Use the Apple Developer Program team that will own Echo long term. Ask its Account Holder to create a **Developer ID Application** certificate. For a locally managed certificate, generate a certificate signing request in Keychain Access on your Mac, submit it in Apple Developer → Certificates, and download and install the issued certificate on the same Mac. Under **My Certificates**, expand the certificate to confirm it has a private key. Export the identity to a password-protected `.p12`. Record the team's 10-character Team ID. [Apple certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
2. Set up an Apple Account on the same team with notarization access and create an app-specific password for it. The workflow uses these with Apple's `notarytool`. [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
3. On a trusted Mac, run `swift package resolve` in the repository. Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account Echo` once. Save the printed public key and securely back up the private key. To export the latter for CI, use `generate_keys --account Echo -x /path/to/protected/echo-sparkle-key` from that same bin directory. The exported file already contains the encoded private key required by Sparkle. [Sparkle key setup](https://sparkle-project.org/documentation/)
4. In GitHub **Settings → Environments**, create an environment named **release**. Restrict deployment to trusted release tags, protect who can create matching tags with a repository ruleset, and configure required reviewers where available. Enter the following values in that environment.

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `APPLE_TEAM_ID` | Apple Developer Team ID |
| Variable | `SPARKLE_PUBLIC_KEY` | Public key printed by Sparkle |
| Secret | `DEVELOPER_ID_P12_BASE64` | Base64-encoded binary contents of the exported identity |
| Secret | `DEVELOPER_ID_P12_PASSWORD` | Export password for the identity |
| Secret | `APPLE_ID` | Apple Account email for notarization |
| Secret | `NOTARY_PASSWORD` | App-specific password for that account |
| Secret | `SPARKLE_PRIVATE_KEY` | Contents of the Sparkle private-key export |

For example, from the repository checkout on your trusted Mac, upload the two key files directly to the release environment:

```sh
base64 < /path/to/Echo.p12 | gh secret set DEVELOPER_ID_P12_BASE64 --env release
gh secret set SPARKLE_PRIVATE_KEY --env release < /path/to/protected/echo-sparkle-key
```

Keep the identity, Sparkle key and their backups in secure storage. Enter credentials directly into GitHub, outside source code, issues and PRs.

## Each release

Merge the release code into the default branch and tag that commit with a new stable `vMAJOR.MINOR.PATCH` greater than the current latest release. Push the tag. The tag sets both bundle version fields. The CI build, tests, assembly and speech fixture gate the release job. Approve the release environment deployment if prompted.

The release job builds the Apple Silicon app, signs Sparkle’s helpers and Echo with hardened runtime, sends the app to Apple for notarization, staples the ticket, and verifies it. It then packages the stapled app, signs the archive and appcast, verifies their signatures, and uploads both to a draft release before making it latest. A failed draft can be retried for the same tag. Use a new version for a correction to a published release.

## First upgrade from a local build

Install the first Developer ID release in `/Applications/Echo.app` once. Moving from ad-hoc builds to the team identity can require fresh macOS permission approvals. Future releases keep the bundle ID `com.ragavij.echo`, the same Developer ID team, preferences domain, and Application Support paths. Sparkle replaces the app bundle during relaunch. Keep PR builds separate from the signed installation.

Use **Check for Updates…** from the status menu. During dictation, meeting recording, finalization, or a pending failed transcript write, the updater defers its requested relaunch. Resolve pending saves before installing. Temporary in-memory storage sessions and ad-hoc builds omit the updater.

Before broad rollout, install signed build A, grant microphone and Accessibility access, save a meeting and customize a shortcut. Upgrade to signed build B through the menu. Confirm the meeting, shortcut, speech engine and push-to-talk delivery into TextEdit on the same Mac. This two-release check needs the production identity and a published testable update.
