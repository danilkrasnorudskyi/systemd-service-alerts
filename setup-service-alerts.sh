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

declare -A SETTINGS
SETTINGS["Restart"]="on-failure"
SETTINGS["RestartSec"]="5"
SETTINGS["ExecStopPost"]="/usr/local/bin/service-stop-alert.sh %n"
SETTINGS["ExecStartPost"]="/usr/local/bin/service-start-post.sh %n"

if [[ "$SERVICE" == *redis* ]]; then
    SETTINGS["ReadWriteDirectories"]="-/var/lib/service-alerts"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "[Service]" >"$CONFIG_FILE"
    echo "Created $CONFIG_FILE with [Service] header"
elif ! grep -q '^\[Service\]' "$CONFIG_FILE"; then
    echo -e "\n[Service]" >>"$CONFIG_FILE"
    echo "Added [Service] header to $CONFIG_FILE"
fi

for KEY in "${!SETTINGS[@]}"; do
    VALUE="${SETTINGS[$KEY]}"
    if grep -Eq "^\s*${KEY}=" "$CONFIG_FILE"; then
        echo "Setting ${KEY} already exists in $CONFIG_FILE, skipping."
    else
        echo "${KEY}=${VALUE}" >>"$CONFIG_FILE"
        echo "Appended ${KEY}=${VALUE} to $CONFIG_FILE"
    fi
done

systemctl daemon-reload
systemctl restart $SERVICE

echo "Alert setup complete for service: $SERVICE in environment: $ENV_NAME"
