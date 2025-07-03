#!/bin/bash

# Usage: ./setup-service-alerts.sh <service-name> <slack-webhook-url> <env-name>

if [ $# -ne 3 ]; then
  echo "Usage: $0 <service-name> <slack-webhook-url> <env-name>"
  exit 1
fi

SERVICE="$1"
WEBHOOK_URL="$2"
ENV_NAME="$3"

mkdir -p /usr/local/bin

cat <<EOF >/usr/local/bin/service-stop-alert.sh
#!/bin/bash
SERVICE="\$1"
HOST=\$(hostname)
TIME=\$(date '+%Y-%m-%d %H:%M:%S')

echo "\$TIME" > /run/service-last-stop-\$SERVICE.time
echo "\$SERVICE_RESULT" > /run/service-last-stop-\$SERVICE.reason
EOF

chmod +x /usr/local/bin/service-stop-alert.sh

cat <<EOF >/usr/local/bin/service-start-post.sh
#!/bin/bash
SERVICE="\$1"
HOST=\$(hostname)
TIME=\$(date '+%Y-%m-%d %H:%M:%S')
ENV_NAME="$ENV_NAME"

STOP_TIME_FILE="/run/service-last-stop-\$SERVICE.time"
STOP_REASON_FILE="/run/service-last-stop-\$SERVICE.reason"

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

MESSAGE="⚠️ Service *\$SERVICE* was \$RESTART_TYPE on \$HOST (\$ENV_NAME) at \$TIME (previous stop at \$STOP_TIME with reason: \$STOP_REASON)"

curl -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"\$MESSAGE\"}" "$WEBHOOK_URL"

rm -f "\$STOP_TIME_FILE" "\$STOP_REASON_FILE"
EOF

chmod +x /usr/local/bin/service-start-post.sh

mkdir -p /etc/systemd/system/$SERVICE.service.d

cat <<EOF >/etc/systemd/system/$SERVICE.service.d/override.conf
[Unit]
OnFailure=service-failure-alert@%n

[Service]
Restart=on-failure
RestartSec=5
ExecStopPost=/usr/local/bin/service-stop-alert.sh %n
ExecStartPost=/usr/local/bin/service-start-post.sh %n
EOF

systemctl daemon-reload
systemctl restart $SERVICE

echo "Alert setup complete for service: $SERVICE in environment: $ENV_NAME"
