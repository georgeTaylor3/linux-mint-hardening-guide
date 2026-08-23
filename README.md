# Linux Mint Hardening Guide

A practical, step-by-step checklist for hardening a Linux Mint daily-driver laptop — full-disk encryption, YubiKey-backed MFA, ransomware-resistant backups, and a locked-down network posture, without wrecking usability.

Written for a real-world setup: LUKS FDE already enabled, a YubiKey 5 NFC, a VPN used without exception, and a spare internal drive available for backups. Adapt the specifics (drive names, package manager) to your own hardware.

## Contents

- [Threat model](#threat-model)
- [Prerequisites](#prerequisites)
- [Step 1 — Backups first](#step-1--backups-first)
- [Step 2 — Patch management](#step-2--patch-management)
- [Step 3 — YubiKey-backed login and sudo](#step-3--yubikey-backed-login-and-sudo)
- [Step 4 — Firewall and VPN kill switch](#step-4--firewall-and-vpn-kill-switch)
- [Step 5 — Browser hardening](#step-5--browser-hardening)
- [Step 6 — Application isolation](#step-6--application-isolation)
- [Step 7 — Physical and firmware security](#step-7--physical-and-firmware-security)
- [Step 8 — Kernel and swap hardening](#step-8--kernel-and-swap-hardening)
- [Step 9 — Lightweight monitoring](#step-9--lightweight-monitoring)
- [Ongoing maintenance](#ongoing-maintenance)
- [Checklist summary](#checklist-summary)

## Threat model

Ranked by realistic likelihood for a personal/work daily driver, not a targeted-nation-state scenario:

1. Ransomware or opportunistic malware (malicious downloads, browser exploits, bad packages)
2. Drive failure
3. Theft or loss of the physical device
4. Phishing / credential theft against online accounts
5. Targeted network attacks (lowest likelihood; mitigated by VPN + firewall)

This guide is weighted accordingly: backups and account/credential hardening get equal priority to OS-level controls, because full-disk encryption alone does not protect against #1 or #2.

## Prerequisites

- Linux Mint with LUKS full-disk encryption already enabled on the primary drive
- A YubiKey 5 (NFC or USB) — for hardware-backed MFA
- A VPN with a working kill switch (this guide assumes ProtonVPN, but the steps generalize)
- A spare internal or external drive for local backups
- An account with sudo access

---

## Step 1 — Backups first

Full-disk encryption protects data at rest if the laptop is stolen. It does **nothing** against ransomware or a dying drive. Do this step before anything else.

**Why not `rsync`/`cp`:** a plain mirror backup faithfully copies ransomware-encrypted files right over your good backups. Use a versioned, deduplicating tool instead.

1. Install a backup tool:
   ```bash
   sudo apt install borgbackup
   # or: sudo apt install restic
   ```
2. Encrypt and prepare the spare drive:
   ```bash
   sudo cryptsetup luksFormat /dev/sdX1
   sudo cryptsetup open /dev/sdX1 backup-drive
   sudo mkfs.ext4 /dev/mapper/backup-drive
   sudo mkdir /mnt/backup && sudo mount /dev/mapper/backup-drive /mnt/backup
   ```
3. Initialize a local repository (Borg example):
   ```bash
   borg init --encryption=repokey /mnt/backup/borg-repo
   ```
4. Add an offsite leg — a cloud target such as Backblaze B2 via Restic or `rclone`, encrypted client-side. A few dollars a month covers most home-directory-sized backups.
5. Automate it with a `systemd` timer (preferred over cron — easier to inspect with `systemctl status`):
   ```bash
   sudo systemctl edit --force --full backup.service
   sudo systemctl edit --force --full backup.timer
   sudo systemctl enable --now backup.timer
   ```
6. Set a retention policy, e.g. daily×7, weekly×4, monthly×6:
   ```bash
   borg prune --keep-daily=7 --keep-weekly=4 --keep-monthly=6 /mnt/backup/borg-repo
   ```
7. **Test a restore now**, not after you need it:
   ```bash
   borg extract /mnt/backup/borg-repo::<archive-name>
   ```
8. Optional but strong: enable Object Lock on your cloud backend (e.g. B2). This makes backups undeletable/unoverwritable for a set period — a compromised laptop cannot destroy them even with valid credentials.

**Verification:** confirm a scheduled run actually happened (`systemctl status backup.timer`) and that a restored file matches the original.

---

## Step 2 — Patch management

1. Raise Mint's update level so security patches, including kernel updates, aren't silently deferred: **Update Manager → Edit → Update levels**.
2. Install unattended security updates:
   ```bash
   sudo apt install unattended-upgrades needrestart
   sudo dpkg-reconfigure --priority=low unattended-upgrades
   ```
3. Reboot after kernel updates — `needrestart` will flag when one is pending.

**Verification:** `cat /etc/apt/apt.conf.d/20auto-upgrades` shows updates enabled; `needrestart -b` reports no pending kernel restart after a reboot.

---

## Step 3 — YubiKey-backed login and sudo

**Set up a recovery path before touching PAM.** Locking yourself out of an FDE + YubiKey box is a bad afternoon — keep a second registered key or a documented fallback.

1. Install the PAM module:
   ```bash
   sudo apt install libpam-u2f
   ```
2. Register your key:
   ```bash
   mkdir -p ~/.config/Yubico
   pamu2fcfg > ~/.config/Yubico/u2f_keys
   ```
3. Require it for `sudo` — add this line near the top of `/etc/pam.d/sudo`:
   ```
   auth required pam_u2f.so
   ```
4. Optionally require it at the lock screen (`/etc/pam.d/cinnamon-screensaver`) once step 3 is confirmed working.
5. Register the YubiKey as a **FIDO2/WebAuthn** factor (not just TOTP) on your important accounts — GitHub, Google, your password manager. WebAuthn is phishing-resistant; TOTP isn't.
6. Buy or plan for a second YubiKey, registered as backup, stored somewhere other than your bag.

**Verification:** open a new terminal and run `sudo -k && sudo whoami` — you should be prompted to touch the YubiKey.

---

## Step 4 — Firewall and VPN kill switch

1. Default-deny inbound:
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw enable
   ```
2. In your VPN client, confirm the **permanent** kill switch is on (survives reboots/crashes), not just the standard one.
3. Enable DNS leak protection in the same settings pane.

**Verification:**
```bash
sudo ufw status verbose
```
Kill the VPN process and run `curl ifconfig.me` — it should fail closed, not fall back to your real IP. Cross-check with any DNS-leak-test site.

---

## Step 5 — Browser hardening

1. Install `uBlock Origin`.
2. Enable Enhanced Tracking Protection → Strict (Firefox) or the equivalent.
3. Enable HTTPS-Only mode.
4. Consider Firefox Multi-Account Containers to separate work/personal sessions.
5. Audit installed extensions — remove anything you don't actively use.

**Verification:** visit a tracker-test page (e.g. a browser privacy checker) and confirm blocking is active.

---

## Step 6 — Application isolation

1. Prefer Flatpak for less-trusted apps — sandboxed via Bubblewrap:
   ```bash
   sudo apt install flatpak
   ```
2. Check AppArmor coverage and extend it:
   ```bash
   sudo aa-status
   sudo apt install apparmor-profiles apparmor-profiles-extra
   ```
3. Avoid piping installer scripts straight into `bash` as root without reading them first.

**Verification:** `sudo aa-status` shows enforced profiles for your browser and other high-exposure apps.

---

## Step 7 — Physical and firmware security

1. Set a BIOS/UEFI password and lock the boot order so USB boot requires it — otherwise someone with physical access can boot alternate media and attack the LUKS setup before your passphrase is ever entered.
2. Confirm Secure Boot is enabled in BIOS setup if your hardware supports it.
3. Check for a TPM:
   ```bash
   sudo dmesg | grep -i tpm
   ```
   If present, TPM + PIN unlock is a reasonable usability/security middle ground — pure TPM-only unlock (no passphrase) weakens resistance to physical-access attacks.

**Verification:** attempt to boot from a USB stick — it should be blocked without the BIOS password.

---

## Step 8 — Kernel and swap hardening

1. Confirm swap lives inside the LUKS container, not on an unencrypted partition:
   ```bash
   lsblk
   cat /etc/crypttab
   ```
2. Review current hardening posture and apply a maintained sysctl profile rather than hand-rolling one from scratch.

**Verification:** `lsblk` shows the swap device nested under the LUKS mapper, not as a bare partition.

---

## Step 9 — Lightweight monitoring

1. Optional: enable `auditd` for local audit logging.
2. Optional: schedule periodic rootkit scans:
   ```bash
   sudo apt install rkhunter
   sudo rkhunter --check
   ```

**Verification:** `sudo systemctl status auditd` (if installed) shows active and logging.

---

## Ongoing maintenance

- **Quarterly:** test a backup restore, clear the `apt list --upgradable` backlog, review FIDO2 registrations on key accounts, prune unused Flatpaks/extensions.
- **Yearly:** re-evaluate this whole list — Secure Boot/TPM support, Wayland vs. X11 hardening posture, and Mint's own defaults all shift over time.

---

## Checklist summary

- [ ] Local backup (LUKS-encrypted second drive, Borg/Restic, versioned)
- [ ] Offsite backup leg configured and encrypted client-side
- [ ] Backup restore tested successfully
- [ ] `unattended-upgrades` installed and enabled
- [ ] Mint update level raised past the most conservative setting
- [ ] YubiKey required for `sudo` (recovery path confirmed first)
- [ ] YubiKey registered as FIDO2/WebAuthn on key accounts
- [ ] Backup YubiKey registered and stored separately
- [ ] UFW enabled, default-deny inbound
- [ ] VPN permanent kill switch + DNS leak protection confirmed
- [ ] Browser hardened (uBlock Origin, strict tracking protection, HTTPS-Only)
- [ ] Flatpak available for lower-trust apps
- [ ] AppArmor profiles reviewed/extended
- [ ] BIOS/UEFI password set, USB boot locked down
- [ ] Secure Boot enabled (if supported)
- [ ] Swap confirmed inside LUKS container
- [ ] Quarterly maintenance reminder scheduled

## License

MIT — use, adapt, and share freely.
