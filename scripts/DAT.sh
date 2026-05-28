#!/bin/bash
########################################################
# Apple Business Manager Device Action Tool
# Author: Jarred Wheeler
# Version: v1.0.1
#
# Features:
# - Unassign devices from MDM server
# - Release (Disown) devices from ABM through Jamf Pro
# - Single serial or CSV import
# - JWT generation with ES256 for Apple Business API unassign
# - Jamf Pro API authentication for release/disown
# - SwiftDialog progress UI
########################################################

set -euo pipefail

########################################
# Variables
########################################

icon=""
Owner=""
BATCH_SIZE=50

dialog_cmd="/usr/local/bin/dialog"

oauth_url="https://account.apple.com/auth/oauth2/v2/token"
abm_api_base="https://api-business.apple.com/v1"

access_token=""
token_expiration=0

########################################
# Dependency Check
########################################

for bin in jq curl openssl xxd uuidgen plutil; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "Missing dependency: $bin"
        exit 1
    }
done

if [[ ! -x "$dialog_cmd" ]]; then
    echo "SwiftDialog not found."
    exit 1
fi

########################################
# Helper Functions
########################################

b64url() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

pad64() {
    printf '%064s' "$1" | tr ' ' '0'
}

json_strings_from_batch() {
    printf '%s\n' "$@" | jq -R . | jq -s .
}

json_serial_objects_from_batch() {
    printf '%s\n' "$@" | jq -R '{serialNumber: .}' | jq -s .
}

getAccessToken() {
    local response current_time token_expires_in

    response=$(curl --silent --location --request POST "${jamf_url}/api/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${jamf_client_id}" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_secret=${jamf_client_secret}")

    current_time=$(date +%s)
    access_token=$(echo "$response" | plutil -extract access_token raw - 2>/dev/null || true)
    token_expires_in=$(echo "$response" | plutil -extract expires_in raw - 2>/dev/null || true)

    if [[ -z "$access_token" || -z "$token_expires_in" ]]; then
        echo "Failed to retrieve Jamf OAuth token"
        echo "$response"
        exit 1
    fi

    token_expiration=$((current_time + token_expires_in - 1))
}

checkTokenExpiration() {
    local current_time

    current_time=$(date +%s)
    if [[ -n "$access_token" && "$token_expiration" -ge "$current_time" ]]; then
        echo "Token valid until the following epoch time: $token_expiration"
    else
        echo "No valid token available, getting new token"
        getAccessToken
    fi
}

invalidateToken() {
    local responseCode

    [[ -z "$access_token" ]] && return 0

    responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${access_token}" "${jamf_url}/api/v1/auth/invalidate-token" -X POST -s -o /dev/null)
    if [[ "$responseCode" == "204" ]]; then
        echo "Token successfully invalidated"
        access_token=""
        token_expiration=0
    elif [[ "$responseCode" == "401" ]]; then
        echo "Token already invalid"
        access_token=""
        token_expiration=0
    else
        echo "An unknown error occurred invalidating the token"
    fi
}

getJamfDeviceEnrollments() {
    local response body http_code enrollment_count

    checkTokenExpiration

    response=$(
    curl -s -w '\n%{http_code}' \
        -X GET "${jamf_url}/api/v1/device-enrollments?page=0&page-size=100&sort=name:asc" \
        -H "Authorization: Bearer ${access_token}" \
        -H "Accept: application/json" \
        -H "User-Agent: ABM-Device-Action-Tool/1.0"
    )

    body=$(echo "$response" | sed '$d')
    http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" != "200" ]]; then
        if [[ "$http_code" == "403" ]]; then
            "$dialog_cmd" \
                --title "Missing Jamf API Privilege" \
                --message "Jamf denied access to list Device Enrollment instances.

Add this privilege to the Jamf API Role used by this client:

- Read Device Enrollment Program Instances

The release call also requires:

- Update Device Enrollment Program Instances" \
                --icon "SF=lock.trianglebadge.exclamationmark" \
                --button1text "OK"
        fi

        echo "Failed to retrieve Jamf Device Enrollment instances (${http_code})"
        echo "$body"
        exit 1
    fi

    enrollment_count=$(echo "$body" | jq '(.results // []) | length')

    if [[ "$enrollment_count" -eq 0 ]]; then
        "$dialog_cmd" \
            --title "No Device Enrollment Instances" \
            --message "Jamf did not return any Device Enrollment instances for this API client." \
            --icon "SF=exclamationmark.triangle" \
            --button1text "OK"
        exit 1
    fi

    jamf_enrollment_options=$(
        echo "$body" | jq -r '
            (.results // [])[]
            | .id as $id
            | (.name // .serverName // "Unnamed Device Enrollment") as $name
            | "\($id) - \($name | gsub("[,\r\n]"; " "))"
        ' | paste -sd, -
    )
}

getJamfEnrollmentSerials() {
    local response body http_code

    checkTokenExpiration

    response=$(
    curl -s -w '\n%{http_code}' \
        -X GET "${jamf_url}/api/v1/device-enrollments/${jamf_device_enrollment_id}/devices" \
        -H "Authorization: Bearer ${access_token}" \
        -H "Accept: application/json" \
        -H "User-Agent: ABM-Device-Action-Tool/1.0"
    )

    body=$(echo "$response" | sed '$d')
    http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" != "200" ]]; then
        echo "Failed to retrieve Jamf Device Enrollment devices (${http_code})"
        echo "$body"
        return 1
    fi

    jamf_enrollment_serials=$(
        echo "$body" | jq -r '
            [
                .. | objects
                | .serialNumber? // .serial_number? // .serial? // empty
                | strings
                | ascii_upcase
            ]
            | unique
            | .[]
        '
    )
}

serial_in_jamf_enrollment() {
    local serial="$1"

    [[ -z "${jamf_enrollment_serials:-}" ]] && return 1

    grep -qx "$serial" <<< "$jamf_enrollment_serials"
}

cleanup() {
    if [[ "${action:-}" == "Release (Disown)" ]]; then
        invalidateToken
    fi

    [[ -n "${dialogPID:-}" ]] && kill "$dialogPID" 2>/dev/null || true
    rm -f "${progress_file:-}"
}

trap cleanup EXIT

########################################
# Action Dialog
########################################

action_output=$(
"$dialog_cmd" \
    --title "Apple Device Action Tool" \
    --message "Choose the workflow you want to run.

Unassign (ABM) removes devices from an Apple Business Manager MDM server assignment.
Release (MDM) disowns devices through Jamf Pro's MDM/ADE integration." \
    --icon "SF=applelogo" \
    --overlayicon "$icon" \
    --button1text "Continue" \
    --button2text "Cancel" \
    --json \
    --selecttitle "Action" \
    --selectvalues "Unassign (ABM),Release (MDM)"
)

dialog_exit=$?
[[ "$dialog_exit" != "0" ]] && exit 1

action_choice=$(echo "$action_output" | jq -r '.Action.selectedValue // .SelectedOption // empty')

case "$action_choice" in
    "Unassign (ABM)")
        action="Unassign"
        ;;
    "Release (MDM)")
        action="Release (Disown)"
        ;;
    *)
        "$dialog_cmd" \
            --title "No Action Selected" \
            --message "Choose Unassign (ABM) or Release (MDM) to continue." \
            --icon "SF=exclamationmark.triangle" \
            --button1text "OK"
        exit 1
        ;;
esac

########################################
# Pathway Dialogs
########################################

client_id=""
key_id=""
mdm_server_id=""
jamf_url=""
jamf_client_id=""
jamf_client_secret=""
jamf_device_enrollment_id=""
single_serial=""
input_method=""
csv_file=""

if [[ "$action" == "Unassign" ]]; then
    dialog_output=$(
    "$dialog_cmd" \
        --title "Unassign Devices | ABM" \
        --message "Provide Apple Business Manager API credentials and choose how to load serial numbers." \
        --icon "SF=applelogo" \
        --overlayicon "$icon" \
        --button1text "Continue" \
        --button2text "Cancel" \
        --json \
        --textfield "Client ID (BUSINESSAPI...)" \
        --textfield "Key ID" \
        --textfield "MDM Server ID" \
        --selecttitle "Input Method" \
        --selectvalues "Single Serial,CSV Import" \
        --textfield "Single Serial Number"
    )

    dialog_exit=$?
    [[ "$dialog_exit" != "0" ]] && exit 1

    client_id=$(echo "$dialog_output" | jq -r '.["Client ID (BUSINESSAPI...)"] // empty')
    key_id=$(echo "$dialog_output" | jq -r '.["Key ID"] // empty')
    mdm_server_id=$(echo "$dialog_output" | jq -r '.["MDM Server ID"] // empty')
    input_method=$(echo "$dialog_output" | jq -r '.["Input Method"].selectedValue // .SelectedOption // empty')
    single_serial=$(echo "$dialog_output" | jq -r '.["Single Serial Number"] // empty')

    if [[ -z "$client_id" || -z "$key_id" || -z "$mdm_server_id" ]]; then
        "$dialog_cmd" \
            --title "Missing ABM Information" \
            --message "Client ID, Key ID, and MDM Server ID are required for Unassign (ABM)." \
            --icon "SF=exclamationmark.triangle" \
            --button1text "OK"
        exit 1
    fi

    pem_file=$(
    osascript <<EOF
POSIX path of (choose file with prompt "Select your ABM API PEM file")
EOF
    )

    [[ -z "$pem_file" ]] && exit 1
else
    dialog_output=$(
    "$dialog_cmd" \
        --title "Release Devices | MDM" \
        --message "Provide Jamf Pro API credentials. The Device Enrollment instance will be loaded from Jamf Pro." \
        --icon "SF=applelogo" \
        --overlayicon "$icon" \
        --button1text "Continue" \
        --button2text "Cancel" \
        --json \
        --textfield "Jamf Pro URL" \
        --textfield "Jamf API Client ID" \
        --textfield "Jamf API Client Secret"
    )

    dialog_exit=$?
    [[ "$dialog_exit" != "0" ]] && exit 1

    jamf_url=$(echo "$dialog_output" | jq -r '.["Jamf Pro URL"] // empty')
    jamf_client_id=$(echo "$dialog_output" | jq -r '.["Jamf API Client ID"] // empty')
    jamf_client_secret=$(echo "$dialog_output" | jq -r '.["Jamf API Client Secret"] // empty')
    jamf_url="${jamf_url%/}"

    if [[ -z "$jamf_url" || -z "$jamf_client_id" || -z "$jamf_client_secret" ]]; then
        "$dialog_cmd" \
            --title "Missing Jamf Information" \
            --message "Jamf Pro URL, Jamf API Client ID, and Jamf API Client Secret are required for Release (MDM)." \
            --icon "SF=exclamationmark.triangle" \
            --button1text "OK"
        exit 1
    fi

    checkTokenExpiration
    getJamfDeviceEnrollments

    dialog_output=$(
    "$dialog_cmd" \
        --title "Release Devices | Device Enrollment" \
        --message "Choose the Jamf Device Enrollment instance to release devices from." \
        --icon "SF=applelogo" \
        --overlayicon "$icon" \
        --button1text "Continue" \
        --button2text "Cancel" \
        --json \
        --selecttitle "Jamf Device Enrollment" \
        --selectvalues "$jamf_enrollment_options"
    )

    dialog_exit=$?
    [[ "$dialog_exit" != "0" ]] && exit 1

    jamf_enrollment_selection=$(echo "$dialog_output" | jq -r '.["Jamf Device Enrollment"].selectedValue // .SelectedOption // empty')
    jamf_device_enrollment_id=$(echo "$jamf_enrollment_selection" | awk '{print $1}')

    if [[ -z "$jamf_device_enrollment_id" ]]; then
        "$dialog_cmd" \
            --title "Missing Device Enrollment" \
            --message "Choose a Jamf Device Enrollment instance to continue." \
            --icon "SF=exclamationmark.triangle" \
            --button1text "OK"
        exit 1
    fi

    dialog_output=$(
    "$dialog_cmd" \
        --title "Release Devices | Input" \
        --message "Choose how to load serial numbers for the selected Jamf Device Enrollment instance." \
        --icon "SF=applelogo" \
        --overlayicon "$icon" \
        --button1text "Continue" \
        --button2text "Cancel" \
        --json \
        --selecttitle "Input Method" \
        --selectvalues "Single Serial,CSV Import" \
        --textfield "Single Serial Number"
    )

    dialog_exit=$?
    [[ "$dialog_exit" != "0" ]] && exit 1

    input_method=$(echo "$dialog_output" | jq -r '.["Input Method"].selectedValue // .SelectedOption // empty')
    single_serial=$(echo "$dialog_output" | jq -r '.["Single Serial Number"] // empty')
fi

if [[ "$input_method" == "CSV Import" ]]; then
    single_serial=""

    csv_file=$(
    osascript <<EOF
POSIX path of (choose file with prompt "Select CSV containing serial numbers")
EOF
    )

    [[ -z "$csv_file" ]] && exit 1
else
    input_method="Single Serial"
fi

if [[ "$input_method" == "Single Serial" && -z "$single_serial" ]]; then
    "$dialog_cmd" \
        --title "Missing Serial Number" \
        --message "A single serial number is required when Single Serial is selected." \
        --icon "SF=exclamationmark.triangle" \
        --button1text "OK"
    exit 1
fi

########################################
# Load Serials
########################################

serials=()

if [[ -n "$single_serial" ]]; then
    clean_serial=$(echo "$single_serial" | tr -d '\r' | xargs | tr '[:lower:]' '[:upper:]')
    [[ -n "$clean_serial" ]] && serials+=("$clean_serial")
fi

if [[ -n "$csv_file" && -f "$csv_file" ]]; then
    while IFS= read -r line; do
        clean=$(echo "$line" | tr -d '\r' | xargs | tr '[:lower:]' '[:upper:]')
        [[ -n "$clean" ]] && serials+=("$clean")
    done < "$csv_file"
fi

total=${#serials[@]}

if [[ "$total" -eq 0 ]]; then
    "$dialog_cmd" \
        --title "No Devices Found" \
        --message "No serial numbers were loaded." \
        --icon "SF=xmark.circle" \
        --button1text "OK"
    exit 1
fi

echo "Loaded $total serial(s)"

if [[ "$action" == "Release (Disown)" && "$input_method" == "CSV Import" ]]; then
    "$dialog_cmd" \
        --title "Confirm Device Release" \
        --message "You are about to release ${total} device serial number(s) loaded from the selected CSV.

This will disown the devices from Apple Business Manager through the selected Jamf Device Enrollment instance." \
        --icon "SF=exclamationmark.triangle" \
        --overlayicon "$icon" \
        --button1text "Release Devices" \
        --button2text "Cancel" \
        --ontop

    dialog_exit=$?
    [[ "$dialog_exit" != "0" ]] && exit 1
fi

if [[ "$action" == "Unassign" ]]; then
    ########################################
    # JWT Generation
    ########################################

    audience="$oauth_url"
    alg="ES256"

    iat=$(date -u +%s)
    exp=$((iat + 300))
    jti=$(uuidgen)

    jwt_header=$(
    jq -nc \
        --arg alg "$alg" \
        --arg kid "$key_id" \
        '{
            alg:$alg,
            kid:$kid,
            typ:"JWT"
        }'
    )

    jwt_payload=$(
    jq -nc \
        --arg sub "$client_id" \
        --arg aud "$audience" \
        --arg iss "$client_id" \
        --arg jti "$jti" \
        --argjson iat "$iat" \
        --argjson exp "$exp" \
        '{
            sub:$sub,
            aud:$aud,
            iss:$iss,
            jti:$jti,
            iat:$iat,
            exp:$exp
        }'
    )

    header_b64=$(printf '%s' "$jwt_header" | b64url)
    payload_b64=$(printf '%s' "$jwt_payload" | b64url)

    signing_input="${header_b64}.${payload_b64}"

    sigfile=$(mktemp)

    printf '%s' "$signing_input" | openssl dgst -binary -sha256 -sign "$pem_file" > "$sigfile"

    asn1_output=$(openssl asn1parse -in "$sigfile" -inform DER)

    r_hex=$(echo "$asn1_output" | awk -F: '/INTEGER/ {print $NF; exit}')
    s_hex=$(echo "$asn1_output" | awk -F: '/INTEGER/ {count++} count==2 {print $NF; exit}')

    rm -f "$sigfile"

    r=$(pad64 "$r_hex")
    s=$(pad64 "$s_hex")

    signature=$(
    printf '%s' "${r}${s}" | \
    xxd -r -p | \
    openssl base64 -A | \
    tr '+/' '-_' | \
    tr -d '='
    )

    jwt="${signing_input}.${signature}"

    echo "JWT generated"

    ########################################
    # OAuth Token Request
    ########################################

    token_response=$(
    curl -s "$oauth_url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=$client_id" \
        --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
        --data-urlencode "client_assertion=$jwt" \
        --data-urlencode "scope=business.api"
    )

    ACCESS_TOKEN=$(echo "$token_response" | jq -r '.access_token')

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        echo "Failed to retrieve OAuth token"
        echo "$token_response" | jq .
        exit 1
    fi

    echo "OAuth token retrieved"
else
    checkTokenExpiration
    if getJamfEnrollmentSerials; then
        missing_serials=()

        for serial in "${serials[@]}"; do
            if ! serial_in_jamf_enrollment "$serial"; then
                missing_serials+=("$serial")
            fi
        done

        if [[ "${#missing_serials[@]}" -gt 0 ]]; then
            missing_list=$(printf '%s\n' "${missing_serials[@]}" | sed 's/^/- /')

            "$dialog_cmd" \
                --title "Serials Not Found in ADE Instance" \
                --message "The selected Jamf Device Enrollment instance does not currently list these serial numbers:

${missing_list}

Check that the devices are assigned to this MDM server in Apple Business Manager and that Jamf has synced Automated Device Enrollment." \
                --icon "SF=exclamationmark.triangle" \
                --button1text "OK"
            exit 1
        fi
    fi

    echo "Jamf OAuth token retrieved"
fi

########################################
# Progress Dialog
########################################

progress_file="/tmp/abm_progress.log"

rm -f "$progress_file"
touch "$progress_file"

"$dialog_cmd" \
    --title "Apple Business Manager | ${action}" \
    --message "Initializing..." \
    --icon "SF=applelogo" \
    --overlayicon "$icon" \
    --progress "$total" \
    --progresstext "Starting..." \
    --button1disabled \
    --commandfile "$progress_file" \
    --moveable \
    --ontop &

dialogPID=$!

sleep 2

########################################
# Processing
########################################

success_count=0
failed_count=0

for (( i=0; i<total; i+=BATCH_SIZE )); do

    batch=("${serials[@]:i:BATCH_SIZE}")

    current_batch=$(( (i / BATCH_SIZE) + 1 ))
    total_batches=$(( (total + BATCH_SIZE - 1) / BATCH_SIZE ))

    echo "message: Processing batch ${current_batch} of ${total_batches}

Processed: $i / $total
Success: $success_count
Failed: $failed_count" >> "$progress_file"

    ####################################
    # Build Device Payload
    ####################################

    if [[ "$action" == "Unassign" ]]; then

        devices_json=$(json_serial_objects_from_batch "${batch[@]}")

        payload=$(
        jq -nc \
            --arg mdmServerId "$mdm_server_id" \
            --argjson devices "$devices_json" \
            '{
                mdmServerId:$mdmServerId,
                devices:$devices
            }'
        )

        endpoint="${abm_api_base}/devices/unassign"

    else

        devices_json=$(json_strings_from_batch "${batch[@]}")

        payload=$(
        jq -nc \
            --argjson devices "$devices_json" \
            '{
                devices:$devices
            }'
        )

        endpoint="${jamf_url}/api/v1/device-enrollments/${jamf_device_enrollment_id}/disown"

    fi

    ####################################
    # API Call
    ####################################

    if [[ "$action" == "Unassign" ]]; then
        response=$(
        curl -s -w '\n%{http_code}' \
            -X POST "$endpoint" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -H "User-Agent: ABM-Device-Action-Tool/1.0" \
            -d "$payload"
        )
    else
        checkTokenExpiration

        response=$(
        curl -s -w '\n%{http_code}' \
            -X POST "$endpoint" \
            -H "Authorization: Bearer $access_token" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "User-Agent: ABM-Device-Action-Tool/1.0" \
            -d "$payload"
        )
    fi

    body=$(echo "$response" | sed '$d')
    http_code=$(echo "$response" | tail -n1)

    ####################################
    # Response Handling
    ####################################

    if [[ "$http_code" == "200" || "$http_code" == "201" || "$http_code" == "202" ]]; then

        echo "Batch ${current_batch} successful"

        success_count=$((success_count + ${#batch[@]}))

    else
        if [[ "$action" == "Release (Disown)" ]] && echo "$body" | jq -e '.errors[]? | select((.description // "") == "Invalid session token.")' >/dev/null 2>&1; then
            "$dialog_cmd" \
                --title "Jamf ADE Session Failed" \
                --message "Jamf returned: Invalid session token.

The Jamf API token was accepted, so this usually points to Jamf's Automated Device Enrollment server-token session with Apple, not the API client credential.

In Jamf Pro, open Settings > Global Management > Automated Device Enrollment, select the Device Enrollment instance, then verify or renew the server token and run a sync. After Jamf can sync ADE successfully, retry this release." \
                --icon "SF=exclamationmark.triangle" \
                --button1text "OK"
        fi

        echo "API Error (${http_code})"
        echo "$body"
        echo "Submitted payload:"
        echo "$payload" | jq .

        failed_count=$((failed_count + ${#batch[@]}))

    fi

    processed=$(( success_count + failed_count ))

    echo "progress: $processed" >> "$progress_file"

    echo "message: Processing batch ${current_batch} of ${total_batches}

Processed: ${processed} / ${total}
Success: ${success_count}
Failed: ${failed_count}" >> "$progress_file"

    sleep 1

done

########################################
# Finish Progress
########################################

echo "progress: complete" >> "$progress_file"

sleep 2

########################################
# Final Dialog
########################################

"$dialog_cmd" \
    --title "ABM Processing Complete" \
    --message "Action: ${action}

Total Devices: ${total}
Success: ${success_count}
Failed: ${failed_count}" \
    --icon "SF=applelogo" \
    --overlayicon "$icon" \
    --button1text "OK" \
    --ontop \
    --timer 15

echo "Done"
