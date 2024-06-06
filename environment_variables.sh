#!/bin/bash

# Run the gp env command and capture its output
env_output=$(gp env)
DELIMITER=" % "
# Read and store env variables from env_output
while IFS= read -r line; do
  if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    variable="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    export "$variable=$value"
  fi
done <<< "$env_output"

# Common API URLs
if [ "$ENV_TYPE" = "PROD" ]; then
  export API="https://console.codejudge.io"
else
  export API="http://codejudge-dev-env1.hbysuh5hy8.us-east-1.elasticbeanstalk.com"
fi

if [ "$1" = "WEB_MICRO" ]; then
  bc1Download=$(sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E88979FB9B30ACF2)
fi

bcDownload=$(sudo apt-get update && sudo apt install bc)
if [ -n "$TEST_V" ] && [ "$(echo "$TEST_V >= 8" | bc -l)" -eq 1 ]; then
  # Do nothing if test_v is 8 or greater
  :
else
  # If test_v is blank or less than 8, set version to 7
  export TEST_V=7
fi

echo "$API$DELIMITER$REPO_ID$DELIMITER$TEST_V"