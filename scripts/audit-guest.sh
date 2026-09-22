#!/usr/bin/env bash
# audit-guest.sh: READ-ONLY health report for a Linux VM. Changes nothing.
# Run by `make audit-vms` (Ansible copies it, runs it with sudo, fetches the output).
# Secrets are not printed: env vars, .env files and container env are never read.
set -uo pipefail
sec() { printf '\n########## %s\n' "$*"; }
run() { printf '\n$ %s\n' "$*"; timeout 60 bash -c "$*" 2>&1; }

sec "System"
run "hostnamectl | grep -E 'hostname|Operating|Kernel|Virtualization'; uptime; timedatectl | grep -E 'Time zone|synchronized'"
run "nproc; free -h; swapon --show"
run "cat /proc/pressure/memory /proc/pressure/cpu /proc/pressure/io 2>/dev/null"
run "[ -f /var/run/reboot-required ] && { echo 'REBOOT REQUIRED'; cat /var/run/reboot-required.pkgs 2>/dev/null; } || echo 'no reboot required'"

sec "Disk"
run "df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs"
run "df -i / | tail -1"
run "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT"
run "vgs 2>/dev/null; lvs 2>/dev/null"
run "du -xh --max-depth=2 /var 2>/dev/null | sort -rh | head -12"
run "journalctl --disk-usage"
run "systemctl is-enabled fstrim.timer; systemctl is-active fstrim.timer"

sec "Updates"
run "apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c '^Inst' | sed 's/^/pending upgrades: /'"
run "apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep '^Inst' | grep -ci security | sed 's/^/of which security: /'"
run "cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; systemctl is-active unattended-upgrades"
run "tail -5 /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null"
run "dpkg -l 'linux-image-*' | awk '/^ii/{print \$2, \$3}'"
run "dpkg --audit"

sec "Services"
run "systemctl --failed --no-legend"
run "systemctl is-active qemu-guest-agent ssh docker 2>/dev/null | paste - - -"
run "ss -tulpnH | awk '{print \$1, \$5, \$7}' | sort -u"
run "ufw status 2>/dev/null | head -20"
run "systemctl is-active fail2ban 2>/dev/null && fail2ban-client status 2>/dev/null | tail -2"
run "grep -hE '^(PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null"
run "last -n 5 -w 2>/dev/null | head -6"

sec "Docker"
if command -v docker >/dev/null; then
  run "docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}'"
  run "docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.RunningFor}}'"
  run "docker ps -a --filter 'status=exited' --filter 'status=restarting' --filter 'status=dead' --format '{{.Names}} {{.Status}}'"
  run "docker inspect --format '{{.Name}} restarts={{.RestartCount}} policy={{.HostConfig.RestartPolicy.Name}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \$(docker ps -aq) 2>/dev/null"
  run "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'"
  run "docker system df"
  run "docker images --format '{{.Repository}}:{{.Tag}} {{.Size}} {{.CreatedSince}}' | sort"
  run "docker volume ls -qf dangling=true | wc -l | sed 's/^/dangling volumes: /'"
  run "cat /etc/docker/daemon.json 2>/dev/null || echo 'no daemon.json (container logs never rotate)'"
  run "find /var/lib/docker/containers -name '*-json.log' -size +100M -printf '%s %p\n' 2>/dev/null | sort -rn | head -5 | awk '{printf \"%.0f MB %s\n\", \$1/1048576, \$2}'"
  run "ls /opt/docker 2>/dev/null; for d in /opt/docker/*/; do [ -f \"\$d/docker-compose.yml\" ] || [ -f \"\$d/compose.yaml\" ] || [ -f \"\$d/compose.yml\" ] && echo \"compose: \$d\"; done"
  run "for d in /opt/docker/*/; do [ -d \"\$d/.git\" ] && echo \"git: \$d\"; done; git -C /opt/docker status --short 2>/dev/null | head -20"
  run "docker logs --since 24h 2>&1 \$(docker ps -q | head -0) >/dev/null; for c in \$(docker ps --format '{{.Names}}'); do n=\$(docker logs --since 24h \$c 2>&1 | grep -ciE 'error|fatal|panic'); [ \"\$n\" -gt 0 ] && echo \"\$c: \$n error lines in 24h\"; done"
else
  echo "docker not installed"
fi

sec "Backups inside the guest"
run "ls -la /opt/docker/*/backup* /opt/backups /var/backups/*.gz 2>/dev/null | head -20"
run "crontab -l -u turbx 2>/dev/null; crontab -l 2>/dev/null; ls /etc/cron.d/"
run "systemctl list-timers --no-pager | head -20"

sec "Recent errors (journal, 24h, priority err)"
run "journalctl -p err --since '24 hours ago' --no-pager | tail -25"
