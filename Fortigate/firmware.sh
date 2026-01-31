bash << 'EOF'
set -e

echo "API_URL=$API_URL"
[[ -n "$API_TOKEN" ]] && echo "API_TOKEN is set"

curl -sk \
  -H "Authorization: Bearer $API_TOKEN" \
  "${API_URL%/}/api/v2/monitor/system/status"
EOF
