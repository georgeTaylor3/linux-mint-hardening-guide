# Patch Management: Unattended Updates

Linux Mint's Update Manager checks for updates and notifies you, but does
**not** install anything automatically — even security patches sit pending
until you manually apply them. This folder documents closing that gap with
`unattended-upgrades`, covering Ubuntu security and bug-fix updates plus
the Mint, Brave, Proton VPN, and VS Code repositories.

## Starting state

Before this was set up, `~/.linuxmint/mintupdate/updates.json` showed 8
security updates (bind9, curl, firefox, libheif, libvirt, thunderbird, vim,
wget) and 1 kernel update sitting unapplied for 3–5 days — Update Manager
had correctly detected them, they just hadn't been installed. This is the
actual risk Step 2 addresses: detection without action doesn't help.

## What this does

1. Installs `unattended-upgrades` and `needrestart`
2. Allows automatic installation from Ubuntu `noble-security` and
   `noble-updates`, Mint's `zena` repository, and the Brave, Proton VPN,
   and VS Code repositories. `-proposed` and `-backports` stay excluded.
   The Google Cloud CLI and the neovim nightly PPA are updated by hand.
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

### Allowed origins on Mint

The stock `50unattended-upgrades` builds `Allowed-Origins` from the
distribution ID and codename. On Ubuntu these expand to
`Ubuntu:noble-security` and similar. On Mint they expand to
`Linuxmint:zena`, `Linuxmint:zena-security`, and two `LinuxmintESM`
entries, which match none of the repositories on the system:

- Ubuntu packages, which include most security fixes and the kernel, carry
  the origin `Ubuntu`.
- Mint's repository uses the origin `linuxmint` in lowercase, and the match
  is case-sensitive.
- There is no `zena-security` repository; Mint security fixes come through
  Ubuntu.

With the stock file, every run logs `No packages found that can be upgraded
unattended` while updates accumulate.

List the origins your repositories publish:

```
apt-cache policy | grep -o 'o=[^,]*,a=[^,]*' | sort -u
```

Add the missing origins in a separate file, so a package upgrade that
replaces `50unattended-upgrades` does not remove them:

```
sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-mint >/dev/null <<'EOF'
// Linux Mint 22.x (Ubuntu noble base). The stock Allowed-Origins expand to
// "Linuxmint:zena", which matches neither the Ubuntu repositories nor the
// "linuxmint" origin. Update "noble" and "zena" when moving to Mint 23.
// Left for manual updates: google-cloud-cli, neovim (nightly PPA).
Unattended-Upgrade::Origins-Pattern {
        "origin=Ubuntu,archive=noble-security";
        "origin=Ubuntu,archive=noble-updates";
        "origin=linuxmint,archive=zena";
        "origin=Brave Software,archive=stable";
        "origin=proton-gitlab,codename=stable,site=repo.protonvpn.com";
        "origin=code stable,archive=stable";
};
EOF
apt-config dump | grep 'Origins-Pattern::'
```

Notes:

- Proton's repository publishes an origin (`proton-gitlab`) and a codename
  (`stable`) but no archive, so its pattern matches on codename and site.
  Find the values for any repository with
  `apt-cache policy | grep -B1 -A2 -i <name>`.
- Remove the lines for applications you don't install. A pattern that
  matches no repository has no effect.
- Mint 23 moves to a new Ubuntu base. Update `noble` and `zena` when
  upgrading.

### Housekeeping, reboots, and logging

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
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -E 'Allowed origins|Packages that will be upgraded|No packages found'
```

`No packages found` is a pass only when nothing is pending. Compare it
against what apt reports:

```
apt list --upgradable 2>/dev/null | tail -n +2
```

If apt lists packages from an allowed repository, such as `noble-security`,
and the dry run reports none, the origins do not match. See "Allowed origins
on Mint" above.

Confirm no reboot is silently required:

```
sudo needrestart -b
```

Confirm the systemd timer driving daily unattended runs is enabled and
scheduled:

```
systemctl status apt-daily-upgrade.timer
systemctl list-timers apt-daily-upgrade.timer
```

The day after setup, confirm the scheduled run completed:

```
sudo tail -n 3 /var/log/unattended-upgrades/unattended-upgrades.log
```

The last line should be `All upgrades installed` or `No packages found that
can be upgraded unattended`.

## Verified working (2026-08-24)

Backlog of 8 security updates + 1 kernel update cleared manually.
`unattended-upgrades` installed, correctly scoped to security-only origins,
housekeeping and syslog logging enabled, automatic reboot deliberately left
off. `apt-daily-upgrade.timer` confirmed active and running on schedule
(fired within the last 2 hours of setup, next run within 24h).

## Correction (2026-10-17)

The 2026-08-24 configuration installed nothing. The stock origins expand to
`Linuxmint:zena` on Mint (see "Allowed origins on Mint"), so each scheduled
run logged `No packages found` while 61 updates accumulated, 39 of them from
`noble-security`. The empty dry run was read as a pass.

Fix: `51unattended-upgrades-mint` adds the Ubuntu, Mint, Brave, Proton VPN,
and VS Code origins, and the scope now includes `noble-updates`. After the
change, the dry run listed 57 packages. A manual run installed them and
logged `All upgrades installed`, and a reboot cleared `reboot-required`. A
second run installed the Brave, VS Code, and Proton VPN updates.
