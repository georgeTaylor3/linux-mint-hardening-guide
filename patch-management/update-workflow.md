# Update workflow on Fedora

How the update timers, the check script, and the alerts connect. The diagrams match the files in `scripts/` and the settings in the [Fedora guide](fedora.md).

## From timers to warnings

Dashed arrow: the check reads what `dnf5-automatic` left behind.

```mermaid
flowchart TD
  subgraph SYS["System unit (root)"]
    T1["dnf5-automatic.timer<br/>OnCalendar daily 06:00, RandomizedDelaySec 60m<br/>Persistent=true runs it after a missed slot"]
    S1["dnf5-automatic.service<br/>Runs dnf5 automatic --timer<br/>/etc/dnf/automatic.conf: security only, apply, never reboot"]
    J["Journal and saved state<br/>A successful run logs Finished in the persistent journal<br/>The check also saves the date in ~/.local/state/update-check/last-run"]
    T1 --> S1 --> J
  end
  subgraph USR["User unit (your login)"]
    T2["update-check.timer<br/>OnStartupSec=15min, OnCalendar 09:00 and 21:00<br/>Persistent=true"]
    S2["update-check.service<br/>ExecStartPre waits up to 60 s for nm-online<br/>ExecStart runs check-updates.sh"]
    C["check-updates.sh<br/>Newest run = latest of systemd record, journal, saved date<br/>Reboot test = dnf needs-restarting exit code 1 plus the word reboot"]
    T2 --> S2 --> C
  end
  J -.->|"reads"| C
  C --> O["Updates overdue<br/>No completed run in 48 hours (MAX_RUN_AGE_H)"]
  C --> F["Updates failed<br/>Service failed or last exit was not 0<br/>Message carries the last 15 journal lines"]
  C --> R["Reboot pending<br/>Pending 72 hours (MAX_REBOOT_AGE_H)<br/>Clock starts at the first check that sees it"]
```

- The two timers run independently. Neither starts the other.
- The check takes the newest completed run from three sources: systemd's record of the service, the journal, and the saved date. A check that starts in the same second as a run, which happens when both timers catch up after a suspend, can miss systemd's record. The journal covers that case.

## From a warning to the inbox

This is an example delivery path. `send-alert.sh` and the `msmtp` configuration are not part of this repository. Any command that accepts `KEY SUBJECT BODY` can serve as `ALERT`.

```mermaid
flowchart TD
  W["warn() in check-updates.sh<br/>Called as: warn KEY SUBJECT BODY<br/>KEY is updates-overdue, updates-failed, reboot-pending, or update-check"]
  P["Desktop popup<br/>notify-send -u critical posts the message to the Plasma notification service over D-Bus, reachable because the check runs as a user unit in your login session"]
  A["ALERT command (optional)<br/>Runs as: ALERT KEY SUBJECT BODY<br/>Example: send-alert.sh, one email per KEY per day"]
  M["msmtp<br/>Reads ~/.config/msmtp/config (mode 600)<br/>STARTTLS with an SMTP token"]
  S["Proton SMTP<br/>smtp.protonmail.ch, port 587"]
  I["Inbox<br/>Subject starts with the hostname in brackets"]
  X["If the send fails<br/>The error goes to the msmtp log and the journal<br/>check-updates.sh logs: alert command failed<br/>A failed send does not use up the day, so the next check retries"]
  W --> P
  W --> A
  A --> M --> S --> I
  M -.->|"error"| X
```

- Without `ALERT`, the desktop popup is the only output.
- The `nm-online` wait covers the network connection and not name resolution. A send can still fail just after a wake, and the failure path above handles that case.
