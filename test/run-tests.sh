#!/usr/bin/env bash
# ============================================================================
#  pi-backup test suite — runs entirely in a /tmp sandbox
#
#  Usage:   bash test/run-tests.sh
#  Env:     PI_BACKUP_BIN   path to the pi-backup CLI (default ../pi-backup)
#
#  The suite never touches the real system: it sets PI_BACKUP_TESTING=1
#  (a documented test hook — skips root checks and simulates schedulers) and
#  PI_BACKUP_CONF pointing at a sandbox config.
# ============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1
PB="${PI_BACKUP_BIN:-$(pwd)/pi-backup}"

export PI_BACKUP_TESTING=1
SB="/tmp/pi-backup-test"
SRC="$SB/src"
DEST="$SB/dest"
CONF="$SB/conf/pi-backup.conf"
LOG="$SB/backup.log"
export PI_BACKUP_CONF="$CONF"

PASS=0
FAIL=0
FAILED_TESTS=""

say_pass()  { printf '  ✓ %s\n' "$1"; PASS=$(( PASS + 1 )); }
say_fail()  { printf '  ✗ %s   (%s)\n' "$1" "$2"; FAIL=$(( FAIL + 1 )); FAILED_TESTS="$FAILED_TESTS
    - $1"; }
check_eq()  { local name="$1" got="$2" want="$3"; if [[ "$got" == "$want" ]]; then say_pass "$name"; else say_fail "$name" "got '$got' want '$want'"; fi; }
check_rc()  { check_eq "$1" "$2" "$3"; }
check_yes() { local name="$1" ok="$2"; if [[ "$ok" == "0" ]]; then say_pass "$name"; else say_fail "$name" "expected success"; fi; }
check_no()  { local name="$1" ok="$2"; if [[ "$ok" != "0" ]]; then say_pass "$name"; else say_fail "$name" "expected failure"; fi; }
check_count() { # check_count NAME MINIMUM  (reads count on stdin)
  local name="$1" minimum="$2" count
  count="$(cat)"
  if (( count >= minimum )); then say_pass "$name"; else say_fail "$name" "count=$count min=$minimum"; fi
}

fresh_conf() {
  cat > "$CONF" <<EOF
PREFIX="pi"
DEST="$DEST"
INCLUDES="tmp/pi-backup-test/src/etc,tmp/pi-backup-test/src/home"
EXCLUDES=""
RETAIN_DAYS="365"
RETAIN_MIN="2"
COMPRESS="gzip"
VERIFY="true"
PKG_LIST="true"
SCHEDULER="systemd"
SCHEDULE="daily"
HOUR="2"
DOW="0"
DOM="1"
RANDOM_DELAY="15"
SERVICES_STOP=""
LOG_FILE="$LOG"
ALLOW_ROOT_DEV="false"
EOF
}

setup() {
  rm -rf "$SB"
  mkdir -p "$SRC/etc" "$SRC/home/user/cache" "$DEST" "$(dirname "$CONF")"
  echo "config-file"   > "$SRC/etc/config.txt"
  echo "secret-file"   > "$SRC/etc/passwd-like.txt"
  echo "cacheable"     > "$SRC/home/user/cache/junk.tmp"
  echo "precious data" > "$SRC/home/user/data.txt"
  fresh_conf
}

setup

echo ""
printf "pi-backup test suite\n"
printf "───────────────────\n"

# ── T01: backup creates archive + checksum + manifest + packages ───────────
bash "$PB" backup -q >/dev/null 2>&1
check_rc "backup runs (rc)" $? 0
find "$DEST" -maxdepth 1 -name 'pi-backup-*.tar.gz' | wc -l | check_count "archive created" 1
find "$DEST" -maxdepth 1 -name '*.sha256' | wc -l | check_count "sha256 sidecar" 1
find "$DEST" -maxdepth 1 -name '*.manifest' | wc -l | check_count "manifest" 1
find "$DEST" -maxdepth 1 -name '*packages-*.txt' | wc -l | check_count "package list" 1

# ── T02/T03: verification catches tampering ────────────────────────────────
bash "$PB" verify latest >/dev/null 2>&1
check_rc "verify latest (clean)" $? 0
ARCHIVE="$(find "$DEST" -maxdepth 1 -name 'pi-backup-*.tar.gz' | sort | head -1)"
ARCHIVE="${ARCHIVE##*/}"
cp "$DEST/$ARCHIVE" "$SB/good.bak"
printf 'corrupted-bytes' >> "$DEST/$ARCHIVE"
bash "$PB" verify "$ARCHIVE" >/dev/null 2>&1
check_rc "verify detects tampering (rc=7)" $? 7
mv "$SB/good.bak" "$DEST/$ARCHIVE"

# ── T04: zstd round-trip (when available) ──────────────────────────────────
if command -v zstd >/dev/null 2>&1; then
  sed -i 's/COMPRESS="gzip"/COMPRESS="zstd"/' "$CONF"
  bash "$PB" backup -q >/dev/null 2>&1
  check_rc "zstd backup runs" $? 0
  ZST="$(find "$DEST" -maxdepth 1 -name 'pi-backup-*.tar.zst' | sort | head -1)"
  ZST="${ZST##*/}"
  [[ -n "$ZST" ]] && zstd -t "$DEST/$ZST" >/dev/null 2>&1
  check_yes "zstd archive is valid" $?
  sed -i 's/COMPRESS="zstd"/COMPRESS="gzip"/' "$CONF"
fi
# ── T05: restore into an empty dir reproduces the source tree ──────────────
rm -rf "$SB/restore1"
bash "$PB" restore --latest --target "$SB/restore1" >/dev/null 2>&1
check_rc "restore --target runs" $? 0
diff -r "$SRC" "$SB/restore1/tmp/pi-backup-test/src" >/dev/null 2>&1
check_yes "restored tree is identical" $?

# ── T06: selective path restore + guard snapshot ───────────────────────────
rm -f "$SRC/home/user/data.txt"
bash "$PB" restore --latest --paths tmp/pi-backup-test/src/home -y >/dev/null 2>&1
check_rc "restore --paths (+--yes) runs" $? 0
if [[ -f "$SRC/home/user/data.txt" ]]; then check_pass_ok=0; else check_pass_ok=1; fi
check_yes "restored file is back" "$check_pass_ok"
find "$DEST" -maxdepth 1 -name 'guard-*.tar.gz' | wc -l | check_count "guard snapshot written" 1

# ── T07: dry-run changes nothing, writes no guard ──────────────────────────
GUARD0="$(find "$DEST" -maxdepth 1 -name 'guard-*' | wc -l)"
bash "$PB" restore --latest --dry-run --target "$SB/nowhere-x" >/dev/null 2>&1
if [[ -d "$SB/nowhere-x" ]]; then check_dir_ok=0; else check_dir_ok=1; fi
check_no  "dry-run creates no target dir" "$check_dir_ok"
GUARD1="$(find "$DEST" -maxdepth 1 -name 'guard-*' | wc -l)"
check_eq "dry-run writes no guard" "$GUARD1" "$GUARD0"

# ── T08: retention prunes old but always keeps RETAIN_MIN ──────────────────
OLDEST="$(find "$DEST" -maxdepth 1 \( -name 'pi-backup-*.tar.gz' -o -name 'pi-backup-*.tar.zst' \) | sort | head -1)"
OLDEST="${OLDEST##*/}"
touch -d '400 days ago' "$DEST/$OLDEST" "$DEST/$OLDEST.sha256" 2>/dev/null
bash "$PB" backup -q >/dev/null 2>&1
if [[ -f "$DEST/$OLDEST" ]]; then check_gone_ok=0; else check_gone_ok=1; fi
check_no "retention: oldest archive pruned" "$check_gone_ok"
N_KEEP="$(find "$DEST" -maxdepth 1 -regextype posix-extended -regex '.*pi-backup-[0-9]{8}-[0-9]{6}\.tar.*' | wc -l)"
check_yes "retention: RETAIN_MIN honoured (>=2 kept)" "$( (( N_KEEP >= 2 )); echo $? )"

# ── T09: not-enough-space → rc 5 ───────────────────────────────────────────
PI_BACKUP_FAKE_SRC_BYTES=200000000000 PI_BACKUP_FAKE_FREE_BYTES=1000 \
  bash "$PB" backup -q >/dev/null 2>&1
check_rc "space pre-flight blocks (rc=5)" $? 5

# ── T10: live-file-change (tar rc 1) tolerated ─────────────────────────────
PI_BACKUP_FAKE_TAR_RC=1 bash "$PB" backup -q >/dev/null 2>&1
check_rc "live-file change tolerated (rc=0)" $? 0

# ── T11: lock blocks overlapping runs ─────────────────────────────────────
flock "$DEST/.pi-backup.lock" -c 'sleep 2' 2>/dev/null &
LOCK_PID=$!
sleep 0.3
bash "$PB" backup -q >/dev/null 2>&1
check_rc "concurrent run blocked (rc=3)" $? 3
wait "$LOCK_PID" 2>/dev/null

# ── T12: list --json is valid JSON ────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  bash "$PB" list --json 2>/dev/null | python3 -m json.tool >/dev/null 2>&1
  check_rc "list --json is valid JSON" $? 0
fi

# ── T13: delete removes archive + sidecars ────────────────────────────────
DEL="$(find "$DEST" -maxdepth 1 -name 'pi-backup-*.tar.gz' | sort | head -1)"
DEL="${DEL##*/}"
bash "$PB" delete --force "$DEL" >/dev/null 2>&1
check_rc "delete works" $? 0
if [[ -f "$DEST/$DEL" ]]; then check_d1=0; else check_d1=1; fi
check_no "deleted archive gone"    "$check_d1"
if [[ -f "$DEST/$DEL.sha256" ]]; then check_d2=0; else check_d2=1; fi
check_no "deleted sidecar gone"    "$check_d2"
# ── T14: config validation rejects bad values ─────────────────────────────
bash "$PB" config set DEST not-absolute >/dev/null 2>&1
check_rc "config set rejects bad DEST (rc=4)" $? 4
bash "$PB" config set NOPE value >/dev/null 2>&1
check_rc "config set rejects unknown key (rc=4)" $? 4

# ── T15: batch wizard applies env config safely ───────────────────────────
PI_BACKUP_BATCH=1 PI_BACKUP_DEST="$DEST" PI_BACKUP_PREFIX="pi" \
  bash "$PB" wizard >/dev/null 2>&1
check_rc "batch wizard applies env config" $? 0
grep -q "DEST=\"$DEST\"" "$CONF"
check_yes "batch wizard saved DEST to config" $?

# ── T16: status + doctor run ──────────────────────────────────────────────
bash "$PB" status >/dev/null 2>&1
check_rc "status renders" $? 0
bash "$PB" doctor >/dev/null 2>&1
DRC=$?
check_eq "doctor returns 0 or 1" "$( [[ $DRC == 0 || $DRC == 1 ]]; echo $? )" 0

echo ""
printf '  ✓ %d passed   ✗ %d failed\n' "$PASS" "$FAIL"
if (( FAIL )); then
  printf '  failed tests:%s\n' "$FAILED_TESTS"
  exit 1
fi
printf '  all green 🍓\n'
exit 0
