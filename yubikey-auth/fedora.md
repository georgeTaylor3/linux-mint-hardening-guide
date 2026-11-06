# YubiKey login, unlock, and sudo on Fedora (pam_u2f)

Tested on Fedora 44 KDE with Plasma Login Manager, authselect profile `local`, and pam-u2f 1.4.0.

## Result

`sudo`, text consoles, the lock screen, and the login screen require the account password and a YubiKey touch. The key prompt comes first. `su -` to root needs only the root password, because root has no key file (see Behavior).

## Differences from the Mint guide

- Fedora generates `system-auth` and `password-auth` with `authselect`. Manual edits to those files are overwritten, so the setup uses `authselect enable-feature` instead of `sed` edits.
- One command covers every service that includes the stack. The services cannot be enabled one at a time.
- `sudo` and `su` include `system-auth`. The lock screen (`kde`) and the login screen (`plasmalogin`) include `password-auth`.
- The root account is locked by default, so rescue mode has no login until a root password is set.

Check which stack a service includes:

    grep -n -E 'system-auth|password-auth' /etc/pam.d/sudo /etc/pam.d/kde /etc/pam.d/su /usr/lib/pam.d/plasmalogin

## Recovery path (set up before changing PAM)

1. Set a root password and store it in a password manager:

        sudo passwd root

2. Test rescue mode. At the GRUB menu press `e`, append `systemd.unit=rescue.target` to the `linux` line, and boot. Enter the disk passphrase, then the root password. A root shell opens. `exit` continues the boot.
3. Keep a root shell open on a text console while testing: press `Ctrl+Alt+F3`, log in, run `su -`, and leave it open.

## Setup

1. Install the module and the registration tool:

        sudo dnf install pam-u2f pamu2fcfg

2. Register the key. Plug in only that key and touch it when it blinks:

        mkdir -p ~/.config/Yubico
        pamu2fcfg > ~/.config/Yubico/u2f_keys
        chmod 0644 ~/.config/Yubico/u2f_keys
        restorecon -Rv ~/.config/Yubico

   Add a second key (plug in only that key):

        pamu2fcfg -n >> ~/.config/Yubico/u2f_keys

3. Back up the PAM configuration:

        sudo cp -a /etc/authselect /root/authselect-before-u2f
        sudo cp -a /etc/pam.d /root/pam.d-before-u2f

4. Enable password plus key:

        sudo authselect enable-feature with-pam-u2f-2fa

5. Optional hardening. Remove the fingerprint line if the laptop has no reader (`fprintd-list $USER` prints `No devices available`). Reject empty passwords after checking that no account has one (the `awk` command prints nothing when none do):

        sudo authselect disable-feature with-fingerprint
        sudo awk -F: '($2==""){print $1}' /etc/shadow
        sudo authselect enable-feature without-nullok

## Tests

1. `sudo -k; sudo whoami` with the key: touch prompt, password prompt, then `root`.
2. The same command without the key must fail. This test shows the key is enforced.
3. Lock the screen, unplug the key, and enter the correct password. The screen must stay locked.
4. At the login screen without the key, the correct password must be rejected.
5. A text console login on `Ctrl+Alt+F4` asks for the touch, then the password.
6. Rescue mode still accepts the root password.
7. `su -` accepts the root password with no touch prompt.

## Behavior

- `with-pam-u2f` (without `-2fa`) makes the key sufficient on its own and skips the password. This setup does not use it.
- The default `nouserok` skips the key check for an account with no key file, and also when the file cannot be read. `without-pam-u2f-nouserok` requires a key for every account, including root.
- Root has no key file, so `su -` skips the key check. Anyone with a shell on the account and the root password can become root without the key. `sudo -i` requires the key.
- The SELinux boolean `authlogin_yubikey` was off, and the key was enforced for `sudo`, the lock screen, and the login screen.
- The registration is tied to the hostname (`pam://hostname`). Register the key again after a rename.

## Rollback

From the root console or the rescue shell:

    authselect disable-feature with-pam-u2f-2fa

Restore the original files from the backups in `/root` if needed. From a live USB: unlock the disk, mount the root subvolume, and comment out the `pam_u2f.so` lines in `/etc/authselect/system-auth` and `/etc/authselect/password-auth`.
