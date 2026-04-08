#!/bin/bash

echo "🔄 Resetting Cognito user..."

# ================= CONFIGURATION =================
USER_POOL_ID="us-east-1_djNRw85rf"
USERNAME="testuser@example.com"
PASSWORD="Temp123!@#ABC"  # Has uppercase, lowercase, numbers, symbols

# =============================================

echo "🗑️ Deleting existing user..."
aws cognito-idp admin-delete-user \
  --user-pool-id $USER_POOL_ID \
  --username $USERNAME 2>/dev/null

echo "📝 Creating new user..."
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username $USERNAME \
  --user-attributes Name=email,Value=$USERNAME Name=email_verified,Value=true \
  --message-action SUPPRESS

echo "🔑 Setting permanent password..."
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username $USERNAME \
  --password "$PASSWORD" \
  --permanent

echo "✅ User reset complete!"
echo "   Username: $USERNAME"
echo "   Password: $PASSWORD"
echo ""
echo "Now run: ./test-api.sh"
