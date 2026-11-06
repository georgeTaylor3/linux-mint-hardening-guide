# Browser Hardening (Brave)

Installs Brave via its official repository and enforces the settings that
matter most given this machine's threat model — chiefly WebRTC leak
protection, since WebRTC can expose your real IP even through an active
VPN tunnel if left on default settings, partially undermining the
Advanced kill switch work from [`firewall-vpn/`](../firewall-vpn/).

## Why Brave, and why not uBlock Origin too

Brave ships with built-in ad/tracker blocking (Shields), so a separate
extension for that would be redundant. The hardening here is about
Brave's own settings, most of which aren't safe defaults out of the box.

## Two settings enforced via managed policy, not just user preferences

Chromium-based browsers store most settings in a per-profile JSON
preferences file, which is only read at startup and can be reset by a
profile wipe or reinstall. For anything that actually matters, we instead
use Chromium's managed policy mechanism
(`/etc/brave/policies/managed/*.json`), which takes precedence over
user-set values and survives profile resets.

- **`WebRtcIPHandling`**: `disable_non_proxied_udp` — prevents WebRTC
  from leaking your real IP outside the VPN tunnel.
- **`HttpsOnlyMode`**: `force_enabled` — Brave's equivalent of Chrome's
  HTTPS-only mode, enforced rather than left as a togglable preference.

### A real bug hit setting this up

The first attempt used the policy key `WebRtcIPHandlingPolicy`. Brave's
own `brave://policy` page reported this as `Unknown policy` — a silently
ignored, do-nothing setting, despite the file being syntactically valid
JSON. The actual Chromium policy key has no "Policy" suffix — it's just
`WebRtcIPHandling`. Confirmed via Brave's own documentation
([Group Policy article](https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy))
and cross-referenced against Chrome's enterprise policy list.

**The lesson, worth repeating for future policy additions:** `brave://policy`
is the only reliable way to confirm a managed policy actually took
effect. A syntactically valid JSON file with a wrong key name fails
silently — no error at apply time, no error in logs, just a policy that
quietly does nothing. Always check this page after adding or changing a
managed policy.

## Installing Brave

```
sudo apt install curl gpg
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
    sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update
sudo apt install brave-browser
```

## Applying the managed policies

```
sudo mkdir -p /etc/brave/policies/managed
sudo tee /etc/brave/policies/managed/webrtc_leak_protection.json << 'EOF'
{
  "WebRtcIPHandling": "disable_non_proxied_udp"
}
EOF
sudo tee /etc/brave/policies/managed/https_only.json << 'EOF'
{
  "HttpsOnlyMode": "force_enabled"
}
EOF
```

Restart Brave, then verify at `brave://policy` — both should show status
**OK**, not an error.

## Manual settings (per-preference, not enforced by policy)

These are lower-stakes user preferences, done once in the UI:

1. `brave://settings/shields` — set Trackers & ads blocking to Aggressive
2. `brave://settings/shields` — set Block fingerprinting to Standard or Strict
3. `brave://settings/privacy` — turn off "Use Google services for push messaging"
4. `brave://settings/privacy` — turn off Brave's P3A/product analytics
5. `brave://settings/privacy` — set cookies to block third-party
6. `brave://settings/extensions` — audit installed extensions, remove anything unused
7. Disable unused built-in features: Brave Rewards, Brave Wallet, Brave News

## Testing the WebRTC fix actually works

Don't trust the policy status alone — verify the real-world effect:

1. Connect to the VPN
2. Visit a WebRTC leak test site (search "WebRTC leak test")
3. Confirm your real IP does **not** appear alongside the VPN's IP in the results

## Verified working (2026-08-24)

`HttpsOnlyMode` and `WebRtcIPHandling` both confirmed `OK` at
`brave://policy` after correcting the policy key name. Brave installed
via the official repository.
