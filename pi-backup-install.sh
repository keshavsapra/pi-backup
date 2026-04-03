#!/bin/bash
# ============================================================
#  Pi Backup Installer
#  Usage: sudo bash <(curl -fsSL https://raw.githubusercontent.com/keshavsapra/pi-backup/refs/heads/main/pi-backup-install.sh)
# ============================================================

set -e

# ── colours ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── helpers ──────────────────────────────────────────────────
info()    { echo -e "${CYAN}[info]${NC}  $*"; }
success() { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()     { echo -e "${RED}[error]${NC} $*"; exit 1; }

need_root() {
  [[ $EUID -eq 0 ]] || err "Please run with sudo:  sudo bash pi-backup-install.sh"
}

need_whiptail() {
  command -v whiptail &>/dev/null && return
  info "Installing whiptail..."
  apt-get install -y whiptail &>/dev/null
}

# ── splash ───────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ____  _   ____             _
 |  _ \(_) | __ )  __ _  ___| | ___   _ _ __
 | |_) | | |  _ \ / _` |/ __| |/ / | | | '_ \
 |  __/| | | |_) | (_| | (__|   <| |_| | |_) |
 |_|   |_| |____/ \__,_|\___|_|\_\\__,_| .__/
                                         |_|
EOF
echo -e "${NC}${BOLD}  Automated backup installer for Raspberry Pi${NC}"
echo -e "  ─────────────────────────────────────────────"
echo ""
sleep 1

need_root
need_whiptail

# ════════════════════════════════════════════════════════════
#  STEP 1 — Backup destination
# ════════════════════════════════════════════════════════════
DEST=$(whiptail --title "Pi Backup — Step 1 of 6" \
  --inputbox "Where should backups be saved?\n\nEnter the full path to your backup directory:" \
  10 60 "/mnt/ssd/backups" 3>&1 1>&2 2>&3) || err "Cancelled."

# validate mount point parent exists
MOUNT_PARENT=$(dirname "$DEST")
if ! mountpoint -q "$MOUNT_PARENT" 2>/dev/null && [[ "$MOUNT_PARENT" != "/" ]]; then
  warn "Parent path $MOUNT_PARENT doesn't look like a mounted drive."
  whiptail --title "Warning" --yesno \
    "⚠  $MOUNT_PARENT doesn't appear to be a mounted drive.\n\nIf the drive isn't mounted when the backup runs, it will fail silently.\n\nContinue anyway?" \
    10 60 || err "Cancelled — please mount your drive first."
fi

mkdir -p "$DEST" || err "Could not create $DEST"

# ════════════════════════════════════════════════════════════
#  STEP 2 — Backup name prefix
# ════════════════════════════════════════════════════════════
PREFIX=$(whiptail --title "Pi Backup — Step 2 of 6" \
  --inputbox "Choose a name prefix for your backup files.\n\nExample: 'kev' → kev-20250401.tar.gz" \
  10 60 "pi" 3>&1 1>&2 2>&3) || err "Cancelled."

PREFIX=$(echo "$PREFIX" | tr -cs '[:alnum:]-_' '-' | sed 's/-$//')
[[ -z "$PREFIX" ]] && PREFIX="pi"

# ════════════════════════════════════════════════════════════
#  STEP 3 — What to back up
# ════════════════════════════════════════════════════════════
PATHS=$(whiptail --title "Pi Backup — Step 3 of 6" \
  --checklist "Select directories to include in backup:\n(Space to toggle, Enter to confirm)" \
  20 65 8 \
  "/etc"             "System config files"         ON  \
  "/home"            "User home directories"        ON  \
  "/usr/local/bin"   "Custom scripts & binaries"   ON  \
  "/opt"             "Optional software"            ON  \
  "/boot/firmware"   "Pi firmware (config.txt etc)" ON  \
  "/srv"             "Server data"                  OFF \
  "/root"            "Root home directory"          OFF \
  "/var/www"         "Web server files"             OFF \
  3>&1 1>&2 2>&3) || err "Cancelled."

[[ -z "$PATHS" ]] && err "No directories selected — nothing to back up."

# whiptail returns quoted strings — clean them up
PATHS_CLEAN=$(echo "$PATHS" | tr -d '"')

# ════════════════════════════════════════════════════════════
#  STEP 4 — Schedule
# ════════════════════════════════════════════════════════════
FREQ=$(whiptail --title "Pi Backup — Step 4 of 6" \
  --menu "How often should backups run?" \
  12 55 4 \
  "daily"   "Every day" \
  "weekly"  "Once a week (recommended)" \
  "monthly" "Once a month" \
  3>&1 1>&2 2>&3) || err "Cancelled."

case "$FREQ" in
  daily)
    CRON_SCHED="0 2 * * *"
    SCHED_HUMAN="daily at 2:00 AM"
    ;;
  weekly)
    DAY=$(whiptail --title "Pi Backup — Step 4 of 6" \
      --menu "Which day of the week?" \
      14 45 7 \
      "0" "Sunday" "1" "Monday" "2" "Tuesday" \
      "3" "Wednesday" "4" "Thursday" "5" "Friday" "6" "Saturday" \
      3>&1 1>&2 2>&3) || err "Cancelled."
    DAYS=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
    CRON_SCHED="0 2 * * $DAY"
    SCHED_HUMAN="every ${DAYS[$DAY]} at 2:00 AM"
    ;;
  monthly)
    DOM=$(whiptail --title "Pi Backup — Step 4 of 6" \
      --menu "Which day of the month?" \
      12 45 5 \
      "1" "1st" "7" "7th" "14" "14th" "21" "21st" "28" "28th" \
      3>&1 1>&2 2>&3) || err "Cancelled."
    CRON_SCHED="0 2 $DOM * *"
    SCHED_HUMAN="monthly on the ${DOM}th at 2:00 AM"
    ;;
esac

# ════════════════════════════════════════════════════════════
#  STEP 5 — Retention & options
# ════════════════════════════════════════════════════════════
RETAIN=$(whiptail --title "Pi Backup — Step 5 of 6" \
  --menu "How long to keep old backups?" \
  12 50 4 \
  "30"  "30 days" \
  "60"  "60 days" \
  "90"  "90 days (recommended)" \
  "180" "180 days" \
  3>&1 1>&2 2>&3) || err "Cancelled."

OPTIONS=$(whiptail --title "Pi Backup — Step 5 of 6" \
  --checklist "Extra options:" \
  14 65 4 \
  "pkgs"   "Save installed package list (dpkg)"  ON  \
  "verify" "Verify archive after writing"         OFF \
  "log"    "Log output to file"                   ON  \
  "notify" "Print summary after each run"         ON  \
  3>&1 1>&2 2>&3) || err "Cancelled."

OPT_PKGS=false;   OPT_VERIFY=false; OPT_LOG=false; OPT_NOTIFY=false
[[ "$OPTIONS" == *"pkgs"*   ]] && OPT_PKGS=true
[[ "$OPTIONS" == *"verify"* ]] && OPT_VERIFY=true
[[ "$OPTIONS" == *"log"*    ]] && OPT_LOG=true
[[ "$OPTIONS" == *"notify"* ]] && OPT_NOTIFY=true

LOG_FILE="/var/log/${PREFIX}-backup.log"

# ════════════════════════════════════════════════════════════
#  STEP 6 — Confirm summary
# ════════════════════════════════════════════════════════════
SUMMARY="Review your backup configuration:

  Destination : $DEST
  Name prefix : $PREFIX
  Schedule    : $SCHED_HUMAN
  Retain for  : $RETAIN days
  Directories : $PATHS_CLEAN
  Package list: $OPT_PKGS
  Verify      : $OPT_VERIFY
  Logging     : $OPT_LOG → $LOG_FILE

Proceed with installation?"

whiptail --title "Pi Backup — Step 6 of 6" \
  --yesno "$SUMMARY" 22 65 || err "Cancelled — nothing was installed."

# ════════════════════════════════════════════════════════════
#  BUILD THE BACKUP SCRIPT
# ════════════════════════════════════════════════════════════
SCRIPT_PATH="/usr/local/bin/${PREFIX}-backup.sh"

info "Writing backup script to $SCRIPT_PATH..."

cat > "$SCRIPT_PATH" << SCRIPT
#!/bin/bash
# Auto-generated by pi-backup-install — do not edit by hand
# Re-run the installer to make changes.

PREFIX="${PREFIX}"
DEST="${DEST}"
LOG="${LOG_FILE}"
RETAIN=${RETAIN}
DATE=\$(date +%Y%m%d_%H%M%S)
TAR="\${DEST}/\${PREFIX}-\${DATE}.tar.gz"
START=\$(date +%s)

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*"; }

# ── mount check ──────────────────────────────────────────────
if ! mountpoint -q "\$(dirname "\$DEST")" 2>/dev/null; then
  log "ERROR: \$DEST parent is not a mountpoint. Aborting."
  exit 1
fi

mkdir -p "\$DEST"
log "=== Backup started ==="
log "Target: \$TAR"

# ── archive ──────────────────────────────────────────────────
if tar -czf "\$TAR" ${PATHS_CLEAN} 2>&1; then
  log "Archive created: \$(du -sh "\$TAR" | cut -f1)"
else
  log "ERROR: tar failed"
  exit 1
fi

SCRIPT

if $OPT_VERIFY; then
cat >> "$SCRIPT_PATH" << 'SCRIPT'
# ── verify ───────────────────────────────────────────────────
log "Verifying archive..."
if tar -tzf "$TAR" > /dev/null 2>&1; then
  log "Verify: OK"
else
  log "ERROR: Archive verification failed — backup may be corrupt!"
  exit 1
fi

SCRIPT
fi

if $OPT_PKGS; then
cat >> "$SCRIPT_PATH" << 'SCRIPT'
# ── package list ─────────────────────────────────────────────
PKG_FILE="${DEST}/${PREFIX}-packages-${DATE}.txt"
dpkg --get-selections > "$PKG_FILE"
log "Package list saved: $PKG_FILE"

SCRIPT
fi

cat >> "$SCRIPT_PATH" << SCRIPT
# ── prune old backups ────────────────────────────────────────
DELETED=\$(find "\$DEST" -name "\${PREFIX}-*.tar.gz" -mtime +\$RETAIN -print -delete | wc -l)
[[ \$DELETED -gt 0 ]] && log "Pruned \$DELETED old backup(s) older than \$RETAIN days"

# ── done ─────────────────────────────────────────────────────
END=\$(date +%s)
ELAPSED=\$((END - START))
log "=== Backup complete in \${ELAPSED}s ==="
SCRIPT

chmod +x "$SCRIPT_PATH"
success "Backup script written to $SCRIPT_PATH"

# ════════════════════════════════════════════════════════════
#  INSTALL CRON JOB
# ════════════════════════════════════════════════════════════
info "Installing cron job..."

CRON_CMD="$CRON_SCHED $SCRIPT_PATH"
if $OPT_LOG; then
  CRON_CMD="$CRON_SCHED $SCRIPT_PATH >> $LOG_FILE 2>&1"
fi

# remove any old entry for this prefix, then add new one
( crontab -l 2>/dev/null | grep -v "${PREFIX}-backup" ; echo "$CRON_CMD" ) | crontab -

success "Cron job installed: $CRON_CMD"

# ════════════════════════════════════════════════════════════
#  TEST RUN (optional)
# ════════════════════════════════════════════════════════════
if whiptail --title "Test Run" \
  --yesno "Installation complete!\n\nWould you like to run a test backup now to make sure everything works?" \
  10 60; then
  echo ""
  info "Running test backup — this may take a moment..."
  echo ""
  if bash "$SCRIPT_PATH"; then
    echo ""
    success "Test backup completed successfully!"
    echo -e "  ${BOLD}Files in $DEST:${NC}"
    ls -lh "$DEST" | tail -5
  else
    warn "Test backup failed — check $LOG_FILE for details"
  fi
fi

# ════════════════════════════════════════════════════════════
#  DONE
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}  ✓ Pi Backup installed successfully!${NC}"
echo ""
echo -e "  ${BOLD}Backup script:${NC}  $SCRIPT_PATH"
echo -e "  ${BOLD}Schedule:${NC}       $SCHED_HUMAN"
echo -e "  ${BOLD}Destination:${NC}    $DEST"
if $OPT_LOG; then
echo -e "  ${BOLD}Log file:${NC}       $LOG_FILE"
fi
echo ""
echo -e "  To run manually:    ${CYAN}sudo bash $SCRIPT_PATH${NC}"
echo -e "  To view cron jobs:  ${CYAN}sudo crontab -l${NC}"
if $OPT_LOG; then
echo -e "  To tail the log:    ${CYAN}tail -f $LOG_FILE${NC}"
fi
echo ""
