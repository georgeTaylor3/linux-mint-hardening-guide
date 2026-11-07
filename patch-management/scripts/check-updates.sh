#!/usr/bin/env bash
# Warns when dnf5-automatic has not completed a run in 48 hours, when the
# last run failed, or when a reboot has been pending for 3 days.
# Each warning goes to the desktop through notify-send. To send it elsewhere
# as well, set ALERT to a command that takes three arguments: a key, a
# subject, and a body. The key names the warning (update-check,
# updates-overdue, updates-failed, reboot-pending), so the command can limit
# how often it sends each one.
#
# Settings (environment variables):
#   UNIT              service to watch (default dnf5-automatic.service)
#   MAX_RUN_AGE_H     hours without a completed run before a warning (48)
#   MAX_REBOOT_AGE_H  hours a reboot may stay pending before a warning (72)
#   STATE_DIR         where the script keeps its state
#   ALERT             optional command, called as: ALERT key subject body
#   EXCLUDE_REPOS     repository ids left out of the pending-update count
set -u

UNIT="${UNIT:-dnf5-automatic.service}"
MAX_RUN_AGE_H="${MAX_RUN_AGE_H:-48}"
MAX_REBOOT_AGE_H="${MAX_REBOOT_AGE_H:-72}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/update-check}"
ALERT="${ALERT:-}"
EXCLUDE_REPOS="${EXCLUDE_REPOS:-}"

RUN_STATE="$STATE_DIR/last-run"
FIRST_SEEN="$STATE_DIR/first-seen"
REBOOT_STATE="$STATE_DIR/reboot-since"

now=$(date +%s)
boot_epoch=$(( now - $(cut -d. -f1 /proc/uptime) ))
mkdir -p "$STATE_DIR"
[ -f "$FIRST_SEEN" ] || echo "$now" > "$FIRST_SEEN"

warn() {  # key subject body
    notify-send -u critical "$2" "$3" 2>/dev/null || true
    if [ -n "$ALERT" ]; then "$ALERT" "$1" "$2" "$3" || echo "update-check: alert command failed for $1" >&2; fi
}

if [ "$(systemctl show -p LoadState --value "$UNIT" 2>/dev/null)" != "loaded" ]; then
    warn update-check "Update check cannot find $UNIT" \
        "Install dnf5-plugin-automatic and enable dnf5-automatic.timer."
    exit 0
fi

result=$(systemctl show -p Result --value "$UNIT")
status=$(systemctl show -p ExecMainStatus --value "$UNIT")
last_exit=$(systemctl show -p ExecMainExitTimestamp --value "$UNIT")
ran=0
if [ -n "$last_exit" ] && [ "$last_exit" != "n/a" ]; then ran=1; fi

# systemd clears its run record at boot, and a check that fires as a run
# starts can find it missing. The newest successful run comes from three
# places, and the newest of them wins: systemd, the journal (a successful
# run logs "Finished"), and the state saved by earlier checks.
last_epoch=0
if [ "$ran" -eq 1 ] && [ "$result" = "success" ] && [ "$status" = "0" ]; then
    if e=$(date -d "$last_exit" +%s 2>/dev/null); then last_epoch=$e; fi
fi
j=$(journalctl -u "$UNIT" --since "14 days ago" --no-pager -o short-unix 2>/dev/null \
    | grep ' systemd\[1\]: Finished ' | tail -n 1 | cut -d. -f1)
case "$j" in
    ''|*[!0-9]*) ;;
    *) if [ "$j" -gt "$last_epoch" ]; then last_epoch=$j; fi ;;
esac
if [ -r "$RUN_STATE" ]; then
    saved=$(cat "$RUN_STATE")
    if [ "$saved" -gt "$last_epoch" ] 2>/dev/null; then last_epoch=$saved; fi
fi
if [ "$last_epoch" -gt 0 ]; then echo "$last_epoch" > "$RUN_STATE"; fi

# Without a recorded run, count from the first time this script ran.
baseline=$last_epoch
if [ "$baseline" -eq 0 ]; then baseline=$(cat "$FIRST_SEEN"); fi
age_h=$(( (now - baseline) / 3600 ))
if [ "$age_h" -ge "$MAX_RUN_AGE_H" ]; then
    # Best effort. dnf check-update exits 100 when updates are available and
    # 0 when none are. Any other result means the count is unknown. A
    # third-party repository whose key is not imported can make the check
    # fail, so list such repository ids in EXCLUDE_REPOS.
    pending="unknown"
    repo_args=()
    if [ -n "$EXCLUDE_REPOS" ]; then repo_args=(--disablerepo="$EXCLUDE_REPOS"); fi
    list=$(timeout 120 dnf "${repo_args[@]}" check-update --quiet </dev/null 2>/dev/null)
    crc=$?
    case "$crc" in
        0)   pending=0 ;;
        100) pending=$(printf '%s\n' "$list" | awk 'NF==3' | wc -l) ;;
    esac
    warn updates-overdue "Updates overdue" \
"No completed dnf5-automatic run in the last $age_h hours.
Packages pending: $pending

Install now:   sudo dnf upgrade --refresh
Timer status:  systemctl list-timers dnf5-automatic.timer"
fi

# Failure: the service is in a failed state or its last run did not succeed.
failed=0
if systemctl is-failed --quiet "$UNIT"; then failed=1; fi
if [ "$ran" -eq 1 ] && { [ "$result" != "success" ] || [ "$status" != "0" ]; }; then failed=1; fi
if [ "$failed" -eq 1 ]; then
    details=$(journalctl -u "$UNIT" -n 15 --no-pager -o cat 2>/dev/null)
    warn updates-failed "Updates failed" \
"The last dnf5-automatic run failed (result: $result, exit status: $status).

${details:-Journal not readable.}

Details: journalctl -u $UNIT"
fi

# Reboot pending: dnf needs-restarting exits with 1 when a reboot is
# recommended. It runs without repositories, so it needs no network and no
# repository keys. Exit code 1 also covers errors, so a reboot is counted
# only when the output mentions one.
out=$(timeout 120 dnf --disablerepo='*' needs-restarting </dev/null 2>&1)
rc=$?
if [ "$rc" -eq 1 ] && ! printf '%s' "$out" | grep -qi 'reboot'; then
    rc=2
fi
case "$rc" in
    1)
        [ -f "$REBOOT_STATE" ] || echo "$now" > "$REBOOT_STATE"
        since=$(cat "$REBOOT_STATE")
        if [ "$since" -lt "$boot_epoch" ]; then
            since=$now
            echo "$now" > "$REBOOT_STATE"
        fi
        reboot_h=$(( (now - since) / 3600 ))
        if [ "$reboot_h" -ge "$MAX_REBOOT_AGE_H" ]; then
            warn reboot-pending "Reboot pending" \
                "A reboot has been pending for $reboot_h hours. Check: dnf needs-restarting"
        fi
        ;;
    0)
        rm -f "$REBOOT_STATE"
        ;;
esac
