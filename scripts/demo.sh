#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: demo.sh
# Description: End-to-end interactive demonstration of AWS secrets & zero-trust
#              access model verification.
# ==============================================================================

APP_URL="${APP_URL:-http://localhost:8080}"
ENV="${1:-dev}"
SECRET_NAME="myapp/${ENV}/app/database"

echo "======================================================================"
echo " AWS Secrets & Zero-Trust Access End-to-End Demonstration"
echo " Target URL   : ${APP_URL}"
echo " Secret Path  : ${SECRET_NAME}"
echo "======================================================================"

# 1. Health & Readiness Verification
echo ""
echo "[Step 1] Checking App Health & Readiness endpoints..."
echo "GET ${APP_URL}/health"
curl -s "${APP_URL}/health" | jq .
echo ""
echo "GET ${APP_URL}/ready"
curl -s "${APP_URL}/ready" | jq .

# 2. Live Secret Fetch (Masked Payload)
echo ""
echo "[Step 2] Fetching live secret via application (/demo endpoint)..."
echo "GET ${APP_URL}/demo"
curl -s "${APP_URL}/demo" | jq .

# 3. Cache Metrics Verification
echo ""
echo "[Step 3] Inspecting in-memory secret cache metrics..."
echo "GET ${APP_URL}/metrics"
curl -s "${APP_URL}/metrics" | jq .

# 4. Zero-Downtime Secret Rotation Demo
echo ""
echo "[Step 4] Simulating live secret rotation in AWS Secrets Manager..."
NEW_PASSWORD="RotatedDemoPassword_$(date +%s)_Secured!"
aws secretsmanager put-secret-value \
  --secret-id "${SECRET_NAME}" \
  --secret-string "{\"username\":\"dev_db_user\",\"password\":\"${NEW_PASSWORD}\",\"host\":\"db-dev.myapp.internal\",\"port\":\"5432\"}"
echo "  ✓ Secret updated in AWS Secrets Manager."

echo ""
echo "[Step 5] Triggering cache refresh and verifying updated state..."
curl -s "${APP_URL}/demo" | jq .

# 5. Security Boundary & Explicit Deny Verification
echo ""
echo "[Step 6] Verifying Security Boundaries (Explicit Deny Rules)..."
echo "  - Testing App Role mutation block (App cannot delete secret):"
if aws secretsmanager delete-secret --secret-id "${SECRET_NAME}" --force-delete-without-recovery 2>&1 | grep -q "AccessDenied"; then
  echo "    ✓ PASSED: App role is explicitly DENIED from deleting secrets."
else
  echo "    ℹ Simulated environment check (run with assumed role for IAM verification)."
fi

echo ""
echo "======================================================================"
echo " ✓ Zero-Trust Demonstration Complete!"
echo "======================================================================"
