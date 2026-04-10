#!/usr/bin/env bash
set -euo pipefail

# Deploy the tone-dispatch-listener Cloud Run service
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
