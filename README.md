# 🍓 Pi Backup
![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-c51a4a)
![Shell](https://img.shields.io/badge/shell-bash-89e051)
![License](https://img.shields.io/badge/license-MIT-blue)
![Works on](https://img.shields.io/badge/Pi%20OS-Bookworm%20%7C%20Bullseye-brightgreen)
![Made with](https://img.shields.io/badge/made%20with-curiosity-orange)

> **One command. A full backup wizard. No engineering degree required.**

```bash
curl -fsSL https://raw.githubusercontent.com/keshavsapra/pi-backup/refs/heads/main/pi-backup-install.sh \
  -o /tmp/pi-backup-install.sh && sudo bash /tmp/pi-backup-install.sh
```

---

## What is this?

A plug-and-play backup installer for Raspberry Pi — built for people who actually *use* their Pi for things, not just tinker with it.

Run one command and a friendly setup wizard walks you through everything:

- 📁 &nbsp;**Where** to save your backups
- 🗂️ &nbsp;**What** directories to include
- 🕑 &nbsp;**When** to run (daily / weekly / monthly)
- 🗑️ &nbsp;**How long** to keep old backups before auto-deleting them
- 📦 &nbsp;**Package list** snapshot so you can restore everything
- ✅ &nbsp;**Test run** right after install to confirm it all works

No editing cron jobs by hand. No terminal wizardry. Just answer the questions and you're done.

<img width="450" height="282" alt="image" src="https://github.com/user-attachments/assets/02e4c379-c7ad-405c-bd50-ec37609722cb" /> <img width="450" height="414" alt="image" src="https://github.com/user-attachments/assets/fa51b9a2-5aaa-456f-9170-c4148e73359c" /> <img width="450" height="414" alt="image" src="https://github.com/user-attachments/assets/150df715-c309-45af-8f29-a638f623a143" /> <img width="450" height="414" alt="image" src="https://github.com/user-attachments/assets/c2e9dbcf-8bea-4b39-a4ff-3b0d09580ac6" /> <img width="450" height="422" alt="image" src="https://github.com/user-attachments/assets/cd25c3dc-3478-4fa1-a7f4-64633dce0061" />




---

## What gets backed up?

You choose during setup — but the defaults cover everything that matters:

| Directory | What's in there |
|---|---|
| `/etc` | System config files |
| `/home` | Your user files |
| `/usr/local/bin` | Custom scripts |
| `/opt` | Installed software |
| `/boot/firmware` | Pi config (config.txt, overlays) |

---

## How it works

The installer writes a clean backup script to `/usr/local/bin/` and drops a cron job into your system — no manual crontab editing, no weird syntax errors.

Every backup run:
1. Checks your drive is actually mounted (won't fail silently)
2. Creates a timestamped `.tar.gz` archive
3. Optionally verifies the archive isn't corrupt
4. Saves a list of all installed packages
5. Prunes old backups past your retention window
6. Logs everything so you can see what happened

To restore packages on a fresh Pi:
```bash
sudo dpkg --set-selections < kev-packages-YYYYMMDD.txt
sudo apt-get dselect-upgrade
```

---

## Requirements

- Raspberry Pi running **Pi OS** (Bookworm or Bullseye)
- An external drive mounted somewhere (USB SSD recommended)
- That's it

---

## Why I built this

I'm **Keshav** — an Architect by profession and a tech enthusiast by habit. I run a headless Raspberry Pi at home for a bunch of things, and one day I realised I had a backup cron job set up... but had completely forgotten what it was backing up, when, or if it even still worked.

So I built this — the kind of tool I wished existed when I started: something that *just works*, explains itself, and doesn't assume you spend your days reading man pages.

Not an engineer. Just someone who likes building things — whether in concrete or in bash. 🏛️

---

## Updating your config

Just re-run the installer — it safely replaces the old cron entry without duplicating it.

---

## Useful commands after install

```bash
# Run a backup manually
sudo bash /usr/local/bin/kev-backup.sh

# Check your cron job is installed
sudo crontab -l

# Watch the log live
tail -f /var/log/kev-backup.log
```

---

<p align="center">Made with ☕ and curiosity &nbsp;·&nbsp; <a href="https://github.com/keshavsapra">@keshavsapra</a></p>
