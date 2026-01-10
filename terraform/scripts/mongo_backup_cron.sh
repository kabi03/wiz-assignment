#!/bin/bash
set -e

# Expected env vars from Terraform:
#   BACKUP_BUCKET
#   MONGO_APP_PASSWORD

INSTALL_DIR="/usr/local/bin"
BACKUP_SCRIPT="${INSTALL_DIR}/wiz_mongo_backup.sh"
ENV_FILE="/etc/wiz-mongo-backup.env"
LOG_DIR="/var/log/wiz"
LOG_FILE="${LOG_DIR}/mongo_backup.log"
CRON_USER="ubuntu"

if [ -z "${BACKUP_BUCKET:-}" ]; then
  echo "BACKUP_BUCKET not set"
  exit 1
fi

if [ -z "${MONGO_APP_PASSWORD:-}" ]; then
  echo "MONGO_APP_PASSWORD not set"
  exit 1
fi

# ----------------------------
# Write env file (NO QUOTES NEEDED because we won't 'source' it)
# ----------------------------
sudo bash -lc "cat > ${ENV_FILE} <<'EOF'
BACKUP_BUCKET=${BACKUP_BUCKET}
MONGO_APP_PASSWORD=${MONGO_APP_PASSWORD}
EOF"

# readable by ubuntu, not world-readable
sudo chown root:ubuntu "${ENV_FILE}"
sudo chmod 640 "${ENV_FILE}"

# ----------------------------
# Write backup script (DO NOT SOURCE env file; parse it safely)
# ----------------------------
sudo bash -lc "cat > ${BACKUP_SCRIPT} <<'EOF'
#!/bin/bash
set -e

ENV_FILE=\"/etc/wiz-mongo-backup.env\"

BACKUP_BUCKET=\"\$(grep '^BACKUP_BUCKET=' \"\$ENV_FILE\" | head -n1 | cut -d= -f2-)\"
MONGO_APP_PASSWORD=\"\$(grep '^MONGO_APP_PASSWORD=' \"\$ENV_FILE\" | head -n1 | cut -d= -f2-)\"

TS=\"\$(/bin/date +%F-%H%M)\"
TMP_FILE=\"/tmp/mongodump-\${TS}.gz\"

/usr/bin/mongodump \\
  --host 127.0.0.1 \\
  --port 27017 \\
  -u tasky \\
  --password \"\$MONGO_APP_PASSWORD\" \\
  --authenticationDatabase admin \\
  --archive=\"\$TMP_FILE\" \\
  --gzip

/usr/bin/aws s3 cp \"\$TMP_FILE\" \"s3://\$BACKUP_BUCKET/mongodump-\${TS}.gz\"

rm -f \"\$TMP_FILE\"
EOF"

sudo chmod 755 "${BACKUP_SCRIPT}"

# ----------------------------
# Ensure log directory exists and is writable by ubuntu
# ----------------------------
sudo mkdir -p "${LOG_DIR}"
sudo chown ubuntu:ubuntu "${LOG_DIR}"
sudo touch "${LOG_FILE}"
sudo chown ubuntu:ubuntu "${LOG_FILE}"
sudo chmod 664 "${LOG_FILE}"

# ----------------------------
# Install DAILY cron @ 03:00 UTC
# ----------------------------
CRON_LINE="0 3 * * * ${BACKUP_SCRIPT} >> ${LOG_FILE} 2>&1 # wiz-mongodump-backup"

EXISTING_CRON="$(sudo crontab -u ${CRON_USER} -l 2>/dev/null | grep -v wiz-mongodump-backup || true)"
(
  echo "${EXISTING_CRON}"
  echo "${CRON_LINE}"
) | sudo crontab -u ${CRON_USER} -

echo "Installed daily cron for ${CRON_USER}: ${CRON_LINE}"
