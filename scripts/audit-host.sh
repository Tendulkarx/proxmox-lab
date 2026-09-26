#!/usr/bin/env bash
# audit-host.sh: READ-ONLY health and configuration report for a Proxmox VE host.
# Changes nothing. Writes /root/pve-audit-<hostname>.txt and prints its path.
#
#   scp scripts/audit-host.sh root@10.69.20.130:/root/ && ssh root@10.69.20.130 bash /root/audit-host.sh
#   scp root@10.69.20.130:/root/pve-audit-prx-server-1.txt audit/
#
# Secrets are stripped: cloud-init passwords, SSH keys and token values are not printed.

set -uo pipefail
OUT="/root/pve-audit-$(hostname).txt"
exec > >(tee "$OUT") 2>&1

sec() { printf '\n########## %s\n' "$*"; }
run() { printf '\n$ %s\n' "$*"; bash -c "$*" 2>&1 | sed -E 's/(cipassword|sshkeys|password|secret|token)[:=].*/\1: <redacted>/I'; }

sec "Host"
run "date -Is; hostname -f; pveversion -v | head -20; uptime"
run "lscpu | grep -E 'Model name|^CPU\\(s\\)|Thread|Virtualization'"
run "free -h; swapon --show"
run "cat /proc/cmdline"
run "dmesg 2>/dev/null | grep -iE 'DMAR|IOMMU|AMD-Vi' | head -5"

sec "Repositories and updates"
run "cat /etc/apt/sources.list 2>/dev/null; ls /etc/apt/sources.list.d/; cat /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list 2>/dev/null | grep -vE '^\\s*#|^\\s*$'"
run "apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c '^Inst' | sed 's/^/pending upgrades: /'"
run "proxmox-boot-tool kernel list 2>/dev/null; dpkg -l 'proxmox-kernel-*' 'pve-kernel-*' 2>/dev/null | awk '/^ii/{print \$2}'"
run "pvesubscription get 2>/dev/null | grep -E 'status|level'"

sec "Storage"
run "pvesm status"
run "cat /etc/pve/storage.cfg"
run "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA"
run "df -hT -x tmpfs -x devtmpfs"
run "zpool status 2>/dev/null || echo 'no ZFS'"
run "lvs 2>/dev/null"
run "for d in \$(lsblk -dno NAME -e7,11); do echo \"== /dev/\$d\"; smartctl -H -A /dev/\$d 2>/dev/null | grep -E 'overall-health|result|Reallocated_Sector|Wear_Leveling|Percentage Used|Media_Wearout|Power_On_Hours|Temperature_Celsius|Critical Warning' ; done; command -v smartctl >/dev/null || echo 'smartctl not installed'"
run "systemctl is-enabled fstrim.timer; systemctl is-active smartmontools 2>/dev/null"

sec "Network"
run "cat /etc/network/interfaces"
run "ip -br addr; ip route"
run "cat /etc/resolv.conf; cat /etc/hosts | grep -v '^#'"
run "timedatectl | grep -E 'Time zone|synchronized|NTP'; chronyc tracking 2>/dev/null | head -4"

sec "Datacenter options (tags, colours, console, keyboard, email)"
run "cat /etc/pve/datacenter.cfg 2>/dev/null || echo '(empty)'"
run "pvesh get /cluster/options --output-format json-pretty 2>/dev/null"

sec "Guests"
run "qm list; pct list"
for id in $(qm list | awk 'NR>1{print $1}'); do
  run "echo '--- VM $id'; qm config $id | grep -vE '^(cipassword|sshkeys|smbios1|vmgenid|meta)'"
  run "qm listsnapshot $id"
  run "qm agent $id ping >/dev/null 2>&1 && echo 'guest agent: responding' || echo 'guest agent: NOT responding'"
done
for id in $(pct list 2>/dev/null | awk 'NR>1{print $1}'); do
  run "echo '--- CT $id'; pct config $id"
done

sec "Backups"
run "cat /etc/pve/jobs.cfg 2>/dev/null || echo 'no backup jobs defined'"
run "cat /etc/vzdump.conf | grep -v '^#'"
run "for s in \$(pvesm status --content backup 2>/dev/null | awk 'NR>1{print \$1}'); do echo \"== \$s\"; pvesm list \$s --content backup 2>/dev/null | tail -n +2 | awk '{print \$1, \$4}' | tail -10; done"
run "systemctl list-timers pve-backup-copy.timer --no-pager 2>/dev/null | head -2; journalctl -u pve-backup-copy.service -n 3 --no-pager -o short 2>/dev/null || echo 'no backup copy on this host'"

sec "Access and security"
run "pveum user list --output-format json | python3 -c 'import sys,json;[print(u[\"userid\"], \"enabled=\"+str(u.get(\"enable\",1)), \"tfa=\"+str(bool(u.get(\"keys\") or u.get(\"tfa-locked-until\") is not None))) for u in json.load(sys.stdin)]'"
run "pveum acl list"
run "cat /etc/pve/priv/tfa.cfg >/dev/null 2>&1 && python3 -c 'import json;d=json.load(open(\"/etc/pve/priv/tfa.cfg\"));print(\"users with TFA:\", list(d.get(\"users\",{}).keys()))' 2>/dev/null"
run "pve-firewall status; cat /etc/pve/firewall/cluster.fw 2>/dev/null | head -20"
run "grep -E '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null"
run "openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -subject -issuer -enddate"
run "systemctl --failed --no-legend"

sec "Notifications"
run "cat /etc/pve/notifications.cfg 2>/dev/null || echo 'none'"

sec "Recent errors (journal, last 24h, priority err)"
run "journalctl -p err --since '24 hours ago' --no-pager | tail -30"

echo; echo "Report written to $OUT"
