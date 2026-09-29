#!/usr/bin/env bash
# Connect prx1 to the Proxmox Backup Server on prx2 (docs/lab-rebuild-plan.md phase 2).
# Run from the Mac after `make hosts` has installed the server:
#
#     scripts/pbs-connect.sh
#
# 1. On prx2: an API token for backup@pbs (named prx1), allowed to back up to datastore `main`
#    and nothing else.
# 2. On prx1: storage `pbs` pointing at it, pinned to the server's certificate fingerprint.
#
# The token secret is shown by the server once; it goes from prx2 to prx1 over SSH stdin and is
# never printed, logged or saved anywhere else. If it is ever lost, run this again with
# --rotate to replace the token. The nightly job is not switched here (a separate, previewed step).
set -euo pipefail

PBS_HOST=prx2
PBS_IP=10.69.20.131
PVE_HOST=prx1
DATASTORE=main
USER_ID=backup@pbs
TOKEN_NAME=prx1
TOKEN_ID="$USER_ID!$TOKEN_NAME"
STORAGE=pbs

remote() { ssh -o BatchMode=yes "$@"; }

if remote "$PVE_HOST" "pvesm status --storage $STORAGE >/dev/null 2>&1" && [ "${1:-}" != "--rotate" ]; then
  echo "prx1 already has storage '$STORAGE'. Nothing to do (use --rotate to replace the token)."
  exit 0
fi

has_token=$(remote "$PBS_HOST" "proxmox-backup-manager user list-tokens '$USER_ID' --output-format json" |
  python3 -c "import json,sys; print(any(t['tokenid'] == '$TOKEN_ID' for t in json.load(sys.stdin)))")
if [ "$has_token" = True ]; then
  [ "${1:-}" = "--rotate" ] || { echo "Token $TOKEN_ID exists but prx1 has no storage: run with --rotate."; exit 1; }
  remote "$PBS_HOST" "proxmox-backup-manager user delete-token '$USER_ID' '$TOKEN_NAME'"
  echo "Old token removed."
fi

# The command prints the new token as JSON-like text; take the "value" field and nothing else.
# If that fails, remove the half-made token rather than print anything.
secret=$(remote "$PBS_HOST" "proxmox-backup-manager user generate-token '$USER_ID' '$TOKEN_NAME'" |
  python3 -c 'import re,sys; m = re.search(r"\"value\"\s*:\s*\"([^\"]+)\"", sys.stdin.read()); print(m.group(1) if m else "")')
if [ -z "$secret" ]; then
  remote "$PBS_HOST" "proxmox-backup-manager user delete-token '$USER_ID' '$TOKEN_NAME'" || true
  echo "Could not read the new token's secret (not shown); token removed. Nothing changed on prx1."
  exit 1
fi
remote "$PBS_HOST" "proxmox-backup-manager acl update /datastore/$DATASTORE DatastoreBackup --auth-id '$TOKEN_ID'"
echo "Token $TOKEN_ID made; it may back up to datastore $DATASTORE only."

fingerprint=$(remote "$PBS_HOST" "proxmox-backup-manager cert info" | awk '/Fingerprint/ {print $NF}')
[ -n "$fingerprint" ] || { echo "Could not read the server's fingerprint."; exit 1; }

# Retention is the Backup Server's prune job (7 daily, 4 weekly, 3 monthly); keep-all here stops
# Proxmox VE pruning on top of it.
printf '%s\n' "$secret" | remote "$PVE_HOST" "read -r pw
  if pvesm status --storage $STORAGE >/dev/null 2>&1; then
    pvesm set $STORAGE --password \"\$pw\" --fingerprint '$fingerprint'
  else
    pvesm add pbs $STORAGE --server $PBS_IP --datastore $DATASTORE --username '$TOKEN_ID' \
      --password \"\$pw\" --fingerprint '$fingerprint' --content backup --prune-backups keep-all=1
  fi"
unset secret
echo "prx1 storage '$STORAGE' points at $PBS_IP datastore $DATASTORE."
remote "$PVE_HOST" "pvesm status --storage $STORAGE"
