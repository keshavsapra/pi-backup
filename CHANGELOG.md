# Changelog

## v2.0.0 — 2026-10-26

The wizard-installs-a-cron-script era is over: v2 is a real CLI. Same friendly installer,
much stronger underneath.

### Added
- **`pi-backup` CLI** with subcommands: `backup`, `list [--json]`, `verify`, `restore`,
  `delete`, `status`, `doctor`, `schedule`, `config`, `update`, `uninstall`, `wizard`.
- **Restore flows** (the headline): interactive restore with archive/path pickers,
  `--target DIR` extraction, selective `--paths` restore onto the running system,
  `--packages` reinstall of a saved dpkg list, `--dry-run` for every flow.
- **Pre-restore guard snapshots** — files about to be overwritten are archived first
  (`guard-*.tar.gz`), making restores undoable.
- **Per-backup manifest** (host, kernel, size, duration, included paths, verify state).
- **sha256 checksum sidecars** written and re-checked by `verify`.
- **zstd compression** option (much faster than gzip on a Pi), plus `none`.
- **systemd timer scheduling** with `Persistent=true` (catches up after the Pi was off),
  randomized delay, and `TimeoutStartSec=infinity`; classic cron still available.
- **Pre-flight space check** — refuses to start when the destination is too small,
  with exact numbers in the error.
- **Pre-flight destination sanity** — refuses to back a drive up onto itself
  (destination on the root filesystem) unless explicitly overridden.
- **Service stop/start hooks** — configured services (e.g. MariaDB) are stopped for the
  backup and restarted afterwards, on success *and* on Ctrl-C.
- **flock locking** so overlapping scheduled/manual runs can't corrupt archives.
- **Config-aware wizard** — re-running shows your existing values as defaults, and
  `pi-backup config set KEY VALUE` edits without the wizard at all.
- **v1 migration** — the installer detects old generated scripts/cron entries, disables
  them and pre-fills the new wizard with your old settings.
- **Headless batch mode** (`PI_BACKUP_BATCH=1` + env vars) for ssh-in-one-line installs.
- Test suite (`test/run-tests.sh`, 26 checks, sandboxed) and a CI workflow that runs it.

### Fixed
- Wrong mount check (`mountpoint` on the *parent* directory) that failed when the
  destination itself was a mount root, and passed when the drive was missing.
- `tar` exit code 1 ("file changed as we read it") no longer kills a whole backup on a
  live system; exit ≥ 2 still aborts and cleans the partial archive.
- Old package-list `.txt` files are now pruned with the archives (they used to pile up
  forever and fill the disk).
- Wizard "monthly on the 21**th**" → correct suffixes (st/nd/rd/th).
- Re-running the installer no longer orphans the old cron entry when the prefix changed.
- Unqoted expansion of include paths into tar broke on paths with spaces;
  includes/excludes are now parsed as explicit lists.
- Interrupted backups no longer leave truncated archives that look like valid backups.
- Two backups within the same wall-clock second used to overwrite each other's archive
  (same filename) — the timestamp now advances until the name is free.

### Security
- Config file is parsed key-by-key (no `eval`/`source`), so a corrupted config cannot
  execute arbitrary code; `pi-backup update` refuses files that fail `bash -n`.
