#!/bin/bash

echo "🚀 Starting API Test..."

# ================= CONFIGURATION =================
USER_POOL_ID="us-east-1_djNRw85rf"
CLIENT_ID="2ov902rk807n4m0lpj25k30lfn"
USERNAME="testuser@example.com"
PASSWORD="Temp123!@#ABC"

API_ENDPOINT="https://5u5oz0pvgb.execute-api.us-east-1.amazonaws.com/production/tasks"

# =============================================

echo "👤 Setting user password..."
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username $USERNAME \
  --password "$PASSWORD" \
  --permanent 2>/dev/null

if [ $? -ne 0 ]; then
  echo "📝 User doesn't exist. Creating user..."
  
  aws cognito-idp admin-create-user \
    --user-pool-id $USER_POOL_ID \
    --username $USERNAME \
    --user-attributes Name=email,Value=$USERNAME Name=email_verified,Value=true \
    --message-action SUPPRESS > /dev/null 2>&1
  
  aws cognito-idp admin-set-user-password \
    --user-pool-id $USER_POOL_ID \
    --username $USERNAME \
    --password "$PASSWORD" \
    --permanent > /dev/null 2>&1
  
  echo "✅ User created and password set!"
else
  echo "✅ User password verified."
fi

echo ""
echo "🔑 Getting Cognito token..."

# CHANGE: AccessToken -> IdToken
TOKEN=$(aws cognito-idp admin-initiate-auth \
  --user-pool-id $USER_POOL_ID \
  --client-id $CLIENT_ID \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=$USERNAME,PASSWORD=$PASSWORD" \
  --query 'AuthenticationResult.IdToken' \
  --output text 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "None" ]; then
  echo "❌ Failed to get token."
  exit 1
fi

echo "✅ Token retrieved successfully!"
echo ""
echo "📡 Calling API..."

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  "$API_ENDPOINT")

BODY=$(echo "$RESPONSE" | sed -e 's/HTTP_STATUS:.*//g')
HTTP_STATUS=$(echo "$RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

echo "────────────────────────────────────"
echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" -eq 200 ]; then
  echo "✅ Success!"
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
else
  echo "❌ Request failed"
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
fi
