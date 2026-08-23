# Automated Backups: Local + Cloud with Restic and Proton Pass

This documents the backup pattern used on this machine: a versioned,
deduplicating backup tool (Restic) running to two destinations, with
repository passwords managed through a password manager's CLI rather than
stored on disk — including a fully unattended cloud leg triggered by a
systemd timer with no plaintext secrets anywhere in the scripts themselves.

The scripts in this folder are genericized — no real bucket names, device
paths, or Proton Pass identifiers. Each has a `--- CONFIGURE THESE ---`
block near the top; fill those in for your own setup before running.

## Files

- `local-backup.sh` — backs up to an on-demand, LUKS-encrypted local drive
- `cloud-backup.sh` — backs up unattended to cloud object storage, designed
  to run from a systemd timer
- `restore.sh` — restores from either destination:
  `./restore.sh [local|cloud] [snapshot-id|latest] [target-directory]`

## Architecture

- **Local**: an encrypted (LUKS) drive, mounted on demand, not permanently
  attached — reduces the always-on attack surface for a local ransomware
  scenario.
- **Cloud**: object storage (GCS Nearline in the original setup, but the
  pattern applies to any S3-compatible backend), backed up daily and
  unattended via a systemd timer.
- **Secrets**: Restic repository passwords are stored in a password manager
  (Proton Pass here) and retrieved at runtime via its CLI, never hardcoded
  or left in a plaintext file.

## Why not just a password file?

`RESTIC_PASSWORD_FILE` pointing at a plaintext file on disk is the simplest
option and reasonable if the disk itself is already encrypted. Routing
through a password manager's CLI instead adds:
- Centralized secret rotation/audit (one place to change/revoke, not a file
  scattered across scripts)
- Scoped, revocable, time-limited access via a Personal Access Token (PAT)
  rather than a static file an attacker could just `cat`
- No secret material persisted outside the password manager's own encrypted
  store, even temporarily

## The unattended-automation problem

A password manager's CLI is normally backed by an OS keyring or an
interactive login session — neither of which is available to a systemd
timer firing at 2am with nobody logged in. Solving this took three pieces,
all reflected in `cloud-backup.sh`:

1. **A scoped Personal Access Token (PAT)**, not your main account
   credentials, granted access to only the single secret the automation
   needs — not the whole vault. Tokens expire automatically, limiting
   blast radius if one ever leaks.
2. **Filesystem-based key storage** (`PROTON_PASS_KEY_PROVIDER=fs`) instead
   of the OS keyring, since the default keyring backend typically requires
   a desktop session or D-Bus and often doesn't persist reliably across
   reboots — a real problem for something that needs to "just work"
   unattended.
3. **A dedicated, isolated session directory**
   (`PROTON_PASS_SESSION_DIR=...`) for the automated identity, separate
   from your normal interactive session. Sharing a session directory
   between two different key-storage backends causes each login to
   silently invalidate the other's stored key — a subtle failure mode
   worth avoiding by design rather than debugging later.

## Setting up the PAT

```
pass-cli pat create --name "cloud-backup-timer" --expiration 1y
pass-cli pat access grant --pat-name "cloud-backup-timer" \
    --share-id "<your vault's share ID>" \
    --item-title "<your item title>" --role viewer
```

Save the printed token (`pst_...` — shown only once) into a
root/owner-restricted file (`chmod 600`) and source it from
`cloud-backup.sh`. Find your vault's Share ID with:

```
pass-cli vault list --output json
```

Note: an item-scoped PAT can resolve items by `--share-id`, but not by
`--vault-name` — vault-name resolution requires broader access the PAT
deliberately doesn't have.

## Other things worth building in

- **Idempotent mount/unmount logic** for the local leg — check whether the
  drive is already open/mounted before assuming a cold start, so a
  previous partial failure doesn't break the next run.
- **A connectivity check before attempting the cloud leg**, exiting cleanly
  (not as a failure) if offline — being disconnected is an expected state
  for a laptop, not an error condition, and shouldn't spam failure alerts.
- **Retention and pruning** (e.g. daily/weekly/monthly policies), so
  storage cost doesn't grow unbounded — a deduplicating backup tool only
  uploads changed data day-to-day, but old snapshots still need aging out.
- **Logging to syslog** with a distinct tag per job, so backup activity is
  greppable and auditable rather than silent.
- **A tested restore path** — a backup system is unproven until a full
  restore has actually been run and diffed against the source. This was
  validated end-to-end (byte-for-byte match via `diff -rq`) before trusting
  the system.

## systemd units for the cloud timer

```
# /etc/systemd/system/cloud-backup.service
[Unit]
Description=Restic cloud backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/path/to/cloud-backup.sh
User=youruser
```

```
# /etc/systemd/system/cloud-backup.timer
[Unit]
Description=Daily cloud backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable with `sudo systemctl enable --now cloud-backup.timer`.

## Result

Both legs run cleanly: the local backup on demand, the cloud backup fully
unattended via systemd with zero manual intervention, secrets pulled live
from the password manager, and a verified restore path — all without any
plaintext credentials committed to source control or sitting on disk
outside the password manager's own encrypted store.
