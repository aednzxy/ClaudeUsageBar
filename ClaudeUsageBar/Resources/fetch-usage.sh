#!/bin/bash
# Fetches Claude usage and writes to a cache file
# Run this script once to grant keychain access, then it won't prompt again

CACHE_FILE="$HOME/.claude/usage-cache.json"
CREDS_FILE="$HOME/.claude/.oauth-token"

# Get token from keychain (will prompt once, then remember)
get_token() {
    local creds
    creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -z "$creds" ]; then
        echo "Error: Could not read credentials from keychain" >&2
        return 1
    fi
    echo "$creds" | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null
}

# Fetch usage from API
fetch_usage() {
    local token="$1"
    curl -s \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/2.0.31" \
        "https://api.anthropic.com/api/oauth/usage"
}

# Main
TOKEN=$(get_token)
if [ -z "$TOKEN" ]; then
    echo '{"error": "Could not get token"}' > "$CACHE_FILE"
    exit 1
fi

USAGE=$(fetch_usage "$TOKEN")
if [ -z "$USAGE" ]; then
    echo '{"error": "Could not fetch usage"}' > "$CACHE_FILE"
    exit 1
fi

# Add timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "$USAGE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
data['fetched_at'] = '$TIMESTAMP'
print(json.dumps(data, indent=2))
" > "$CACHE_FILE"

echo "Usage cached to $CACHE_FILE"
