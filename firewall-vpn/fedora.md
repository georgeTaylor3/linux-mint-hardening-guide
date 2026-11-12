# Firewall and VPN on Fedora

Tested on Fedora 44 KDE with firewalld and NetworkManager.

## Result

Inbound connections are rejected unless a service in the zone allows them. The default zone allows DHCPv6 replies and Samba client name replies. The home zone adds mDNS. Outbound traffic and replies to outbound connections are not affected.

## Differences from the Mint guide

- Mint uses `ufw` with default deny incoming and allow outgoing. Fedora uses firewalld, where each network connection belongs to one zone. Do not run `ufw` and firewalld together.
- The default zone, `FedoraWorkstation`, rejects unsolicited packets to ports 1 to 1024 and accepts every TCP and UDP port from 1025 to 65535. A program that listens on a high port is reachable from the network: KDE Connect (ports 1714 to 1764), a development server, or a container with a published port. This guide removes that range.
- Mint disables the SSH server. On Fedora the `ssh` service is removed from the zones, and `sshd` is off unless enabled.

## Zones after the change

| Zone | Used by | Services |
|---|---|---|
| `FedoraWorkstation` (default) | A connection with no zone assigned | `dhcpv6-client`, `samba-client` |
| `home` | A connection assigned with `nmcli` | `dhcpv6-client`, `mdns`, `samba-client` |

Neither zone has ports. A new or unknown network falls into the default zone, so it gets the stricter rules. Printer discovery over mDNS needs the `mdns` service, which only the `home` zone has.

## Setup

1. Back up the firewalld configuration:

        sudo cp -a /etc/firewalld /root/firewalld-before

2. Remove the port range and the `ssh` service, then reload:

        sudo firewall-cmd --permanent --zone=FedoraWorkstation --remove-port=1025-65535/tcp
        sudo firewall-cmd --permanent --zone=FedoraWorkstation --remove-port=1025-65535/udp
        sudo firewall-cmd --permanent --zone=FedoraWorkstation --remove-service=ssh
        sudo firewall-cmd --permanent --zone=home --remove-service=ssh
        sudo firewall-cmd --reload

3. Assign the trusted network to the `home` zone. This is the only command that binds a connection to a zone:

        nmcli connection modify "NAME" connection.zone home
        nmcli connection up "NAME"

4. Check the saved and the running configuration:

        sudo firewall-cmd --get-active-zones
        sudo firewall-cmd --permanent --zone=FedoraWorkstation --list-all
        sudo firewall-cmd --permanent --zone=home --list-all

The saved listings show no ports and no `ssh`.

To allow KDE Connect on the home network only:

        sudo firewall-cmd --permanent --zone=home --add-service=kdeconnect
        sudo firewall-cmd --reload

## Tests

A closed port and a blocked port look the same from the other machine. The control below shows that the test can return `True`, so a `False` means the firewall blocked the connection.

1. On the laptop, list what listens and start a test server on an empty folder:

        ss -tlnp
        cd "$(mktemp -d)" && python3 -m http.server 8000

2. On another machine on the same network (Windows PowerShell shown), with the laptop's address:

        Test-NetConnection -ComputerName ADDRESS -Port 8000 -InformationLevel Quiet

   The result is `False`, because no rule allows port 8000.

3. On the laptop, open the port for five minutes. The rule removes itself:

        sudo firewall-cmd --zone=home --add-port=8000/tcp --timeout=300

   The same test now returns `True`. After the rule closes, it returns `False` again.

4. Test a listening service that must be blocked, for example port 1716 with KDE Connect running. The result is `False`.

`Test-NetConnection` checks TCP only. UDP is covered by the zone listing, not by this test.

## Pitfalls

- `firewall-cmd --runtime-to-permanent` writes every zone to `/etc/firewalld/zones`. It wrote twelve files, and the saved `FedoraWorkstation` zone still listed the port range afterward. Use `--permanent` for each change and check `--permanent --list-all`.
- A file in `/etc/firewalld/zones` overrides the copy that ships in `/usr/lib/firewalld/zones`, so package updates do not change that zone. Remove the files of zones you did not change.
- Each `--permanent` change rewrites `FedoraWorkstation.xml.old` with the version from before that change only. The backup from step 1 holds the original.
- On an interface that NetworkManager controls, `firewall-cmd --permanent --add-interface` and `--remove-interface` rewrite the connection profile and reset its zone to the default. The message is "The interface is under control of NetworkManager, setting zone to default." Use `nmcli` to assign a zone.
- `/etc/firewalld/zones` is readable by root only. Use `sudo` for `ls` and `grep` there.

## Rollback

        sudo rm /etc/firewalld/zones/FedoraWorkstation.xml /etc/firewalld/zones/home.xml
        sudo cp -a /root/firewalld-before/zones/. /etc/firewalld/zones/
        sudo nmcli connection modify "NAME" connection.zone ""
        sudo firewall-cmd --reload
        nmcli connection up "NAME"

This restores the original `FedoraWorkstation` zone, including the open port range.

## VPN (Proton VPN command-line client)

This section uses Proton's command-line client, `proton-vpn-cli`, from Proton's Fedora repository. The Mint guide uses the GUI app and its Advanced kill switch. Proton lists the GUI app as officially supported on Fedora with GNOME, and KDE support is limited.

Tested on Fedora 44 KDE with `proton-vpn-cli` 1.1.0 over WireGuard.

### What a connection adds

- A NetworkManager connection of type `wireguard` with the interface `proton0`.
- Two policy-routing rules: `suppress_prefixlength 0` on the main table, and a rule that sends unmarked packets to a table whose default route is `proton0`. On the tested laptop the mark was `0xea13b2c` and the table was `245447468`. The rule priorities change between connections.
- Two nftables tables from NetworkManager, `ip nm-wg-proton0` and `ip6 nm-wg-proton0`.
- The VPN interface becomes the default DNS route.
- During the connect, the client adds a temporary dummy connection `pvpn-killswitch` on the device `pvpnksintrf0`, which NetworkManager makes the default for IPv4 and IPv6 routing and DNS. The client deletes it about 0.8 seconds later, after the tunnel and `pvpn-killswitch-ipv6` are up. It exists with the kill switch off.
- A dummy connection `pvpn-killswitch-ipv6` on the device `ipv6leakintrf0`, with an IPv6 default route through that device. It exists with the kill switch off. `protonvpn status` adds a second profile of that name if the dummy was deactivated by hand while the tunnel is up.
- The VPN interfaces join the default firewalld zone, which has no open ports. The Wi-Fi stays in its own zone, and the home subnet stays on the Wi-Fi.

A disconnect removes the rules, the tables, and the dummy connection, and leaves no saved profile.

### Install

The role in `roles/firewall_vpn` does these steps. The manual equivalent:

1. Download the repository package. The file name has a version, which Proton's Fedora page lists (1.0.5-1 at the time of writing):

        wget "https://repo.protonvpn.com/fedora-$(cat /etc/fedora-release | cut -d' ' -f 3)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.5-1.noarch.rpm"

2. Print the signing key's fingerprint and compare it with the figure on Proton's page at protonvpn.com. Each Fedora release has its own key. The Fedora 44 fingerprint is `6929 133B DE1C E1CF A9ED  B286 D841 76F6 8448 30D4`:

        curl -s https://repo.protonvpn.com/fedora-44-stable/public_key.asc | gpg --show-keys --with-fingerprint

3. Install the repository package, then list what the client pulls before installing it:

        sudo dnf install ./protonvpn-stable-release-1.0.5-1.noarch.rpm
        sudo dnf install --assumeno proton-vpn-cli

4. Install the client. `dnf` asks to import the key. Compare the fingerprint again before answering `y`:

        sudo dnf install proton-vpn-cli

The install on the tested laptop pulled 71 packages. `proton-vpn-cli` requires `proton-vpn-daemon`, which requires `python3-bcc`. `bcc` recommends `kernel-devel` and `bcc-tools`, and `dnf` installs weak dependencies by default, so a compiler toolchain (`gcc`, `make`, kernel headers) came with them. The client connected with the helper off. Whether it works without `kernel-devel` and `bcc-tools` is untested.

### Split-tunneling helper

`proton-vpn-daemon` installs `me.proton.vpn.split_tunneling.service`, a root service that the package's post-install script enables and starts. The command-line client has no split-tunneling setting, and a connection succeeds with the helper off. `protonvpn connect` prints `Split tunneling backend not found` and continues.

A start condition keeps the helper from starting. A mask would make the post-install `systemctl start` fail on each upgrade of the package:

        sudo mkdir -p /etc/systemd/system/me.proton.vpn.split_tunneling.service.d
        printf '[Unit]\nConditionPathExists=/etc/proton-vpn-split-tunneling.enabled\n' | sudo tee /etc/systemd/system/me.proton.vpn.split_tunneling.service.d/10-disabled.conf
        sudo systemctl daemon-reload
        sudo systemctl stop me.proton.vpn.split_tunneling.service

With the drop-in in place, `systemctl start` and `systemctl enable` on the unit both exit 0 and the unit stays inactive. To enable the helper again, delete the drop-in, run `sudo systemctl daemon-reload`, and start the unit.

### Sign in, connect, disconnect

        protonvpn signin USERNAME
        protonvpn connect
        protonvpn status
        protonvpn disconnect

- The password goes at a hidden prompt. With a security key on the account, the client asks for the key's PIN and a button press next. `protonvpn signin USERNAME --totp` uses an authenticator code instead.
- `protonvpn connect` with no argument picks the fastest server, so the server changes between connections. `--country` and `--city` narrow the choice.
- The address that `connect` prints can differ from the exit address. Read the exit address with `curl -4 -s https://ifconfig.me`.
- The verbose option `-v` prints the home public address and an API identifier. Mask the output before sharing it.
- No auto-connect setting appears in `protonvpn config list`. Whether the VPN reconnects after a boot is untested.

### Kill switch

`protonvpn config set kill-switch` accepts `off` and `standard`. The help text says `standard` blocks the internet if the VPN drops during an active connection and restores it after a disconnect that you request. The client refuses to change the setting while connected, so run `protonvpn disconnect` first. Proton lists the Advanced kill switch for the GUI app only, and the command-line client has no permanent mode.

This guide runs with the kill switch `off`. If the VPN connection is removed, traffic returns to the Wi-Fi and leaves with the home address, with no block and no warning. Check `protonvpn status` before using an untrusted network.

The package `python3-proton-vpn-api-core` ships `proton-vpn-kill-switch-boot.service`, disabled. Do not enable it by hand.

If a kill switch blocks the network, run these from another connection:

        protonvpn disconnect
        protonvpn config set kill-switch off
        sudo python3 -I -m proton.vpn.killswitch.disable
        sudo nft list tables

The module turns off the kill switch and the IPv6 leak protection of every backend. The package's removal scripts do not run it, so run it before removing the package. With no kill switch enabled it exits 0 and changes nothing. Its effect on an active kill switch is untested.

### Network lost after a cancelled connect

A connect that is cancelled or crashes while the temporary `pvpn-killswitch` connection exists leaves the laptop with no network, because that connection stays the default route and DNS for IPv4 and IPv6. In a test that killed the client with `SIGKILL` the moment `pvpn-killswitch` appeared, the network was lost in three of three rounds. The kill switch was off.

The symptom is no network after a cancelled or crashed connect, with `pvpn-killswitch` in the output of `nmcli connection show`. The repair needs no network:

        nmcli connection delete id pvpn-killswitch

`vpn-off` (see "Connect and disconnect quickly") also deletes it, along with any other leftover `pvpn-*` and `ProtonVPN *` connection. The effect of `SIGTERM`, the signal that `vpn-off` and `timeout` send, at that moment was not isolated.

### Checks

        protonvpn status
        curl -4 -s --max-time 8 https://ifconfig.me ; echo
        ip rule | grep -c fwmark
        sudo nft list tables
        resolvectl query example.com
        nmcli -t -f NAME,TYPE,DEVICE connection show --active
        sudo firewall-cmd --get-active-zones

Connected: the `curl` address differs from the home address, the count is `1`, `nft list tables` lists `nm-wg-proton0`, `resolvectl` names `proton0` as the link, and `proton0` is in the default firewalld zone. Disconnected: the count is `0`, only `inet firewalld` remains, and DNS goes over the Wi-Fi.

### Connect and disconnect quickly

Two scripts turn the VPN on and off without sudo or a password. With the kill switch off, a disconnect puts the laptop back on its normal connection.

`vpn-on` does not sign in, because that needs the account password and a security key or authenticator code. Run `protonvpn signin USERNAME` first. It waits for a disconnect in progress, refuses to start a second connect, runs `protonvpn connect` under a 60-second timeout, passes any other options through (`vpn-on --country DE`), checks for an active WireGuard connection, tests the internet with `curl -4`, and prints one result line and a desktop notification. It prints the server name and no exit address. If the connect fails or times out and a WireGuard, `fwmark`, or `pvpn-` connection remains, it runs `vpn-off`.

`vpn-off` cancels a `protonvpn connect` that is in progress, runs `protonvpn disconnect` under a 10-second timeout, and falls back to taking the WireGuard connection down through NetworkManager. After a NetworkManager-only teardown, `protonvpn status` kept reporting `Connected` until `protonvpn disconnect` ran, so the script runs the client's disconnect again. It then deletes every connection whose name starts with `pvpn-` or `ProtonVPN `, including any you created under those names, and checks that nothing is left. It prints what was active at the start, the result, and a desktop notification. It also checks for a running `protonvpn connect` process. A version that checked only connections and routing rules reported the VPN as off while a connect was starting, and the connect then finished.

Save each script under `~/.local/bin/`, then run `chmod +x ~/.local/bin/vpn-off ~/.local/bin/vpn-on`.

`~/.local/bin/vpn-off`:

        #!/usr/bin/env bash
        # vpn-off: turn the Proton VPN off. Needs no sudo and no password.
        # Usage: vpn-off [--pause]   (--pause waits for Enter before the terminal closes)
        # - A connect that is in progress is cancelled first.
        # - Leftover client connections (pvpn-*, ProtonVPN *) are deleted at the end.
        #   A connect that is cut off can leave the temporary pvpn-killswitch connection,
        #   which is the default route and DNS for IPv4 and IPv6.
        # Test hook: VPN_OFF_SKIP_CLIENT=1 skips the client's disconnect to exercise the fallback.
        # VPN_OFF_QUIET=1 suppresses the desktop notification (vpn-on uses it).

        say() {
            echo "$1"
            if [ -z "$VPN_OFF_QUIET" ] && command -v notify-send >/dev/null 2>&1; then
                notify-send -u critical -i network-disconnect "Proton VPN" "$1" >/dev/null 2>&1
            fi
        }

        # True if a WireGuard or pvpn- connection is active, or a fwmark routing rule exists.
        # Another tool that adds a fwmark rule would make this report the VPN as on.
        vpn_active() {
            nmcli -t -f TYPE connection show --active 2>/dev/null | grep -qx 'wireguard' && return 0
            nmcli -t -f NAME connection show --active 2>/dev/null | grep -q '^pvpn-' && return 0
            ip rule 2>/dev/null | grep -q 'fwmark' && return 0
            return 1
        }

        running() { pgrep -f "protonvpn $1" >/dev/null 2>&1; }

        # Names the signals that make vpn_active true (used in the fallback message).
        why_active() {
            local w=""
            nmcli -t -f TYPE connection show --active 2>/dev/null | grep -qx 'wireguard' && w="$w wireguard"
            nmcli -t -f NAME connection show --active 2>/dev/null | grep -q '^pvpn-' && w="$w pvpn-connection"
            ip rule 2>/dev/null | grep -q 'fwmark' && w="$w fwmark-rule"
            echo "${w# }"
        }

        client_disconnect() { timeout 10 protonvpn disconnect >/dev/null 2>&1; }

        # Delete every client connection, active or saved. Deleting one also deactivates it.
        clean_profiles() {
            nmcli -t -f UUID,NAME connection show 2>/dev/null | while IFS=: read -r uuid name; do
                case "$name" in
                    pvpn-*|"ProtonVPN "*)
                        nmcli connection delete uuid "$uuid" >/dev/null 2>&1 && echo "Removed leftover connection: $name" ;;
                esac
            done
        }

        start_active=0
        vpn_active && start_active=1
        if [ "$start_active" = 1 ]; then echo "Active at the start: $(why_active)"; fi

        cancelled=0
        if running connect; then
            cancelled=1
            echo "A connect is in progress. Cancelling it."
            pkill -f 'protonvpn connect'
            for _ in 1 2 3 4 5; do running connect || break; sleep 1; done
            running connect && pkill -9 -f 'protonvpn connect'
            # NetworkManager may finish an activation that was already requested.
            sleep 2
        fi

        # Wait for another disconnect to finish.
        for _ in $(seq 1 15); do running disconnect || break; sleep 1; done

        fallback=0
        if [ "$cancelled" = 1 ] || vpn_active; then
            if [ -z "$VPN_OFF_SKIP_CLIENT" ]; then
                client_disconnect
                sleep 1
            fi
            if vpn_active; then
                fallback=1
                echo "The client did not take the VPN down (still active: $(why_active)). Using NetworkManager."
                nmcli -t -f TYPE,NAME connection show --active | while IFS=: read -r type name; do
                    [ "$type" = "wireguard" ] && nmcli connection down id "$name" >/dev/null 2>&1
                done
                sleep 1
                # The client keeps reporting "Connected" after NetworkManager takes the tunnel down.
                client_disconnect
                sleep 1
            fi
        fi

        # Always run the cleanup, before the final check.
        clean_profiles
        sleep 1

        if vpn_active; then
            say "VPN may still be ON. Run: nmcli connection show --active"
        elif [ "$cancelled" = 1 ]; then
            say "The connect was cancelled. VPN is OFF."
        elif [ "$fallback" = 1 ]; then
            say "VPN is OFF (taken down with NetworkManager). Traffic now uses the normal connection."
        elif [ "$start_active" = 1 ]; then
            say "VPN is OFF. Traffic now uses the normal connection."
        else
            say "VPN is already off."
        fi

        if [ "$1" = "--pause" ]; then
            read -r -p "Press Enter to close. "
        fi

`~/.local/bin/vpn-on`:

        #!/usr/bin/env bash
        # vpn-on: connect the Proton VPN. Needs no sudo and no password.
        # Usage: vpn-on [--pause] [options for "protonvpn connect"]
        #   vpn-on                  connect to the fastest server
        #   vpn-on --country US     options pass through to "protonvpn connect"
        # The client must already be signed in: protonvpn signin USERNAME
        # vpn-off cancels a connect that is in progress.

        say() {
            echo "$1"
            if command -v notify-send >/dev/null 2>&1; then
                notify-send -u normal -i network-vpn "Proton VPN" "$1" >/dev/null 2>&1
            fi
        }

        # True if a WireGuard connection is active or a fwmark routing rule exists.
        vpn_active() {
            nmcli -t -f TYPE connection show --active 2>/dev/null | grep -qx 'wireguard' && return 0
            ip rule 2>/dev/null | grep -q 'fwmark' && return 0
            return 1
        }

        running() { pgrep -f "protonvpn $1" >/dev/null 2>&1; }

        pause=0
        args=()
        for a in "$@"; do
            if [ "$a" = "--pause" ]; then pause=1; else args+=("$a"); fi
        done

        finish() {
            if [ "$pause" = 1 ]; then
                read -r -p "Press Enter to close. "
            fi
        }

        # Wait for a disconnect that is in progress.
        for _ in $(seq 1 15); do running disconnect || break; sleep 1; done

        if running connect; then
            say "A connect is already in progress."
            finish
            exit 0
        fi

        if vpn_active; then
            timeout 20 protonvpn status 2>/dev/null | head -4
            say "VPN is already on."
            finish
            exit 0
        fi

        out=$(timeout 60 protonvpn connect "${args[@]}" 2>&1)
        rc=$?
        sleep 1

        if [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then
            say "The connect was cancelled."
        elif [ "$rc" -eq 0 ] && vpn_active; then
            server=$(printf '%s\n' "$out" | grep -m1 '^Connected to')
            if curl -4 -s -o /dev/null --max-time 8 https://ifconfig.me; then
                say "VPN is ON. ${server:-Connected.} Internet test passed."
            else
                say "VPN is ON, but the internet test failed. Run vpn-off, then vpn-on."
            fi
        else
            echo "Client output:"
            printf '%s\n' "$out" | grep -v -i 'your new ip'
            if vpn_active || nmcli -t -f NAME connection show --active 2>/dev/null | grep -q '^pvpn-'; then
                echo "A partial connection remains. Clearing it with vpn-off."
                [ -x "$HOME/.local/bin/vpn-off" ] && VPN_OFF_QUIET=1 "$HOME/.local/bin/vpn-off" >/dev/null 2>&1
            fi
            if [ "$rc" -eq 124 ]; then
                say "The connect timed out. The VPN is not on. Run vpn-on again, or vpn-off to clean up."
            else
                say "VPN did not connect. If the client says you are not signed in, run: protonvpn signin USERNAME"
            fi
        fi

        finish

To start them from the application menu, a panel, or a keyboard shortcut, save launchers under `~/.local/share/applications/` with the user name in `Exec` changed.

`vpn-off.desktop`:

        [Desktop Entry]
        Type=Application
        Name=VPN off
        Comment=Disconnect the Proton VPN now
        Exec=/home/USER/.local/bin/vpn-off --pause
        Icon=network-disconnect
        Terminal=true
        Categories=Network;

`vpn-on.desktop`:

        [Desktop Entry]
        Type=Application
        Name=VPN on
        Comment=Connect the Proton VPN now
        Exec=/home/USER/.local/bin/vpn-on --pause
        Icon=network-vpn
        Terminal=true
        Categories=Network;

Tested on Fedora 44 KDE:

- `vpn-on` from the disconnected state, with the VPN already on, in an off, on, off cycle, with `--country DE` (a server in Germany), and with short timeouts, which printed the timeout message and ran `vpn-off` when a connection was left. The `pvpn-` check was tested alone with a dummy connection named `pvpn-test`.
- `vpn-off` on the normal path, on the fallback path (forced with `VPN_OFF_SKIP_CLIENT=1`, which skips the client's disconnect), and started 0.3, 1, 2, and 5 seconds after `vpn-on`. Each time the connect was cancelled or had finished, and no connection, routing rule, or `nft` table was left.
- `vpn-off` as the repair for the network lost after a cancelled connect, in three of three rounds.
- Both launchers, started from the panel.

After a disconnect, `protonvpn status` printed `Disconnected`, the `fwmark` count was 0, and `sudo nft list tables` listed only `inet firewalld`.

Not tested: a client that hangs, an expired session, `SIGTERM` at the moment the temporary connection exists, a keyboard shortcut. The scripts do not touch the kill switch. If a kill switch blocks the network, use the commands in the kill switch section.

### Remove

        protonvpn disconnect
        protonvpn config set kill-switch off
        sudo python3 -I -m proton.vpn.killswitch.disable
        protonvpn signout
        sudo dnf remove --assumeno proton-vpn-cli protonvpn-*-release

Read the removal list before running the last command without `--assumeno`. Delete leftover connections whose names begin with `pvpn-` with `nmcli connection delete NAME`, and delete the directory `/etc/systemd/system/me.proton.vpn.split_tunneling.service.d`.

## Verified

Fedora 44 KDE, 2026-11-06: with `kdeconnectd` listening on port 1716, a connection from another machine on the network to TCP port 1716 was blocked. In the control, TCP port 8000 was reachable while a rule allowed it and unreachable after the rule closed. A `firewall-cmd --reload` kept the Wi-Fi connection in the `home` zone.

Fedora 44 KDE, 2026-11-06: after a reboot, the Wi-Fi connection was in the `home` zone, `FedoraWorkstation` had no ports, and `home` had `dhcpv6-client`, `mdns`, and `samba-client`.

Fedora 44 KDE, 2026-11-11, `proton-vpn-cli` 1.1.0, WireGuard: `protonvpn connect` succeeded with the split-tunneling helper disabled by the start condition. While connected, the IPv4 and IPv6 exit addresses were in Proton's range, `resolvectl query` answered over `proton0`, the VPN interfaces were in the default firewalld zone, the home subnet stayed on the Wi-Fi, and a CUPS print job to a printer on the home network completed. After `protonvpn disconnect`, the nftables tables, the policy-routing rules, the dummy connection, and the DNS route matched their state before the connection. The connection stayed in place through suspends of 11 seconds, about 7 hours, and about 40 hours on the home Wi-Fi.

The quick connect and disconnect scripts were tested on the same laptop (see "Connect and disconnect quickly"). A connect that was killed at the moment the temporary `pvpn-killswitch` connection existed left the laptop without a network in three of three rounds, and `vpn-off` restored it each time. A dry run of the role (`ansible-playbook --check --tags firewall_vpn`) on the same laptop, which already had the packages installed, reported no changes.

Not yet tested: the browser DNS and WebRTC leak tests, a network change while connected, a reboot (sign-in and reconnect), the kill switch, the start condition under a package upgrade, and the Ansible tasks on a fresh install.
