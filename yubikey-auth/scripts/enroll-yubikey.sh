#!/bin/bash
# enroll-yubikey.sh — register a YubiKey for pam_u2f under a specific
# user's account, without needing that user to log in first.
#
# Usage: sudo ./enroll-yubikey.sh <target-username>
#
# Must be run with sudo, as an already-authenticated admin user (e.g. gorg).
# Writes to the TARGET user's own home directory with correct ownership,
# so pam_u2f (sudo, screen unlock, login greeter) recognizes the key for
# that account.
#
# IMPORTANT: pamu2fcfg needs live access to the YubiKey's HID/FIDO
# interface (/dev/hidraw*). That access is normally granted by
# systemd-logind only to the user actively logged into the current seat —
# not to an arbitrary target user with no session (which is exactly the
# case here, since the whole point is enrolling a key for someone who
# CAN'T log in yet). Running pamu2fcfg as an unprivileged sudo -u target
# user will silently fail with "No device found" even though the key is
# plugged in and lsusb sees it fine. The fix: run pamu2fcfg as root
# (root always has device access) and use its -u flag to embed the
# correct target username in the output instead of relying on whoami.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo."
    echo "Usage: sudo $0 <target-username>"
    exit 1
fi

TARGET_USER="$1"

if [ -z "$TARGET_USER" ]; then
    echo "Usage: sudo $0 <target-username>"
    exit 1
fi

if ! id "$TARGET_USER" &>/dev/null; then
    echo "Error: user '$TARGET_USER' does not exist."
    exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
YUBICO_DIR="$TARGET_HOME/.config/Yubico"
KEYS_FILE="$YUBICO_DIR/u2f_keys"

echo "Enrolling a YubiKey for user: $TARGET_USER"
echo "Target file: $KEYS_FILE"
echo ""
echo "Make sure ONLY the intended YubiKey is plugged in (unplug any"
echo "others) before continuing, to avoid registering the wrong key."
echo ""
echo "Insert the YubiKey now and touch it when it blinks."
echo ""

mkdir -p "$YUBICO_DIR"

# Run pamu2fcfg AS ROOT (for device access) with -u to embed the correct
# target username, regardless of who's actually invoking this script.
if [ -f "$KEYS_FILE" ]; then
    echo "An existing key file was found for $TARGET_USER."
    read -r -p "Append a new key (for a backup YubiKey) instead of overwriting? [y/N] " APPEND
    if [[ "$APPEND" =~ ^[Yy]$ ]]; then
        pamu2fcfg -u "$TARGET_USER" -n >> "$KEYS_FILE"
    else
        pamu2fcfg -u "$TARGET_USER" > "$KEYS_FILE"
    fi
else
    pamu2fcfg -u "$TARGET_USER" > "$KEYS_FILE"
fi

# Correct, non-group-writable permissions and ownership — pamu2fcfg ran
# as root, so the file needs to be handed back to the target user.
chmod 0644 "$KEYS_FILE"
chown "$TARGET_USER:$TARGET_USER" "$KEYS_FILE"
chown "$TARGET_USER:$TARGET_USER" "$YUBICO_DIR"

echo ""
echo "Done. Contents of $KEYS_FILE:"
cat "$KEYS_FILE"
echo ""
echo "$TARGET_USER can now authenticate via sudo, screen unlock, and the"
echo "login greeter using this YubiKey, provided the system's PAM files"
echo "already include the pam_u2f.so rule (they do, if set up following"
echo "this repo's yubikey-auth/ guide)."
