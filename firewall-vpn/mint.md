# Firewall (UFW) and VPN Kill Switch

Default-deny inbound networking, sshd fully disabled (not just firewalled),
and a verified — not just toggled — VPN kill switch that provably drops
all traffic when the tunnel isn't up.

## UFW: default-deny inbound

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

Verify:

```
sudo ufw status verbose
```

Should show `deny (incoming), allow (outgoing)`. This only blocks
**unsolicited inbound** connection attempts — a stateful firewall tracks
connections your machine initiates, so outbound traffic (browsing, `git`,
outbound SSH tunnels) and the return traffic on those connections is
unaffected. Nothing needs an explicit outbound rule for normal use.

### Audit what's actually listening before deciding on inbound rules

```
sudo ss -tlnp
```

Anything bound to `127.0.0.1` or `::1` only is already unreachable from
outside regardless of firewall rules. Anything bound to `0.0.0.0` or `[::]`
is a real inbound-reachable service, worth a deliberate decision:

- **Not needed** → don't just firewall it, disable the service entirely.
  A firewall rule is one layer; a disabled service removes the attack
  surface even if the firewall is ever misconfigured later.
- **Actively used** (e.g. local VM networking via libvirt/dnsmasq) → leave
  it alone; it's usually already scoped to a specific virtual interface,
  not globally reachable.

### Disabling an unneeded inbound service (example: SSH server)

If you never need to SSH *into* this machine (only *out*, e.g. cloud
tunnels), disable the daemon rather than just firewalling the port:

```
sudo systemctl disable --now ssh
```

Watch for a note about a triggering socket unit still being active —
modern systemd often uses **socket activation**, where a separate
`.socket` unit holds the listening port and starts the service on demand
even if the service itself is marked disabled:

```
sudo systemctl disable --now ssh.socket
```

Verify both are gone:

```
sudo ss -tlnp | grep :22
sudo systemctl status ssh.socket ssh.service
```

This does **not** affect the SSH *client* — outbound `ssh`, `git` over
SSH, or cloud tunnel tooling (e.g. GCP IAP tunnels) are a completely
separate program from the server daemon and are unaffected by disabling
`sshd`.

## VPN kill switch: verify, don't trust the toggle

A kill switch setting that "looks enabled" isn't proof it works. Test it
by actually cutting the connection and confirming traffic really stops.

### Standard vs. Advanced

- **Standard**: only engages on an *accidental* drop. A deliberate
  disconnect, or the app itself crashing/exiting, leaves you unprotected
  with no warning.
- **Advanced** (sometimes called "Permanent"): blocks all traffic — in
  and out — unless the VPN is actively connected, full stop, including
  after a deliberate disconnect or a reboot. Not compatible with split
  tunneling.

If the goal is "VPN without exception," Advanced is the only mode that
actually enforces that as policy rather than as a best-effort default.

### Enabling it (Proton VPN Linux GUI)

Settings → Features → Kill Switch → toggle on → select **Advanced**.

### Actually testing it

Connect to a server first — with Advanced kill switch on, no traffic
(including to reach the VPN itself) is possible without an active
connection:

```
curl ifconfig.me
```

Should show the VPN's IP, not your ISP's.

Then disconnect (via the app, a deliberate action — this is exactly the
scenario Standard mode would *not* protect against) and retest
immediately:

```
curl ifconfig.me --max-time 5
```

A working Advanced kill switch fails this completely — not a fallback to
your real IP, not a generic connection error, but a full resolution
failure (`curl: (6) Could not resolve host`), since even DNS is blocked.
That's the actual proof: nothing leaks, not even a DNS query.

Reconnect and reconfirm normal access afterward:

```
curl ifconfig.me
```

## A real bug hit along the way: Proton VPN GTK app silent-crash-on-launch

Worth documenting since it cost real debugging time and had nothing to do
with the firewall or VPN itself — a corrupted local app setting caused the
GUI to silently fail on every launch, misleadingly presenting as a generic
"no server available in the current tier" dialog.

**Symptom:** launching the app shows a "no server available in the
current tier" dialog, or the window never appears at all (exists per the
window manager but stays permanently unmapped).

**Root cause:** `~/.config/Proton/VPN/app-config.json` had
`"connect_at_app_startup"` set to a non-empty, non-country-code string
(in this case, the literal text `"ON"`, evidently corrupted or
mis-written by a previous app version). The app's startup logic checks
this field for Python *truthiness*, not for a specific sentinel value —
`"ON"`, `"OFF"`, or any other non-empty string all evaluate as "yes,
autoconnect," and the app then tries to treat that string as a country
code, fails to match anything, and throws an unhandled exception before
the main window ever finishes initializing.

**Fix:** set the field to a genuinely empty string, which is the only
value the app's own source code treats as "disabled":

```
sed -i 's/"connect_at_app_startup": "ON"/"connect_at_app_startup": ""/' ~/.config/Proton/VPN/app-config.json
```

(Adjust the matched value to whatever the file currently shows —
`"OFF"` doesn't work either; only an empty string does.)

If you also want the window to launch visibly rather than start
minimized while debugging:

```
sed -i 's/"start_app_minimized": true/"start_app_minimized": false/' ~/.config/Proton/VPN/app-config.json
```

## Ruling things out methodically

Two other real issues surfaced during this session that turned out to be
unrelated to the firewall/VPN work, but were worth investigating properly
given the stakes (this session also touched login-gating PAM changes):

- **SSH agent losing its socket** after a reboot — resolved by explicitly
  pointing `SSH_AUTH_SOCK` at the still-live gnome-keyring socket
  (`/run/user/1000/keyring/ssh`), a known category of session-environment
  propagation issue, unrelated to firewall or PAM changes.
- **A previously-registered SSH Authentication Key disappearing from
  GitHub** — confirmed via GitHub's own SSH keys settings page, unrelated
  to anything local; re-adding the key resolved it.

Neither was actually caused by the UFW or kill switch work — both were
ruled out methodically (checking USB/hardware state, agent state, and the
remote GitHub-side configuration directly) before concluding so, rather
than assumed.

## Verified working (2026-08-24)

- UFW active, default-deny incoming confirmed via `ufw status verbose`
- `sshd` confirmed fully stopped at both the service and socket level
- Outbound SSH (GitHub, cloud tunnels) confirmed still functional
- Proton VPN Advanced kill switch confirmed via an actual disconnect test:
  complete DNS resolution failure with the VPN down, full connectivity
  restored on reconnect
