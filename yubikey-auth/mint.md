# YubiKey-Backed Login, Unlock, and Sudo (PAM U2F)

This extends hardware-backed MFA — already used for SSH commit signing —
to every local authentication boundary: the initial login screen, screen
unlock, and `sudo`. All three now require a password **and** a physical
YubiKey touch.

## Why this matters more than it might seem

A password alone protects against someone who doesn't know it. It does
nothing against someone who's already watched you type it, or against
credential-stuffing if the same password (or a variant) is reused
elsewhere. Requiring a physical touch closes that gap for local access —
an attacker needs the physical key in hand, not just knowledge of a
string.

## Before touching PAM: establish a real recovery path first

**Do this before editing any PAM file.** A mistake in a PAM stack can lock
you out of `sudo`, screen unlock, or — worst case — the ability to log in
at all. There is no undo from inside a broken session.

Two things needed:

1. **A root password**, since Debian/Ubuntu-derived systems ship with the
   root account locked by default (no password, `passwd -S root` shows
   `L`). A locked root account means GRUB recovery mode's "drop to root
   shell" option will fail via `sulogin` rather than actually giving you a
   shell.

   ```
   sudo passwd -S root        # check current state
   sudo passwd root           # set one if it shows L
   ```

   Store this password in a password manager, not written down in plaintext.

2. **Actually test the recovery path before changing anything** — don't
   assume it'll work:

   - Reboot
   - At GRUB: **Advanced options → Recovery mode**
   - Confirm you're prompted for your disk encryption passphrase (expected,
     if the drive is LUKS-encrypted)
   - At the recovery menu: **root — Drop to root shell prompt**
   - Confirm you land in a working shell, not a `sulogin` failure

   Only proceed past this point once that's been verified to actually work.

## Setup

Install the PAM U2F module:

```
sudo apt install libpam-u2f
```

Register the YubiKey. This is a **separate credential type** from SSH
keys — a fresh registration is needed even if the same physical key is
already used for SSH signing:

```
mkdir -p ~/.config/Yubico
pamu2fcfg > ~/.config/Yubico/u2f_keys
```

Touch the YubiKey when prompted. Confirm the file has content:

```
cat ~/.config/Yubico/u2f_keys
```

## Adding the PAM rule — three separate files, three separate risk levels

Do these **one at a time**, testing each before moving to the next, and
without closing any already-open terminal until the current step is
confirmed working — an open session is a fallback if something breaks.

### 1. `sudo` (lowest risk — an open terminal is already your fallback)

```
sudo sed -i '1i auth required pam_u2f.so' /etc/pam.d/sudo
```

Test in a **new** terminal, keeping the current one open:

```
sudo -k
sudo whoami
```

Should prompt for a YubiKey touch, then the account password, before
returning `root`.

### 2. Screen unlock (`cinnamon-screensaver`, or your DE's equivalent)

```
sudo sed -i '1i auth required pam_u2f.so' /etc/pam.d/cinnamon-screensaver
```

Test by locking the screen and confirming the unlock prompt now also
requires a YubiKey touch.

### 3. The login greeter (highest risk — no already-open session covers this)

This is the file that gates the very first login prompt after boot, before
any session exists. Getting this wrong with no verified recovery path is
how a machine becomes unbootable-by-you. **Do not skip the recovery-path
verification above before this step.**

Check which PAM file the greeter actually uses — this varies by display
manager and Mint version:

```
ls /etc/pam.d/ | grep -i lightdm
```

For LightDM, the relevant file is `lightdm` (not `lightdm-autologin`,
which handles passwordless auto-login and shouldn't be touched unless
that's specifically what you're changing).

Insert the rule **after** the existing `pam_nologin.so` /
`nopasswdlogin` checks, not at the very top — those need to run first:

```
sudo sed -i '/@include common-auth/i auth    required        pam_u2f.so' /etc/pam.d/lightdm
```

**Test by logging out (not rebooting)** — this returns you to the actual
greeter without losing the ability to reboot into recovery mode if
something's wrong:

1. Log out normally
2. Enter your password at the greeter
3. Confirm you're prompted to touch the YubiKey before the session loads
4. Touch it, confirm you land on the desktop normally

If it fails: a raw TTY (`Ctrl+Alt+F3`) uses a separate, untouched PAM
stack (`/etc/pam.d/login`) and should still accept a password-only login,
giving a way back in without needing full GRUB recovery. If that also
fails, GRUB recovery mode (already verified working) gets you to a root
shell to revert:

```
sed -i '/pam_u2f.so/d' /etc/pam.d/lightdm
```

## What's still open

- **Online accounts** (GitHub, email, password manager, etc.) are a
  separate concern from local PAM — register the YubiKey as a FIDO2/
  WebAuthn factor on each individually if not already done. Local
  hardening here doesn't extend to those.
- **A second, backup YubiKey** stored separately isn't set up in this
  configuration. Losing the only registered key means losing access to
  everything gated by `pam_u2f.so` — the GRUB recovery path (still valid,
  since it doesn't go through PAM's U2F check) is the fallback in that
  case, but a second key is a more convenient safety net worth considering.

## Verified working (2026-08-24)

All three PAM files tested individually, in increasing order of risk, each
confirmed working before moving to the next:
- `sudo` — password + YubiKey touch required, tested via a fresh `sudo -k`
- Screen unlock — password + YubiKey touch required, tested by locking
  and unlocking
- LightDM greeter — password + YubiKey touch required, tested via a full
  logout/login cycle (not just a reboot, which wouldn't have proven the
  greeter path specifically)

Recovery path (root password + GRUB recovery mode) was set up and
verified working *before* any PAM file was modified.

## Enrolling a YubiKey for a second user (without them logging in first)

`scripts/enroll-yubikey.sh` registers a YubiKey for `pam_u2f` under a
specific user account, run by an already-authenticated admin — useful
when a second user can't log in yet because they have no key registered
at all (a chicken-and-egg problem: the greeter requires a key, but they
need to log in to register one).

    sudo ./scripts/enroll-yubikey.sh <target-username>

Insert the target user's YubiKey (only that key — unplug others to avoid
ambiguity about which one gets registered) and touch it when prompted.

### A real bug hit here, worth knowing about

The first version of this script ran `pamu2fcfg` as the target user via
`sudo -u <user>`, which seemed like the obviously-correct approach — the
resulting file needs to be owned by that user, after all. It failed
every time with `No device found`, despite `lsusb` clearly showing the
key plugged in.

The cause: `pamu2fcfg` needs live access to the YubiKey's HID/FIDO
interface (`/dev/hidraw*`). That access is normally granted temporarily
by `systemd-logind` to whichever user is actively logged into the
current seat — not to an arbitrary target user with no session. Since
the whole point of this script is enrolling a key for someone who
**can't** log in yet, running the enrollment command as that user always
fails this permission check, even though the physical key is right
there.

**The fix**: `pamu2fcfg` has a `-u`/`--username` flag exactly for this
scenario. Run it as **root** instead (root always has device access,
no seat ACL needed) and pass `-u <target-username>` to embed the correct
username in the output rather than relying on `whoami`. The script then
`chown`s the resulting file to the target user afterward.

**Takeaway for future similar scripts**: any command that needs live
hardware access (not just filesystem permissions) has to be evaluated
separately from "which user should own the resulting file" — those are
two different permission questions, and conflating them is an easy
mistake to make.
