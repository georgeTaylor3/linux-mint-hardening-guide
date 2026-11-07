# Automatic security updates on Fedora (dnf5-automatic)

Tested on Fedora 44 KDE with dnf5-plugin-automatic 5.4.6.0.

## Result

Updates that carry a security advisory download and install daily without a prompt. Other updates and reboots stay manual.

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

## Rollback

    sudo systemctl disable --now dnf5-automatic.timer
    sudo rm /etc/dnf/automatic.conf

## Verified

Fedora 44 KDE, dnf5-plugin-automatic 5.4.6.0, 2026-11-02: the timer ran after a missed 06:00 slot, installed a kernel update, and left a reboot pending. `dnf needs-restarting` reported the reboot, and the check cleared after the reboot.
