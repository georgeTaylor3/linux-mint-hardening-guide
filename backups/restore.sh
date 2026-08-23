#!/bin/bash
# Usage: ./restore.sh [local|cloud] [snapshot-id|latest] [target-directory]
# Restores from either the local encrypted drive or the cloud repository.
# Fill in the placeholders below before use.

set -e

# --- CONFIGURE THESE ---
LUKS_DEVICE="/dev/nvmeXn1"
LUKS_MAPPER_NAME="backup-drive"
MOUNT_POINT="/mnt/backup"
LOCAL_RESTIC_REPO="$MOUNT_POINT/restic-repo"
CLOUD_RESTIC_REPO="gs:YOUR_BUCKET_NAME:/"
PASS_VAULT_NAME="Personal"
LOCAL_PASS_ITEM_TITLE="restic-local-backup"
CLOUD_PASS_ITEM_TITLE="restic-cloud-backup"
# ------------------------

SOURCE=$1
SNAPSHOT=${2:-latest}
TARGET=${3:-/tmp/restic-restore}
export PATH="$HOME/.local/bin:$PATH"

if [ "$SOURCE" = "local" ]; then
    echo "Mounting local backup drive..."
    sudo cryptsetup open "$LUKS_DEVICE" "$LUKS_MAPPER_NAME"
    sudo mount "/dev/mapper/$LUKS_MAPPER_NAME" "$MOUNT_POINT"
    REPO="$LOCAL_RESTIC_REPO"
    export RESTIC_PASSWORD_COMMAND="pass-cli item view --vault-name \"$PASS_VAULT_NAME\" --item-title \"$LOCAL_PASS_ITEM_TITLE\" --field password"
elif [ "$SOURCE" = "cloud" ]; then
    REPO="$CLOUD_RESTIC_REPO"
    export RESTIC_PASSWORD_COMMAND="pass-cli item view --vault-name \"$PASS_VAULT_NAME\" --item-title \"$CLOUD_PASS_ITEM_TITLE\" --field password"
else
    echo "Usage: $0 [local|cloud] [snapshot-id|latest] [target-directory]"
    exit 1
fi

echo "Restoring snapshot '$SNAPSHOT' from $SOURCE to $TARGET ..."
mkdir -p "$TARGET"
restic -r "$REPO" restore "$SNAPSHOT" --target "$TARGET"

if [ "$SOURCE" = "local" ]; then
    sudo umount "$MOUNT_POINT"
    sudo cryptsetup close "$LUKS_MAPPER_NAME"
fi

echo "Restore complete. Files are in $TARGET"
