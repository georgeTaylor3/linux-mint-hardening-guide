# Patch Management: Unattended Security Updates

Linux Mint's Update Manager checks for updates and notifies you, but does
**not** install anything automatically — even security patches sit pending
until you manually apply them. This folder documents closing that gap with
`unattended-upgrades`, scoped to security-only updates, verified against a
real backlog on this machine.

## Starting state

Before this was set up, `~/.linuxmint/mintupdate/updates.json` showed 8
security updates (bind9, curl, firefox, libheif, libvirt, thunderbird, vim,
wget) and 1 kernel update sitting unapplied for 3–5 days — Update Manager
had correctly detected them, they just hadn't been installed. This is the
actual risk Step 2 addresses: detection without action doesn't help.

## What this does

1. Installs `unattended-upgrades` and `needrestart`
2. Scopes automatic installation to **security updates only** — not general
   package upgrades, backports, or proposed packages — to minimize the
   chance of an unattended change breaking something on a daily-driver
   machine
3. Enables safe housekeeping (removing unused dependencies/old kernels)
   without enabling automatic reboots — a kernel update still requires you
   to reboot manually, so you're never caught off guard mid-work
4. Enables syslog logging so update activity is auditable the same way as
   the backup jobs (`grep` a distinct tag out of `/var/log/syslog`)

## Setup

```
sudo apt install unattended-upgrades needrestart
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Say yes to the prompt this raises ("Automatically download and install
stable updates?").

## Configuration

Check `/etc/apt/apt.conf.d/50unattended-upgrades`. On Ubuntu-based systems
(Mint inherits this), the default `Allowed-Origins` is already scoped
correctly out of the box — `-security` and ESM origins enabled,
`-updates`/`-proposed`/`-backports` left commented out. Worth confirming
rather than assuming:

```
grep -A 8 "Allowed-Origins" /etc/apt/apt.conf.d/50unattended-upgrades
```

Enable housekeeping, keep automatic reboots off, and turn on logging:

```
sudo sed -i 's|^//Unattended-Upgrade::Remove-Unused-Dependencies "false";|Unattended-Upgrade::Remove-Unused-Dependencies "true";|' /etc/apt/apt.conf.d/50unattended-upgrades
sudo sed -i 's|^//Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "false";|' /etc/apt/apt.conf.d/50unattended-upgrades
sudo sed -i 's|^// Unattended-Upgrade::SyslogEnable "false";|Unattended-Upgrade::SyslogEnable "true";|' /etc/apt/apt.conf.d/50unattended-upgrades
```

Confirm the edits landed:

```
grep -E "Automatic-Reboot|Remove-Unused-Dependencies|SyslogEnable" /etc/apt/apt.conf.d/50unattended-upgrades
```

## Clearing an existing backlog

If updates were already sitting pending (as they were here), apply them
once manually rather than waiting for the next scheduled unattended run:

```
mintupdate-cli list
sudo mintupdate-cli upgrade
```

## Verification

Dry-run to confirm the configuration works without making changes:

```
sudo unattended-upgrade --dry-run --debug
```

If the system is already fully patched, this will correctly report nothing
to install (`InstCount=0`) — that's success, not a failure to detect
anything. It may also show old, now-unused kernel packages queued for
cleanup under `Remove-Unused-Dependencies`.

Confirm no reboot is silently required:

```
sudo needrestart -b
```

Confirm the actual systemd timer driving daily unattended runs is enabled
and scheduled:

```
systemctl status apt-daily-upgrade.timer
systemctl list-timers apt-daily-upgrade.timer
```

## Verified working (2026-08-24)

Backlog of 8 security updates + 1 kernel update cleared manually.
`unattended-upgrades` installed, correctly scoped to security-only origins,
housekeeping and syslog logging enabled, automatic reboot deliberately left
off. `apt-daily-upgrade.timer` confirmed active and running on schedule
(fired within the last 2 hours of setup, next run within 24h).
