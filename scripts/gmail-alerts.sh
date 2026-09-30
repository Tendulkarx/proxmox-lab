#!/usr/bin/env bash
# Alerts by email through Gmail (decision 67), run once from the Mac (Touch ID for 1Password):
#
#     scripts/gmail-alerts.sh            set up (once)
#     scripts/gmail-alerts.sh --update   after rotating the Gmail app password in 1Password:
#                                        push the new one to all four places, send test emails
#
# 1. Proxmox VE on prx1 and prx2 and the Backup Server: target `gmail`, warnings and errors
#    only (ansible roles pve_host and pbs, tag alerts).
# 2. Uptime Kuma on prdsrv3: notification "Gmail", default for new monitors and switched on for
#    every existing one (it had none). Uptime Kuma stops for a few seconds while it is added.
# 3. A test email from each Proxmox target.
#
# Alerts go to <user>+homelab@gmail.com, so one Gmail filter labels them all.
# The login is the Gmail app password property-search uses. It goes from 1Password to the
# servers over SSH and is never printed or saved on the Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=${1:-}
USER_REF=op://property-search-prod/app/EMAIL_USERNAME
PASS_REF=op://property-search-prod/app/EMAIL_PASSWORD
KEY=~/.ssh/id_ed25519_homelab

echo "== Proxmox hosts and Backup Server"
if [ "$MODE" = --update ]; then
  # The password goes over SSH stdin, never on this Mac's command line.
  op read "$PASS_REF" | ssh -i "$KEY" root@10.69.20.130 'read -r p; pvesh set /cluster/notifications/endpoints/smtp/gmail --password "$p" && echo "prx1 updated"'
  op read "$PASS_REF" | ssh -i "$KEY" root@10.69.20.131 'read -r p; pvesh set /cluster/notifications/endpoints/smtp/gmail --password "$p" && echo "prx2 updated";
    proxmox-backup-manager notification endpoint smtp update gmail --password "$p" && echo "Backup Server updated"'
else
  out=$(make hosts ARGS="--tags alerts" </dev/null 2>&1) || { echo "$out" | tail -30; exit 1; }
  echo "$out" | grep -A3 'PLAY RECAP'
fi

echo "== Uptime Kuma"
# Python reads the two lines from stdin; it has no single quotes, so it can sit inside '...'.
kuma_py='
import json, sqlite3, sys
user, pw = sys.stdin.read().split("\n")[:2]
to = user.split("@")[0] + "+homelab@" + user.split("@")[1]  # pve_alert_tag in pve_host
db = sqlite3.connect("/opt/docker/uptime-kuma/data/kuma.db")
row = db.execute("select id, config from notification where name = \"Gmail\"").fetchone()
if row:
    cfg = json.loads(row[1])
    cfg.update(smtpUsername=user, smtpPassword=pw, smtpTo=to)
    db.execute("update notification set config = ? where id = ?", (json.dumps(cfg), row[0]))
    db.commit()
    print("Gmail notification updated")
    sys.exit(0)
cfg = {"name": "Gmail", "type": "smtp", "isDefault": True, "applyExisting": True,
       "smtpHost": "smtp.gmail.com", "smtpPort": 587, "smtpSecure": False,
       "smtpIgnoreTLSError": False, "smtpUsername": user, "smtpPassword": pw,
       "smtpFrom": "Uptime Kuma <" + user + ">", "smtpTo": to}
cur = db.execute("insert into notification (name, config, active, user_id, is_default) values (?, ?, 1, 1, 1)",
                 ("Gmail", json.dumps(cfg)))
nid = cur.lastrowid
ids = [r[0] for r in db.execute("select id from monitor")]
db.executemany("insert into monitor_notification (monitor_id, notification_id) values (?, ?)", [(i, nid) for i in ids])
db.commit()
print(f"Gmail notification added to {len(ids)} monitors")
'
{ op read "$USER_REF"; op read "$PASS_REF"; } |
  ssh -i "$KEY" -o BatchMode=yes turbx@10.69.20.115 "cd /opt/docker/uptime-kuma && docker compose stop >/dev/null 2>&1 &&
    sudo python3 -c '$kuma_py'; docker compose up -d >/dev/null 2>&1 && echo 'Uptime Kuma started'"

echo "== Test emails (one per Proxmox target)"
ssh -i "$KEY" root@10.69.20.130 'pvesh create /cluster/notifications/targets/gmail/test && echo "prx1 sent"'
ssh -i "$KEY" root@10.69.20.131 'pvesh create /cluster/notifications/targets/gmail/test && echo "prx2 sent";
  proxmox-backup-manager notification target test gmail && echo "Backup Server sent"'
