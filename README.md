# 🍓 Pi Backup

![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-c51a4a)
![Shell](https://img.shields.io/badge/shell-bash-89e051)
![License](https://img.shields.io/badge/license-MIT-blue)
![Works on](https://img.shields.io/badge/Pi%20OS-Bookworm%20%7C%20Bullseye-brightgreen)
![Tests](https://img.shields.io/badge/tests-26%20passing-brightgreen)

> **One command to set it up. Real commands to run it. Restores that actually work.**

```
curl -fsSL https://raw.githubusercontent.com/keshavsapra/pi-backup/refs/heads/main/pi-backup-install.sh \
  -o /tmp/pi-backup-install.sh && sudo bash /tmp/pi-backup-install.sh
```

---

## Why this exists

A Raspberry Pi's SD card is the least reliable part of the whole build. When it dies — and it
will — what matters is whether you can get your home, your configs and your services back *today*.

Pi Backup is a friendly, fat-free alternative to heavyweight tools like
[raspiBackup](https://github.com/framps/raspiBackup): a 7-question wizard instead of a
5000-line script, but built around the same hard truths — **versioned backups, verified
integrity, and a restore you have actually rehearsed.**

### v2 at a glance

| | v1 | v2 |
|---|---|---|
| Install | wizard writes a cron+script | wizard installs a real CLI (`pi-backup`) |
| Run a backup | `sudo bash /usr/local/bin/kev-backup.sh` | `sudo pi-backup backup` |
| **Restore** | ❌ manual tar recovery | `sudo pi-backup restore` (interactive or fully scripted) |
| Schedule | cron only | systemd timer (catches up if the Pi was off) or cron |
| Integrity | optional `tar -t` | sha256 checksum + full archive verify, per backup |
| Concurrent runs | can corrupt archives | flock lockfile — overlapping runs refuse to start |
| Live-system safe | tar rc=1 aborts backup | files changed mid-run are tolerated & logged |
| Full backup drive | silent failure | pre-flight space check with clear numbers |
| Old package lists | never cleaned | retention prunes archives, checksums, manifests, lists |
| Config edits | re-run wizard, retype everything | wizard remembers; or `pi-backup config set KEY VALUE` |

---

## What gets backed up

You pick during the wizard — sensible defaults, all stored as a plain config file:

| Directory | What's in there |
|---|---|
| `/etc` | system configuration |
| `/home` | user files |
| `/usr/local/bin` | your custom scripts |
| `/opt` | installed software |
| `/boot/firmware` | Pi config (`config.txt`, overlays) |

Every backup additionally stores:
- a **sha256 checksum** (`.sha256`) so corruption is detectable,
- a **manifest** (host, kernel, duration, what was included, verify status),
- an **installed-package list** (`dpkg`) so you can rebuild dependencies on fresh hardware.

Common cache/trash/docker paths are excluded by default — the wizard shows you the toggles.

## How a backup run works

1. refuses to run into a destination on the root filesystem (your SD card can't back itself up),
2. stops anything you told it to stop (databases etc.) and restarts them afterwards — even on Ctrl-C,
3. pre-flights: enough space at the destination? (or it stops with exact numbers),
4. creates a timestamped `tar.gz` / `tar.zst` archive (`flock` guards against overlaps),
5. verifies the archive + writes the checksum and manifest,
6. prunes beyond your retention window — but **never below a minimum keep-count**,
7. leaves a one-line summary and everything in the log for forensics.

---

## Commands

| Command | What it does |
|---|---|
| `sudo pi-backup backup` | run a backup now |
| `pi-backup list` | show backups (sizes, verify state) — `--json` for scripting |
| `sudo pi-backup verify [name\|latest\|all]` | checksum + integrity check |
| `sudo pi-backup restore` | interactive restore (menus) |
| `sudo pi-backup status` | one-screen dashboard: config, schedule, latest run, free space |
| `sudo pi-backup doctor` | triage: config, drives, tools, timer, checksums |
| `sudo pi-backup delete <name>` | remove a backup(+ sidecars) to free space |
| `sudo pi-backup config set KEY VALUE` | tweak any setting without the wizard |
| `sudo pi-backup schedule install` | (re)install the systemd timer or cron entry |
| `sudo pi-backup update` | update pi-backup from GitHub (syntax-checked first) |
| `sudo pi-backup wizard` | full reconfiguration |
| `sudo pi-backup uninstall` | remove pi-backup — **your backups are never touched** |

Exit codes are stable and documented (`0` ok, `3` busy, `4` config, `5` space, `6` tar, `7` verify) —
so you can script around pi-backup.

## Restore cookbook 🍴

Restoring is a first-class feature, not an afterthought:

**① "I deleted a file / wrecked a config"**
```
sudo pi-backup restore                                # menus: pick archive → pick paths
sudo pi-backup restore latest --paths etc/nginx       # scriptable, same result
```
Before overwriting anything, pi-backup snapshots the files it is about to replace into
`guard-*.tar.gz` in your backup folder — an automatic undo button.

**② "Copy everything to this machine"** (system untouched)
```
sudo pi-backup restore latest --target /mnt/recovered
```

**③ "Fresh SD card / new Pi"**
Flash Raspberry Pi OS, install pi-backup on it, then:
```
sudo pi-backup restore latest --target /          # restore /etc /home /usr/local/bin ... onto /
```
Files being overwritten are guarded first; type `RESTORE` to confirm.

**④ "Packages missing after restore"**
```
sudo pi-backup restore latest --packages
```
It diffs the stored package list against what's installed and installs only what's missing.

## Scheduling that doesn't lie to you

v2 defaults to a **systemd timer** instead of cron:

- `Persistent=true` — if the Pi was switched off at backup time, it catches up on boot,
- `RandomizedDelaySec` — spreads load when several Pis back up to one NAS,
- `TimeoutStartSec=infinity` — big backups aren't killed by systemd's default 90 s,
- `Nice`/`ionice` throttling so the backup doesn't starve your services.

Classic cron is one wizard-selection away, and `Persistent` behaviour is the reason we recommend
the timer. Check when it will fire next: `systemctl list-timers pi-backup-*.timer`.

## Configuration reference

Config lives in `/etc/pi-backup/pi-backup.conf` (plain `KEY="value"`, parsed safely — never
eval'd). The wizard writes it, `pi-backup config set` edits it, `pi-backup config show` reads it.

| Key | Meaning | Default |
|---|---|---|
| `PREFIX` | name prefix for archives | `pi` |
| `DEST` | backup destination (must be a mounted external drive) | — |
| `INCLUDES` | comma-separated paths, relative to `/` | `etc,home,usr/local/bin,opt,boot/firmware` |
| `EXCLUDES` | comma-separated globs | `home/*/.cache,home/*/.local/share/Trash` |
| `RETAIN_DAYS` | prune backups older than this | `90` |
| `RETAIN_MIN` | never prune below this many backups | `3` |
| `COMPRESS` | `gzip` / `zstd` / `none` | `gzip` |
| `VERIFY` | verify + checksum every backup | `true` |
| `PKG_LIST` | save `dpkg` list each run | `true` |
| `SCHEDULER` | `systemd` or `cron` | `systemd` |
| `SCHEDULE`/`HOUR`/`DOW`/`DOM`/`RANDOM_DELAY` | when | `daily`, 02:00, ±15 min |
| `SERVICES_STOP` | services stopped around backup, auto-restarted | — |
| `ALLOW_ROOT_DEV` | allow destination on the root filesystem | `false` |

### Headless / batch installs

No terminal? Set env vars and run the installer:
```
PI_BACKUP_BATCH=1 sudo bash /tmp/pi-backup-install.sh
# recognised: PI_BACKUP_DEST, PI_BACKUP_PREFIX, PI_BACKUP_INCLUDES, PI_BACKUP_EXCLUDES,
#             PI_BACKUP_SCHEDULE, PI_BACKUP_HOUR, PI_BACKUP_RETAIN_DAYS, PI_BACKUP_COMPRESS, ...
```

## Upgrading from v1

Run the installer. It detects old v1 scripts and cron entries, disables them (kept as
`*.v1-disabled`), removes the old cron line, and pre-fills the new wizard with your old settings.
Nothing else changes hands.

## Requirements

- Raspberry Pi running Pi OS (Bookworm or Bullseye — other Debian-family Distro work too)
- an external drive mounted somewhere (USB SSD recommended)
- that's it — bash, tar, coreutils and util-linux are already there

## Testing

```
bash test/run-tests.sh          # 26 checks, entirely inside a /tmp sandbox
```
The suite needs no root and never touches the real system (it exercises documented test hooks:
`PI_BACKUP_TESTING`, `PI_BACKUP_CONF`, `PI_BACKUP_FAKE_*`). CI runs it on every push.

## FAQ

**Why tar and not rsync/dd like raspiBackup?**
Tar archives are simple, portable, verifiable and easy to extract *partially* — which is what
most restores are. If you need running-system image-level restores or rsync-hardlink snapshots,
use [raspiBackup](https://github.com/framps/raspiBackup) — it's excellent at that.
Pi Backup optimises for "I can set it up from a keyboard-width terminal in 5 minutes and I know
exactly how to get my files back."

**Can the destination be a NAS share?** Yes — mount it (NFS/SMB/sshfs) and point `DEST` at the
mount point. The pre-flight checks that it's really mounted.

**Is the archive format stable?** Plain `.tar.gz`/`.tar.zst` — any Linux box can extract it with
plain `tar`. No proprietary formats, ever.

## Why I built this

I'm **Keshav** — an Architect by profession and a tech enthusiast by habit. I run a headless
Raspberry Pi at home for a bunch of things, and one day I realised I had a backup cron job set
up... but had completely forgotten what it was backing up, when, or if it even still worked.

So I built this — the kind of tool I wished existed when I started: something that *just works*,
explains itself, and doesn't assume you spend your days reading man pages.

Not an engineer. Just someone who likes building things — whether in concrete or in bash. 🏛️

---

Made with ☕ and curiosity  ·  [@keshavsapra](https://github.com/keshavsapra)
