#!/bin/bash
set -euo pipefail

CRON_USER="ubuntu"

EXISTING_CRON="$(sudo crontab -u "${CRON_USER}" -l 2>/dev/null || true)"

# 1) Remove any old/bad mongodump --uri lines from previous iterations
CLEANED_CRON="$(echo "${EXISTING_CRON}" | grep -v 'mongodump --uri=' || true)"

# 2) If the good job already exists, just write the cleaned cron back (in case we removed old lines)
if echo "${CLEANED_CRON}" | grep -q "wiz-mongodump-backup"; then
  echo "${CLEANED_CRON}" | sudo crontab -u "${CRON_USER}" -
  exit 0
fi

# 3) Add the correct job (no URI parsing issues)
CRON_LINE="0 3 * * * /usr/bin/mongodump --host 127.0.0.1 --port 27017 --username tasky --password '${MONGO_APP_PASSWORD}' --authenticationDatabase admin --db go-mongodb --archive=/tmp/mongodump-\$(date +\\%F).gz --gzip && /usr/bin/aws s3 cp /tmp/mongodump-\$(date +\\%F).gz s3://${BACKUP_BUCKET}/ # wiz-mongodump-backup"

( echo "${CLEANED_CRON}"
  echo "${CRON_LINE}"
) | sudo crontab -u "${CRON_USER}" -
