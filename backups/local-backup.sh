#!/bin/bash
# Local backup: LUKS-encrypted drive, mounted on demand.
# Fill in the placeholders below before use.

set -e

# --- CONFIGURE THESE ---
LUKS_DEVICE="/dev/nvmeXn1"           # your backup drive's device path, e.g. /dev/sdb1 or /dev/nvme1n1
LUKS_MAPPER_NAME="backup-drive"
MOUNT_POINT="/mnt/backup"
RESTIC_REPO="$MOUNT_POINT/restic-repo"
PASS_VAULT_NAME="Personal"           # Proton Pass vault holding the repo password
PASS_ITEM_TITLE="restic-local-backup"
BACKUP_PATHS="$HOME/Documents $HOME/git $HOME/.ssh $HOME/backup-scripts"
# ------------------------

export PATH="$HOME/.local/bin:$PATH"
export RESTIC_PASSWORD_COMMAND="pass-cli item view --vault-name \"$PASS_VAULT_NAME\" --item-title \"$PASS_ITEM_TITLE\" --field password"

logger -t local-backup "Starting local backup"

if [ ! -e "/dev/mapper/$LUKS_MAPPER_NAME" ]; then
    sudo cryptsetup open "$LUKS_DEVICE" "$LUKS_MAPPER_NAME"
fi
if ! mount | grep -q "$MOUNT_POINT"; then
    sudo mount "/dev/mapper/$LUKS_MAPPER_NAME" "$MOUNT_POINT"
fi

restic -r "$RESTIC_REPO" backup $BACKUP_PATHS
restic -r "$RESTIC_REPO" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

sudo umount "$MOUNT_POINT"
sudo cryptsetup close "$LUKS_MAPPER_NAME"

logger -t local-backup "Local backup complete. Drive unmounted and locked."
