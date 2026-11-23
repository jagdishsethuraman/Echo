#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build --disable-keychain -c release
product=$(swift build -c release --show-bin-path)
stage=$(mktemp -d .build/assembly.XXXXXX)
trap 'rm -rf "$stage"' EXIT
app="$stage/Echo.app"
contents="$app/Contents"
mkdir -p "$contents"/{MacOS,Resources,Frameworks}
cp "$product/Echo" "$contents/MacOS/"
cp Info.plist "$contents/"
cp AppIcon.icns "$contents/Resources/"
ditto "$product/Sparkle.framework" "$contents/Frameworks/Sparkle.framework"

if [[ -n "${ECHO_RELEASE_VERSION:-}" ]]; then
    : "${ECHO_SIGN_IDENTITY:?}" "${SPARKLE_PUBLIC_KEY:?}"
    plist="$contents/Info.plist"
    plutil -replace CFBundleShortVersionString -string "$ECHO_RELEASE_VERSION" "$plist"
    plutil -replace CFBundleVersion -string "$ECHO_RELEASE_VERSION" "$plist"
    plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$plist"
    plutil -insert SUFeedURL -string 'https://github.com/jagdishsethuraman/Echo/releases/latest/download/appcast.xml' "$plist"
    plutil -insert SURequireSignedFeed -bool YES "$plist"
    framework="$contents/Frameworks/Sparkle.framework"
    nested="$framework/Versions/B"
    sign=(codesign --force --timestamp --options runtime --sign "$ECHO_SIGN_IDENTITY")
    for helper in "$nested"/XPCServices/*.xpc "$nested/Autoupdate" "$nested/Updater.app"; do
        "${sign[@]}" --preserve-metadata=entitlements "$helper"
    done
    "${sign[@]}" "$framework"
    "${sign[@]}" --entitlements scripts/Echo.entitlements "$app"
else
    codesign --force --sign - --identifier com.ragavij.echo "$app"
fi

codesign --verify --deep --strict --verbose=2 "$app"
"$contents/MacOS/Echo" --test
if [[ -e Echo.app ]]; then mv Echo.app "$stage/previous.app"; fi
mv "$app" Echo.app
echo "Assembled and verified Echo.app"
