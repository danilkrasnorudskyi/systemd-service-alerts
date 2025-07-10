#!/bin/bash

# Usage: ./setup-service-alerts.sh <service-name> <slack-webhook-url> <env-name>

if [ $# -ne 3 ]; then
  echo "Usage: $0 <service-name> <slack-webhook-url> <env-name>"
  exit 1
fi

SERVICE="$1"
WEBHOOK_URL="$2"
ENV_NAME="$3"

sudo mkdir -p /var/lib/service-alerts
sudo chown root:root /var/lib/service-alerts
sudo chmod 777 /var/lib/service-alerts

mkdir -p /usr/local/bin

cat <<EOF >/usr/local/bin/service-stop-alert.sh
#!/bin/bash
SERVICE="\$1"
HOST=\$(hostname)
TIME=\$(date '+%Y-%m-%d %H:%M:%S')
ENV_NAME="$ENV_NAME"

echo "\$TIME" > /var/lib/service-alerts/service-last-stop-\$SERVICE.time
echo "\$SERVICE_RESULT" > /var/lib/service-alerts/service-last-stop-\$SERVICE.reason

if [[ "\$SERVICE_RESULT" == "success" || -z "\$SERVICE_RESULT" ]]; then
    RESTART_TYPE="manually stopped"
else
    RESTART_TYPE="stopped on failure"
fi

MESSAGE=":alert: Service *\$SERVICE* on *\$ENV_NAME* was \$RESTART_TYPE at *\$TIME* (reason: \$SERVICE_RESULT). Host: \$HOST"

curl -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"\$MESSAGE\"}" "$WEBHOOK_URL"
EOF

chmod +x /usr/local/bin/service-stop-alert.sh

cat <<EOF >/usr/local/bin/service-start-post.sh
#!/bin/bash
SERVICE="\$1"
HOST=\$(hostname)
TIME=\$(date '+%Y-%m-%d %H:%M:%S')
ENV_NAME="$ENV_NAME"

STOP_TIME_FILE="/var/lib/service-alerts/service-last-stop-\$SERVICE.time"
STOP_REASON_FILE="/var/lib/service-alerts/service-last-stop-\$SERVICE.reason"

if [[ -f "\$STOP_TIME_FILE" && -f "\$STOP_REASON_FILE" ]]; then
    STOP_TIME=\$(cat "\$STOP_TIME_FILE")
    STOP_REASON=\$(cat "\$STOP_REASON_FILE")
else
    STOP_TIME=""
    STOP_REASON=""
fi

if [[ "\$STOP_REASON" == "success" || -z "\$STOP_REASON" ]]; then
    RESTART_TYPE="manually restarted"
else
    RESTART_TYPE="automatically restarted after failure"
fi

MESSAGE=":large_green_circle: Service *\$SERVICE* was \$RESTART_TYPE on *\$ENV_NAME* at *\$TIME* (previous stop at \$STOP_TIME with reason: \$STOP_REASON). Host: \$HOST"

curl -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"\$MESSAGE\"}" "$WEBHOOK_URL"

rm -f "\$STOP_TIME_FILE" "\$STOP_REASON_FILE"
EOF

chmod +x /usr/local/bin/service-start-post.sh

CONFIG_FILE="/etc/systemd/system/$SERVICE.service.d/override.conf"
mkdir -p "$(dirname "$CONFIG_FILE")"

CONFIG_FILE="/etc/systemd/system/$SERVICE.service.d/override.conf"

# Ensure directory exists
mkdir -p "$(dirname "$CONFIG_FILE")"

# Define settings
SETTINGS="
Restart=on-failure
RestartSec=5
ExecStopPost=/usr/local/bin/service-stop-alert.sh %n
ExecStartPost=/usr/local/bin/service-start-post.sh %n
"

# Add redis-specific setting if needed
case "$SERVICE" in
  *redis*)
    SETTINGS="$SETTINGS
ReadWriteDirectories=-/var/lib/service-alerts"
    ;;
esac

# If file doesn’t exist, create with [Service] header
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[Service]" >"$CONFIG_FILE"
    echo "$SETTINGS" >>"$CONFIG_FILE"
    echo "Created $CONFIG_FILE with [Service] block"
else
    # Check if [Service] section exists
    if grep -q '^\[Service\]' "$CONFIG_FILE"; then
        echo "Found [Service] section in $CONFIG_FILE"
    else
        # Add [Service] at the end
        echo "\n[Service]" >>"$CONFIG_FILE"
        echo "$SETTINGS" >>"$CONFIG_FILE"
        echo "Added [Service] section with settings"
    fi

    # For each setting, check if it exists in [Service], else append
    for setting in $SETTINGS; do
        KEY=$(echo "$setting" | cut -d= -f1)
        VALUE=$(echo "$setting" | cut -d= -f2-)

        # Check if KEY exists inside [Service]
        if awk '
            $0 == "[Service]" { in_service=1; next }
            /^\[/ && $0 != "[Service]" { in_service=0 }
            in_service && $1 == "'$KEY'=" { found=1 }
            END { exit !found }
        ' "$CONFIG_FILE"; then
            echo "Setting $KEY already exists in [Service], skipping."
        else
            # Append to [Service] section
            awk -v key="$KEY" -v value="$VALUE" '
                BEGIN { added=0 }
                $0 == "[Service]" { print; nextline=NR+1 }
                NR==nextline && added==0 {
                    print key "=" value
                    added=1
                }
                { print }
                END {
                    if (added==0) {
                        print key "=" value
                    }
                }
            ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            echo "Appended $KEY=$VALUE to [Service] in $CONFIG_FILE"
        fi
    done
fi


systemctl daemon-reload
systemctl restart $SERVICE

echo "Alert setup complete for service: $SERVICE in environment: $ENV_NAME"
