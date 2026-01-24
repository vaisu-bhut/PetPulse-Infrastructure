#!/bin/bash
# Test-PetPulse.sh
# Usage: ./test_flow.sh [base_url]

# Default to preview environment
BASE_URL="${1:-https://preview.petpulse.clestiq.com}"
echo "Testing against: $BASE_URL"

RANDOM_VAL=$RANDOM
USERNAME="Test User $RANDOM_VAL"
EMAIL="testuser${RANDOM_VAL}@example.com"
PASSWORD="password123"
COOKIE_JAR="cookies.txt"

# Cleanup function
cleanup() {
    rm -f "$COOKIE_JAR"
    # Keep video for future runs to save bandwidth? Or delete?
    # rm -f test.mp4
}
trap cleanup EXIT

echo "1. Registering user $EMAIL..."
REG_BODY=$(jq -n \
                  --arg name "$USERNAME" \
                  --arg email "$EMAIL" \
                  --arg password "$PASSWORD" \
                  '{name: $name, email: $email, password: $password}')

STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$BASE_URL/register" \
     -H "Content-Type: application/json" \
     -d "$REG_BODY")

if [ "$STATUS_CODE" -ge 200 ] && [ "$STATUS_CODE" -lt 300 ]; then
    echo "   Registered."
else
    echo "   Registration failed with status $STATUS_CODE"
    exit 1
fi

echo "2. Logging in..."
LOGIN_BODY=$(jq -n \
                  --arg email "$EMAIL" \
                  --arg password "$PASSWORD" \
                  '{email: $email, password: $password}')

STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$BASE_URL/login" \
     -H "Content-Type: application/json" \
     -d "$LOGIN_BODY")

if [ "$STATUS_CODE" -ge 200 ] && [ "$STATUS_CODE" -lt 300 ]; then
    echo "   Logged in."
else
    echo "   Login failed with status $STATUS_CODE"
    exit 1
fi

echo "3. Creating Pet..."
PET_BODY=$(jq -n \
                --arg name "TestDog" \
                --arg species "Dog" \
                --argjson age 5 \
                --arg breed "Labrador" \
                --arg bio "Good boy" \
                '{name: $name, species: $species, age: $age, breed: $breed, bio: $bio}')

RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$BASE_URL/pets" \
     -H "Content-Type: application/json" \
     -d "$PET_BODY")

PET_ID=$(echo "$RESPONSE" | jq -r '.id')

if [ -n "$PET_ID" ] && [ "$PET_ID" != "null" ]; then
    echo "   Pet Created. ID: $PET_ID"
else
    echo "   Create Pet failed. Response: $RESPONSE"
    exit 1
fi

echo "4. Getting Video File..."
if [ ! -s test.mp4 ]; then
    echo "   Downloading sample test.mp4..."
    rm -f test.mp4
    curl -fL "https://www.w3schools.com/html/mov_bbb.mp4" -o test.mp4
else
    echo "   Using existing test.mp4"
fi

echo "5. Uploading Video..."
UPLOAD_URL="$BASE_URL/pets/$PET_ID/upload_video"

# Upload one video
RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$UPLOAD_URL" \
    -F "video=@test.mp4")

VIDEO_ID=$(echo "$RESPONSE" | jq -r '.video_id')
STATUS=$(echo "$RESPONSE" | jq -r '.status')

if [ -n "$VIDEO_ID" ] && [ "$VIDEO_ID" != "null" ]; then
    echo "   Video Uploaded. Status: $STATUS. ID: $VIDEO_ID"
else
    echo "   Upload Failed. Response: $RESPONSE"
    rm -f "$COOKIE_JAR"
    exit 1
fi

echo "6. Waiting for Processing..."
# Wait loop to check verification (if we had a status endpoint)
# For now, just wait a bit to ensure it doesn't crash immediately
for i in {1..10}; do
    echo -n "."
    sleep 1
done
echo ""

echo "7. Verifying Session & Pet Access..."
USER_INFO=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X GET "$BASE_URL/users")
USER_NAME=$(echo "$USER_INFO" | jq -r '.name')

if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "null" ]; then
     echo "   User Session Valid: $USER_NAME"
else
     echo "   User Session Invalid."
     rm -f "$COOKIE_JAR"
     exit 1
fi

# Cleanup
echo "Test Complete. Success!"
