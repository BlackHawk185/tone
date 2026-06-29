#!/usr/bin/env bash
set -euo pipefail

# Deploy the tone-dispatch-listener Cloud Run service.
#
# NOTE: Scheduler jobs should exist for:
#   1. /renew-watch every 6 days for Gmail Pub/Sub watches
#   2. /renew-calendar-watch every 6 days for Calendar webhook watches
#   3. /refresh-calendar-shifts on a lower cadence as a safety reconcile
# Gmail and Calendar watches both expire after 7 days.
# To create the Gmail renew job (one-time):
#   gcloud scheduler jobs create http renew-gmail-watch \
#     --schedule="0 0 */6 * *" \
#     --uri="https://tone-dispatch-listener-323826101860.us-central1.run.app/renew-watch" \
#     --http-method=POST \
#     --location=us-central1
# To create the Calendar renew job:
#   gcloud scheduler jobs create http renew-calendar-watch \
#     --schedule="15 0 */6 * *" \
#     --uri="https://tone-dispatch-listener-323826101860.us-central1.run.app/renew-calendar-watch" \
#     --http-method=POST \
#     --location=us-central1
# To create the Calendar reconcile job:
#   gcloud scheduler jobs create http refresh-calendar-shifts \
#     --schedule="*/15 * * * *" \
#     --uri="https://tone-dispatch-listener-323826101860.us-central1.run.app/refresh-calendar-shifts" \
#     --http-method=POST \
#     --location=us-central1
gcloud run deploy tone-dispatch-listener \
  --source . \
  --region us-central1 \
  --min-instances 1 \
  --max-instances 1 \
  --no-cpu-throttling \
  --cpu-boost \
  --memory 512Mi \
  --timeout 3600 \
  --allow-unauthenticated
