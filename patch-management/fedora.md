# Automatic security updates on Fedora (dnf5-automatic)

Tested on Fedora 44 KDE with dnf5-plugin-automatic 5.4.6.0.

## Result

Updates that carry a security advisory download and install daily without a prompt. Other updates and reboots stay manual.

How the timers, the check script, and the alerts connect: [update-workflow.md](update-workflow.md).

## Differences from the Mint guide

- Fedora uses DNF5 and `dnf5-automatic` in place of `unattended-upgrades`. There is no origins pattern to maintain. The setting `upgrade_type = security` selects updates that carry a security advisory.
- Repositories that do not publish advisories in their metadata may have no updates selected. Update those with `sudo dnf upgrade --refresh`.
- The pre-configured install, download, and notify-only timers of the older package are gone. One timer, `dnf5-automatic.timer`, follows the settings in `/etc/dnf/automatic.conf`.
- The timer does not run on image-based variants such as Silverblue and Kinoite. It has the condition `ConditionPathExists=!/run/ostree-booted`.

## Setup

1. Install the plugin:

        sudo dnf install dnf5-plugin-automatic

2. Write the configuration. Values in `/etc/dnf/automatic.conf` override the defaults in `/usr/share/dnf5/dnf5-plugins/automatic.conf`:

        [commands]
        upgrade_type = security
        download_updates = yes
        apply_updates = yes
        reboot = never

3. Enable the timer:

        sudo systemctl enable --now dnf5-automatic.timer

| Setting | Value | Effect |
|---|---|---|
| `upgrade_type` | `security` | Select only updates with a security advisory. `default` selects all updates. |
| `download_updates` | `yes` | Download the selected updates. |
| `apply_updates` | `yes` | Install the downloaded updates. With `no`, packages stay in the cache. |
| `reboot` | `never` | Reboots stay manual. Other values are `when-changed` and `when-needed`. |

## Schedule

The timer runs daily at 06:00 with a random delay of up to 60 minutes (`OnCalendar=*-*-* 6:00`, `RandomizedDelaySec=60m`). With `Persistent=true`, a run missed while the laptop was off happens after the next boot or wake.

## Check the result

    systemctl list-timers --no-pager dnf5-automatic.timer
    systemctl status dnf5-automatic.service --no-pager
    journalctl -u dnf5-automatic.service --no-pager | tail -30

A completed run shows `status=0/SUCCESS`. The journal lists the packages and ends with `Transaction finished` when updates were installed.

## Reboots

With `reboot = never`, check after kernel and core library updates:

    dnf --disablerepo='*' needs-restarting; echo "exit $?"

Exit code 1 and the message `Reboot is required to fully utilize these updates.` mean a reboot is recommended. Exit code 0 means none is needed. `--disablerepo='*'` runs the check against the installed package database and skips repository metadata, so it needs no network and no repository key approval.

DNF keeps the three newest kernels by default. The oldest is removed at the next kernel update.

## Other updates

    sudo dnf upgrade --refresh

Run this regularly for updates without a security advisory and for third-party repositories.

## Update check (optional)

`scripts/check-updates.sh` runs as a user timer and shows a desktop notification when:

- `dnf5-automatic` has not completed a run in 48 hours,
- the last run failed, or
- a reboot has been pending for 72 hours.

The script takes the newest completed run from three places and uses the latest: systemd's record of the service, the journal (a successful run logs `Finished`), and a copy saved in `~/.local/state/update-check`. systemd clears its record at boot. A check that starts in the same second as a run, which happens when both timers catch up after a suspend, can miss that run. The journal lookup needs a persistent journal (`/var/log/journal` exists) and an account that can read the system journal. `journalctl -u dnf5-automatic.service` as that account shows whether it can. Without journal access, the saved copy covers reboots.

The reboot clock starts when the check first sees the pending reboot, not when the update installed. With `reboot = never`, the warning arrives at the first check 72 hours or more after that.

Install from the repository folder:

    mkdir -p ~/.local/bin ~/.config/systemd/user
    install -m 755 patch-management/scripts/check-updates.sh ~/.local/bin/
    cp patch-management/scripts/update-check.service patch-management/scripts/update-check.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now update-check.timer

The timer runs 15 minutes after login and at 09:00 and 21:00, and catches up after a suspend.

The service waits up to 60 seconds for NetworkManager to report a connection (`nm-online`) before the check runs. The line starts with `-`, so a system without `nm-online` skips the wait. The wait is for the connection. It does not check name resolution, so an `ALERT` command that needs DNS can still fail just after a wake. When the `ALERT` command exits non-zero, the script writes `update-check: alert command failed for KEY` to the journal. Read it with `journalctl --user -u update-check.service`.

Settings are environment variables. To set one for the service, run `systemctl --user edit update-check.service` and add lines such as:

    [Service]
    Environment=EXCLUDE_REPOS=librewolf
    Environment=ALERT=/home/USER/bin/my-alert.sh

| Variable | Default | Effect |
|---|---|---|
| `UNIT` | `dnf5-automatic.service` | Service to watch |
| `MAX_RUN_AGE_H` | `48` | Hours without a completed run before a warning |
| `MAX_REBOOT_AGE_H` | `72` | Hours a reboot may stay pending before a warning |
| `STATE_DIR` | `~/.local/state/update-check` | Location of the state files |
| `ALERT` | none | Command called as `ALERT key subject body`, for email or chat |
| `EXCLUDE_REPOS` | none | Repository ids left out of the pending-update count |

The key passed to `ALERT` names the warning (`update-check`, `updates-overdue`, `updates-failed`, `reboot-pending`), so the command can limit how often it sends each one.

Test without sending anything. The first run records the state. The second forces the overdue warning and prints it instead of calling an alert command:

    ~/.local/bin/check-updates.sh
    ALERT=echo MAX_RUN_AGE_H=0 STATE_DIR=/tmp/update-check-test ~/.local/bin/check-updates.sh

## Rollback

    sudo systemctl disable --now dnf5-automatic.timer
    sudo rm /etc/dnf/automatic.conf
    systemctl --user disable --now update-check.timer
    rm ~/.config/systemd/user/update-check.service ~/.config/systemd/user/update-check.timer ~/.local/bin/check-updates.sh

## Verified

Fedora 44 KDE, dnf5-plugin-automatic 5.4.6.0, 2026-11-02: the timer ran after a missed 06:00 slot, installed a kernel update, and left a reboot pending. `dnf needs-restarting` reported the reboot, and the check cleared after the reboot.

Fedora 44 KDE, 2026-11-03: the next timer transaction installed `kernel-core` 7.2.15 from the `updates` repository (security advisory FEDORA-2026-778424cb43) and removed the oldest installed kernel. Other updates (70 packages on 2026-11-06) stayed pending until `sudo dnf upgrade --refresh`.
