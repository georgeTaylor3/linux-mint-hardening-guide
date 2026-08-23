#!/bin/bash
# Cloud backup: runs unattended via a systemd timer.
# Authenticates to Proton Pass with a scoped Personal Access Token (PAT),
# never your full account credentials.
# Fill in the placeholders below before use.

set -e

# --- CONFIGURE THESE ---
RESTIC_REPO="gs:YOUR_BUCKET_NAME:/"          # or an s3:, b2:, etc. backend
PASS_ITEM_SHARE_ID="YOUR_VAULT_SHARE_ID"     # from: pass-cli vault list --output json
PASS_ITEM_TITLE="restic-cloud-backup"
PAT_TOKEN_FILE="/etc/proton-pass/backup-token"
PASS_SESSION_DIR="/etc/proton-pass/session"  # dedicated dir, isolated from your interactive session
CONNECTIVITY_CHECK_URL="https://proton.me"
BACKUP_PATHS="$HOME/Documents $HOME/git $HOME/.ssh $HOME/backup-scripts"
# ------------------------

export PATH="$HOME/.local/bin:$PATH"
export PROTON_PASS_KEY_PROVIDER=fs
export PROTON_PASS_SESSION_DIR="$PASS_SESSION_DIR"

# Being offline is expected for a laptop; exit cleanly rather than as a failure.
if ! curl -s --max-time 5 --head "$CONNECTIVITY_CHECK_URL" > /dev/null; then
    logger -t cloud-backup "No internet connectivity — skipping cloud backup for now. Will retry next scheduled run."
    exit 0
fi

logger -t cloud-backup "Starting cloud backup"

set -a
source "$PAT_TOKEN_FILE"
set +a
pass-cli logout 2>/dev/null || true
pass-cli login

export RESTIC_PASSWORD_COMMAND="pass-cli item view --share-id \"$PASS_ITEM_SHARE_ID\" --item-title \"$PASS_ITEM_TITLE\" --field password"

restic -r "$RESTIC_REPO" backup $BACKUP_PATHS
restic -r "$RESTIC_REPO" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

logger -t cloud-backup "Cloud backup complete"
