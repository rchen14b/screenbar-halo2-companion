#!/bin/bash
# Launch the installed app once with the bridge's API encryption key taken from an ESPHome secrets
# file (the key the bridge was built with); the app stores it in its Keychain item. The same can be
# entered by hand in Settings.
#   scripts/import-credentials.sh path/to/secrets.yaml [host]   # key name: api_encryption_key
set -euo pipefail

SECRETS="${1:?usage: $0 path/to/secrets.yaml [host]}"
HOST="${2:-screenbar-halo2.local}"
key=$(sed -n 's/^api_encryption_key: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$SECRETS")
[[ -n "$key" ]] || { echo "api_encryption_key missing in $SECRETS" >&2; exit 1; }

pkill -x ScreenBarMenu 2>/dev/null || true
open --env "SCREENBAR_HOST=$HOST" --env "SCREENBAR_KEY=$key" "$HOME/Applications/ScreenBar.app"
echo "Launched ScreenBar for $HOST with the API key from $SECRETS"
