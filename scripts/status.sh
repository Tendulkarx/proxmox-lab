#!/usr/bin/env bash
# One-screen health check of both Proxmox hosts (make status). Read-only.
# For each host: uptime, every VM with its state and any pending hardware change, the
# `data` disk (VM disks and backups share it), and the last nightly backup job.
set -uo pipefail
KEY=~/.ssh/id_ed25519_homelab

for h in prx1:10.69.20.130 prx2:10.69.20.131; do
  name=${h%%:*}; ip=${h#*:}
  echo "== $name ($ip)"
  ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=5 "root@$ip" 'bash -s' <<'EOF' 2>/dev/null || echo "   not reachable"
up=$(uptime -p | sed "s/^up //")
echo "   up $up; RAM free $(free -g | awk "/^Mem/ {print \$7}") GB of $(free -g | awk "/^Mem/ {print \$2}")"
qm list 2>/dev/null | awk 'NR > 1 {print $1, $2, $3}' | while read -r id vm state; do
  pending=$(qm pending "$id" 2>/dev/null | grep -c "^new")
  note=""; [ "$pending" -gt 0 ] && note="  (hardware change pending: needs a full stop and start)"
  printf "   %-5s %-22s %s%s\n" "$id" "$vm" "$state" "$note"
done
if [ -d /mnt/pve/data ]; then
  df -h /mnt/pve/data | awk 'NR == 2 {printf "   data disk: %s used of %s (%s), %s free\n", $3, $2, $5, $4}'
fi
# The nightly job's task ID has an empty VM field (":vzdump::"); one-off backups name the VM
last=$(grep ":vzdump::" /var/log/pve/tasks/index 2>/dev/null | tail -1)
if [ -n "$last" ]; then
  when=$(date -d "@$((16#$(echo "$last" | cut -d: -f5)))" "+%a %d %b %H:%M" 2>/dev/null)
  result=$(echo "$last" | awk '{ $1 = ""; $2 = ""; print }' | sed 's/^ *//')
  echo "   last nightly backup: $when, result: ${result:-unknown}"
else
  echo "   last nightly backup: none recorded"
fi
EOF
done
