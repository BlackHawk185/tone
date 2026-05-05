#!/usr/bin/env bash
set -euo pipefail

# Deploy the tone-dispatch-listener Cloud Run service.
#
# NOTE: A Cloud Scheduler job (renew-gmail-watch) must exist to POST to
# /renew-watch every 6 days. Gmail push watches expire after 7 days.
# To create it (one-time):
#   gcloud scheduler jobs create http renew-gmail-watch \
#     --schedule="0 0 */6 * *" \
#     --uri="https://tone-dispatch-listener-nhbnibjr5a-uc.a.run.app/renew-watch" \
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
