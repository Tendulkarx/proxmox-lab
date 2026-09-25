#!/usr/bin/env bash
# Print "<host ip> <vmid>" for a VM name, by asking both Proxmox hosts. Used by make backup
# and make restart, so nobody has to remember which host or VMID a VM has.
set -uo pipefail
name="${1:?Usage: vm-locate.sh <vm name>}"
for ip in 10.69.20.130 10.69.20.131; do
  id=$(ssh -i ~/.ssh/id_ed25519_homelab -o BatchMode=yes -o ConnectTimeout=5 "root@$ip" \
       "qm list 2>/dev/null | awk -v n='$name' '\$2 == n {print \$1}'" 2>/dev/null)
  [ -n "$id" ] && { echo "$ip $id"; exit 0; }
done
echo "No VM called '$name' on prx1 or prx2" >&2; exit 1
