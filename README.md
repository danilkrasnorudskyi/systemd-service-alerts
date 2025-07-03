# Service Restart Alert Setup

This script sets up automatic alerts for a specified systemd service on Ubuntu, notifying you via Slack whenever the service is restarted—either manually or automatically after a failure. The alert message includes the service name, host, environment name, timestamp, and reason for the restart.

---

## Features

- Detects if a service restart was manual or automatic after failure
- Sends notifications to a Slack webhook URL
- Works with any systemd service name
- Includes environment name in alerts for easy identification

---

## Prerequisites

- Ubuntu server with `systemd`
- The service you want to monitor is managed by systemd (e.g., nginx, php-fpm, redis)
- Slack incoming webhook URL (or adapt the script to your preferred alerting method)
- `curl` installed (usually preinstalled on Ubuntu)

---

## Installation & Usage

1. **Copy the script to your server**

   Save the provided script as `setup-service-alerts.sh` and make it executable:

   ```bash
   chmod +x setup-service-alerts.sh
   ```

2. **Run the script with arguments**

   ```bash
   sudo ./setup-service-alerts.sh <service-name> <slack-webhook-url> <env-name>
   ```

   - `<service-name>` — the systemd service to monitor (e.g., `nginx`)
   - `<slack-webhook-url>` — your Slack incoming webhook URL to receive alerts
   - `<env-name>` — a friendly environment label (e.g., `production`, `staging`)

   Example:

   ```bash
   sudo ./setup-service-alerts.sh nginx https://hooks.slack.com/services/XXX/YYY/ZZZ production
   ```

3. **What the script does**

   - Creates two alert scripts in `/usr/local/bin/`:
     - `service-stop-alert.sh`: runs after the service stops and records stop info
     - `service-start-post.sh`: runs after the service starts, determines restart type, and sends Slack alert
   - Creates a systemd override for the specified service to call these scripts on stop/start and enable automatic restart on failure
   - Reloads systemd and restarts the monitored service

4. **Verify**

   You can test the setup by killing the service process:

   ```bash
   sudo kill -9 $(pidof <service-name>)
   ```

   You should receive a Slack alert showing the service was automatically restarted due to failure.

   Manually restarting the service with:

   ```bash
   sudo systemctl restart <service-name>
   ```

   will generate a Slack alert indicating a manual restart.

---

## Notes

- The alert message includes hostname and environment name for better context
- Make sure your Slack webhook URL is valid and has permissions to post messages
- You can modify `/usr/local/bin/service-start-post.sh` if you want to use other alerting methods

---

## Troubleshooting

- If alerts do not appear, check the journal logs for errors:

  ```bash
  journalctl -u <service-name> -e
  ```

- Verify script permissions:

  ```bash
  ls -l /usr/local/bin/service-*.sh
  ```

- Test curl command manually with your webhook URL

---

If you want to monitor multiple services or use email/Telegram for alerts, feel free to ask for help!
