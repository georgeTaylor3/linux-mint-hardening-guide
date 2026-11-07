# Firewall on Fedora (firewalld)

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

## VPN kill switch

Not written yet for Fedora.

## Verified

Fedora 44 KDE, 2026-11-06: with `kdeconnectd` listening on port 1716, a connection from another machine on the network to TCP port 1716 was blocked. In the control, TCP port 8000 was reachable while a rule allowed it and unreachable after the rule closed. A `firewall-cmd --reload` kept the Wi-Fi connection in the `home` zone.

Fedora 44 KDE, 2026-11-06: after a reboot, the Wi-Fi connection was in the `home` zone, `FedoraWorkstation` had no ports, and `home` had `dhcpv6-client`, `mdns`, and `samba-client`.
