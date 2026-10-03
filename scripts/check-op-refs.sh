#!/usr/bin/env bash
# Checks that every 1Password reference in proxmox-lab and homelab-apps still resolves, so a
# renamed or moved item shows up here before a rebuild needs it. Prints OK or MISSING per
# reference; values are read into /dev/null and never shown. One Touch ID prompt.
#   scripts/check-op-refs.sh            (or: make check-secrets)
# HOMELAB_APPS overrides where homelab-apps is cloned (default: next to this repo).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
apps=${HOMELAB_APPS:-$root/../homelab-apps}

# Literal references in both repos. decisions.md keeps old names on purpose, so it is skipped;
# placeholders such as op://Development/<app>/... do not match the pattern.
refs=$(grep -rhoE "op://[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+" "$root" "$apps" \
  --exclude-dir=.git --exclude-dir=.terraform --exclude-dir=audit --exclude=decisions.md | sort -u)

# The off-site script builds its references from variables, so list its fields here.
offsite=$apps/backups/setup-offsite.sh
if [ -f "$offsite" ]; then
  vault=$(sed -n 's/^VAULT=//p' "$offsite"); item=$(sed -n 's/^ITEM=//p' "$offsite")
  for f in drive_token crypt_password crypt_salt; do refs+=$'\n'"op://$vault/$item/$f"; done
fi

ok=0 missing=0
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if op read "$ref" >/dev/null 2>&1; then
    ok=$((ok + 1)); echo "OK       $ref"
  else
    missing=$((missing + 1)); echo "MISSING  $ref"
  fi
done <<< "$refs"
echo "$ok OK, $missing missing"
[ "$missing" -eq 0 ]
