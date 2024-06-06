#!/bin/bash

wget -qOenvironment_variables.sh https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/gitpod/environment_variables.sh
chmod 0755 environment_variables.sh
ENV_OUTPUT=$(bash ./environment_variables.sh)
DELIMITER=" % "
IFS="$DELIMITER" read -ra parts <<< "$ENV_OUTPUT"
API="${parts[0]}"
REPO_ID="${parts[1]}"
TEST_V="${parts[2]}"

if (( $(echo "$TEST_V < 8" | bc -l) )); then
  echo "old test, exiting..."
  exit 1
fi

port=$1
ques_type=$2

update_setup_status="$API/api/v1/update-setup-status/"
verify_connection_url="$API/api/v1/verify-connection/"

# Function to make a cURL call
function make_curl_call() {
  local method=$1
  local url=$2
  local data=$3
  local test_uuid=$4
  local question_id=$5
  local user_id=$6
  local response
  if [ "$test_uuid" = "NULL" ]; then
    # Remove the "uuid" field from the JSON data
    data=$(jq 'del(.test_uuid)' <<< "$data")
  fi
  response=$(curl --location --request "$1" "$2" --header 'Content-Type: application/json' --data-raw "$data")
  if [ $? -ne 0 ]; then
    errorHandler "$?" "cURL call failed with exit code: $?" "$4" "$5" "$6"
    exit $?
  fi
}

function errorHandler() {
  local exit_code=$1
  local error_string=$2
  local test_uuid=$3
  local question_id=$4
  local user_id=$5
  wget -qOenhanced_error_handler.sh https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/gitpod/enhanced_error_handler.sh
  chmod 0755 enhanced_error_handler.sh
  bash ./enhanced_error_handler.sh "$exit_code" "$error_string" "$test_uuid" "$question_id" "$user_id"
  exit $exit_code
}

function set_status() {
  local test_uuid=$1
  local question_id=$2
  local user_id=$3
  local status=$4
  echo "Setting status to " "$status"

  make_curl_call "PUT" "$update_setup_status" "$(cat <<EOF
{
      "user_id": "$user_id",
      "ques_id": "$question_id",
      "repo_id": "$REPO_ID",
      "test_uuid": "$test_uuid",
      "status": "$status"
}
EOF
)" "$1" "$2" "$3"
}

check_port_up() {
  install_nc=$(sudo apt-get install -y netcat)
  if nc -z localhost "$port" || ( [ "$ques_type" = "WEB_MICRO_PROJECT" ] && nc -z localhost 9515 ); then
    echo "All ports are up."
    # Mark starting connection verification
    echo "Server successfully."
    set_status "$uuid" "$ques_id" "$user_id" "STARTING_CONN_VERIFY"
  else
    echo "One or more ports are down."
    set_status "$uuid" "$ques_id" "$user_id" "SRVR_CONN_FAILED"
    exit 1
  fi
}

verify_connection() {
  local url=$1
  local ques_type=$2
  local test_uuid=$3
  local ques_id=$4
  local user_id=$5

  echo "verifying connection"
  data=$(cat <<EOF
{
    "ques_type":"$ques_type",
    "url": "$url",
    "repo_id": "$REPO_ID",
    "ques_id": "$ques_id",
    "test_uuid": "$test_uuid",
    "mode": "2"
    $(if [ "$ques_type" = "WEB_MICRO_PROJECT" ]; then echo ',"chrome_url": "'"$(gp url 9515)"'"'; fi)
}
EOF
)
  if [ "$test_uuid" = "NULL" ]; then
    # Remove the "uuid" field from the JSON data
    data=$(jq 'del(.test_uuid)' <<< "$data")
  fi

  echo "Invoking verify connection curl request"
  response=$(curl -sS --location --request POST "$verify_connection_url" --header 'Content-Type: application/json' --data-raw "$data")
  status=$(jq -r '.status' <<< "$response")
  if [ "$status" = "true" ]; then
    commit_count=$(git rev-list --count origin/master)
    if [ "$commit_count" -ge 2 ]; then
      set_status "$test_uuid" "$ques_id" "$user_id" "VERIFIED_COMMIT"
    else
      set_status "$test_uuid" "$ques_id" "$user_id" "VERIFYING_COMMIT"
    fi
  else
    set_status "$test_uuid" "$ques_id" "$user_id" "CONN_VERIFY_FAILED"
  fi
}

# Arguments
repo_details=$(env | grep GITPOD_REPO_ROOTS | cut -d'=' -f2)
IFS='-' read -ra arr <<< "$repo_details"
if [ "${arr[0]}" = "/workspace/test" ]; then
  uuid="${arr[3]}"
  user_id="${arr[4]}"
elif [ "${arr[0]}" = "/workspace/question" ]; then
  uuid="NULL"
  user_id="${arr[2]}"
fi
ques_id="${arr[1]}"

# workspace_url=$(env | grep -oP '(?<=GITPOD_WORKSPACE_URL=).*')
# url="https://${workspace_url/https:\/\//https:\/\/$port-}"
# Generating the URL with port appended using parameter expansion
# url="https://${GITPOD_WORKSPACE_URL/https:\/\//https:\/\/$port-}"
url=$(gp url $port)


# check if port is up
echo "checking port"
check_port_up

verify_connection "$url" "$ques_type" "$uuid" "$ques_id" "$user_id"
