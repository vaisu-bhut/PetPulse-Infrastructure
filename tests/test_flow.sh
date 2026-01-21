#!/bin/bash
# Test-PetPulse.sh

BASE_URL="https://preview.petpulse.clestiq.com"
RANDOM_VAL=$RANDOM
USERNAME="Test User $RANDOM_VAL"
EMAIL="testuser${RANDOM_VAL}@example.com"
PASSWORD="password123"
COOKIE_JAR=$(mktemp)

echo "1. Registering user $EMAIL..."
REG_BODY=$(jq -n \
                  --arg name "$USERNAME" \
                  --arg email "$EMAIL" \
                  --arg password "$PASSWORD" \
                  '{name: $name, email: $email, password: $password}')

STATUS_CODE=$(curl -s -S -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/register" \
     -H "Content-Type: application/json" \
     -d "$REG_BODY" 2>curl_error.log)

if [ "$STATUS_CODE" -ge 200 ] && [ "$STATUS_CODE" -lt 300 ]; then
    echo "   Registered."
else
    echo "   Registration failed with status $STATUS_CODE"
    echo "   Curl Error Output:"
    cat curl_error.log
    rm curl_error.log
    exit 1
fi
rm -f curl_error.log

echo "2. Logging in..."
LOGIN_BODY=$(jq -n \
                  --arg email "$EMAIL" \
                  --arg password "$PASSWORD" \
                  '{email: $email, password: $password}')

# We use -c to store cookies
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIE_JAR" -X POST "$BASE_URL/login" \
     -H "Content-Type: application/json" \
     -d "$LOGIN_BODY")

if [ "$STATUS_CODE" -ge 200 ] && [ "$STATUS_CODE" -lt 300 ]; then
    echo "   Logged in. Cookie captured."
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

RESPONSE=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/pets" \
     -H "Content-Type: application/json" \
     -d "$PET_BODY")

PET_ID=$(echo "$RESPONSE" | jq -r '.id')

if [ -n "$PET_ID" ] && [ "$PET_ID" != "null" ]; then
    echo "   Pet Created. ID: $PET_ID"
else
    echo "   Create Pet failed. Response: $RESPONSE"
    exit 1
fi

echo "4. Uploading Multiple Videos (Queue Check)..."
DUMMY_FILE="dummy.mp4"
echo "fake video content" > "$DUMMY_FILE"

UPLOAD_URL="$BASE_URL/pets/$PET_ID/upload_video"

for i in {1..3}; do
    # curl handles multipart with -F
    RESPONSE=$(curl -s -b "$COOKIE_JAR" -X POST "$UPLOAD_URL" \
        -F "video=@$DUMMY_FILE")
    
    # Parse JSON
    VIDEO_ID=$(echo "$RESPONSE" | jq -r '.video_id')
    STATUS=$(echo "$RESPONSE" | jq -r '.status')
    
    if [ -n "$VIDEO_ID" ] && [ "$VIDEO_ID" != "null" ]; then
        echo "   [$i/3] Video Uploaded. Status: $STATUS. ID: $VIDEO_ID"
    else
        echo "   [$i/3] Upload Failed. Response: $RESPONSE"
    fi
    
    sleep 0.5
done

rm "$DUMMY_FILE"

echo "5. Verifying Worker Processing (Wait)..."
sleep 5
echo "   Waited 5 seconds."

echo "   Checking Session Validity..."
USER_INFO=$(curl -s -b "$COOKIE_JAR" -X GET "$BASE_URL/users")
USER_NAME=$(echo "$USER_INFO" | jq -r '.username')

if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "null" ]; then
     echo "   User Session Valid: $USER_NAME"
else
     echo "   User Session Invalid."
fi

rm "$COOKIE_JAR"
echo "Test Complete."
