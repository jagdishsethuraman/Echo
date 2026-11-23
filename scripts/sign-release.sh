#!/bin/bash
# Run on an ephemeral macOS GitHub-hosted runner.
set -euo pipefail
umask 077
: "${DEVELOPER_ID_P12_BASE64:?}" "${DEVELOPER_ID_P12_PASSWORD:?}" "${APPLE_TEAM_ID:?}" "${RUNNER_TEMP:?}"
workdir=$(mktemp -d "$RUNNER_TEMP/echo-sign.XXXXXX")
keychain="$workdir/signing.keychain-db"
password=$(openssl rand -hex 32)
original=()
while IFS= read -r line; do
    original+=("$(echo "$line" | sed 's/^ *"//; s/"$//')")
done < <(security list-keychains -d user)
cleanup() {
    security list-keychains -d user -s "${original[@]}"
    security delete-keychain "$keychain" || true
    rm -rf "$workdir"
}
trap cleanup EXIT
security create-keychain -p "$password" "$keychain"
security unlock-keychain -p "$password" "$keychain"
security list-keychains -d user -s "$keychain" "${original[@]}"
printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 -D > "$workdir/identity.p12"
security import "$workdir/identity.p12" -k "$keychain" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -k "$password" "$keychain" >/dev/null
ECHO_SIGN_IDENTITY=$(security find-identity -v -p codesigning "$keychain" |
    awk -v team="($APPLE_TEAM_ID)\"" '/Developer ID Application:/ && $NF == team {print $2}')
[[ "$ECHO_SIGN_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] || { echo "Expected one Developer ID Application identity for the configured team" >&2; exit 1; }
export ECHO_SIGN_IDENTITY
./assemble_app.sh
