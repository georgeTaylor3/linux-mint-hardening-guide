# Linux Mint Hardening Guide

A practical hardening plan for a Linux Mint daily-driver laptop — full-disk encryption, YubiKey-backed MFA, ransomware-resistant backups, and a locked-down network posture, without wrecking usability.

**This README is the plan.** Each step below is a short summary of what and why. Steps that have been fully implemented and tested link out to their own folder with the actual scripts, configs, and detailed how-to. Steps without a folder are planned but not yet built.

Written for a real-world setup: LUKS FDE already enabled, a YubiKey 5 NFC, a VPN used without exception, and a spare internal drive available for backups. Adapt the specifics (drive names, package manager) to your own hardware.

## Contents

- [Threat model](#threat-model)
- [Prerequisites](#prerequisites)
- [Step 1 — Backups first](#step-1--backups-first) ✅ implemented
- [Step 2 — Patch management](#step-2--patch-management) ✅ implemented
- [Step 3 — YubiKey-backed login and sudo](#step-3--yubikey-backed-login-and-sudo) ✅ implemented
- [Step 4 — Firewall and VPN kill switch](#step-4--firewall-and-vpn-kill-switch) ✅ implemented
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

## Step 1 — Backups first ✅ implemented

Full-disk encryption protects data at rest if the laptop is stolen. It does **nothing** against ransomware or a dying drive. Do this step before anything else.

**➡️ See [`backups/`](./backups/)** for the full implementation: a local (LUKS-encrypted, on-demand) + cloud (object storage, unattended via systemd) backup system using Restic, with repository secrets managed through a password manager CLI rather than stored on disk. Includes ready-to-adapt scripts and a full writeup of the design decisions and pitfalls hit along the way. Tested end-to-end, including a verified restore.

---

## Step 2 — Patch management ✅ implemented

Security patches, including kernel updates, need to actually land — not sit deferred by an overly conservative update policy or a laptop that's rarely rebooted.

**➡️ See [`patch-management/`](./patch-management/)** for the full implementation: `unattended-upgrades` scoped to security-only origins, verified against a real pending backlog on this machine, with automatic reboots deliberately left off and syslog logging enabled for auditability.

---

## Step 3 — YubiKey-backed login and sudo ✅ implemented

Extend hardware-backed MFA beyond just SSH commit signing to local `sudo`, screen unlock, and the initial login screen, using `pam_u2f`. Requires a verified recovery path before touching PAM — locking yourself out of an FDE + YubiKey box is a bad afternoon.

**➡️ See [`yubikey-auth/`](./yubikey-auth/)** for the full implementation: PAM U2F rules added to `sudo`, screen unlock, and the LightDM greeter, each tested individually in increasing order of risk — with a root password and GRUB recovery mode verified working *before* any PAM file was touched.

---

## Step 4 — Firewall and VPN kill switch ✅ implemented

Default-deny inbound via `ufw`, plus confirming the VPN's *Advanced* kill switch (not just the standard one) is actually enforcing "no traffic without an active VPN connection" as policy.

**➡️ See [`firewall-vpn/`](./firewall-vpn/)** for the full implementation: UFW default-deny with an audit of every listening service, `sshd` fully disabled (not just firewalled) after confirming it was unused, and Proton VPN's Advanced kill switch verified with a real disconnect test — not just a settings toggle. Also documents a real app bug hit along the way (a corrupted local config value silently crashing the VPN app on launch) and how it was diagnosed and fixed.

---

## Step 5 — Browser hardening

uBlock Origin, Enhanced Tracking Protection set to Strict, HTTPS-Only mode, and an audit of installed extensions.

*Planned — not yet implemented in this repo.*

---

## Step 6 — Application isolation

Flatpak for lower-trust apps (sandboxed via Bubblewrap), and reviewing/extending AppArmor coverage for high-exposure apps like the browser.

*Planned — not yet implemented in this repo.*

---

## Step 7 — Physical and firmware security

BIOS/UEFI password with USB boot locked down (protects the LUKS setup from an evil-maid attack), Secure Boot if supported, and TPM + PIN as a usability/security middle ground if available.

*Planned — not yet implemented in this repo.*

---

## Step 8 — Kernel and swap hardening

Confirming swap lives inside the LUKS container rather than an unencrypted partition, and applying a maintained sysctl hardening profile.

*Planned — not yet implemented in this repo.*

---

## Step 9 — Lightweight monitoring

`auditd` for local audit logging, periodic `rkhunter` scans.

*Planned — not yet implemented in this repo.*

---

## Ongoing maintenance

- **Quarterly:** test a backup restore, clear the `apt list --upgradable` backlog, review FIDO2 registrations on key accounts, prune unused Flatpaks/extensions.
- **Yearly:** re-evaluate this whole list — Secure Boot/TPM support, Wayland vs. X11 hardening posture, and Mint's own defaults all shift over time.

---

## Checklist summary

- [x] Local backup (LUKS-encrypted second drive, Restic, versioned) — see [`backups/`](./backups/)
- [x] Offsite backup leg configured and encrypted client-side — see [`backups/`](./backups/)
- [x] Backup restore tested successfully — see [`backups/`](./backups/)
- [x] `unattended-upgrades` installed and enabled — see [`patch-management/`](./patch-management/)
- [x] Security-only update scoping verified against a real backlog — see [`patch-management/`](./patch-management/)
- [x] YubiKey required for `sudo` (recovery path confirmed first) — see [`yubikey-auth/`](./yubikey-auth/)
- [x] YubiKey required for screen unlock — see [`yubikey-auth/`](./yubikey-auth/)
- [x] YubiKey required for initial login (greeter) — see [`yubikey-auth/`](./yubikey-auth/)
- [x] UFW enabled, default-deny inbound — see [`firewall-vpn/`](./firewall-vpn/)
- [x] Unused inbound services disabled, not just firewalled — see [`firewall-vpn/`](./firewall-vpn/)
- [x] VPN Advanced kill switch verified with a real disconnect test — see [`firewall-vpn/`](./firewall-vpn/)
- [ ] YubiKey registered as FIDO2/WebAuthn on key accounts
- [ ] Backup YubiKey registered and stored separately
- [ ] Browser hardened (uBlock Origin, strict tracking protection, HTTPS-Only)
- [ ] Flatpak available for lower-trust apps
- [ ] AppArmor profiles reviewed/extended
- [ ] BIOS/UEFI password set, USB boot locked down
- [ ] Secure Boot enabled (if supported)
- [ ] Swap confirmed inside LUKS container
- [ ] Quarterly maintenance reminder scheduled

## License

MIT — use, adapt, and share freely.
