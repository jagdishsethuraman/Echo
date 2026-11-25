#!/bin/bash
set -euo pipefail

plist=${1:?Provide the app Info.plist}
key=${2:?Provide a Sparkle public key}
plutil -insert SUPublicEDKey -string "$key" "$plist"
plutil -insert SUFeedURL -string 'https://github.com/jagdishsethuraman/Echo/releases/latest/download/appcast.xml' "$plist"
plutil -insert SURequireSignedFeed -bool YES "$plist"
plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$plist"
