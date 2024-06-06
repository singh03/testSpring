
#!/bin/bash

wget -qOenvironment_variables.sh https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/gitpod/environment_variables.sh
chmod 0755 environment_variables.sh
ENV_OUTPUT=$(bash ./environment_variables.sh)
DELIMITER=" % "
IFS="$DELIMITER" read -ra parts <<< "$ENV_OUTPUT"
API="${parts[0]}"
REPO_ID="${parts[1]}"
TEST_V="${parts[2]}"

update_setup_status="$API/api/v1/update-setup-status/"
store_user_port_and_url="$API/api/v3/store-user-url/"
verify_connection_url="$API/api/v1/verify-connection/"

# Read language name and VERSION from command line arguments
LANG=$1
VERSION=$2
FRAMEWORK=$3
FRAMEWORK_VERSION=$4
use_gradle=$5

# Function to handle errors
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

# Function to make a cURL call
function make_curl_call() {
  local method=$1
  local url=$2
  local data=$3
  local test_uuid=$4
  local question_id=$5
  local user_id=$6
  
  if [ "$test_uuid" = "NULL" ]; then
    # Remove the "uuid" field from the JSON data
    data=$(jq 'del(.test_uuid)' <<< "$data")
  fi
  
  if (( $(echo "$TEST_V > 7" | bc -l) )); then
    curl --location --request "$method" "$url" --header 'Content-Type: application/json' --data-raw "$data"
    if [ $? -ne 0 ]; then
      errorHandler "$?" "cURL call failed with exit code: $?" "$test_uuid" "$question_id" "$user_id"
      exit $?
    fi
  fi
}

function set_status() {
  local test_uuid=$1
  local question_id=$2
  local user_id=$3
  local status=$4

  make_curl_call "PUT" "$update_setup_status" "$(cat <<EOF
{
      "user_id": "$user_id",
      "ques_id": "$question_id",
      "test_uuid": "$test_uuid",
      "repo_id": "$REPO_ID",
      "status": "$status"
}
EOF
)" "$test_uuid" "$question_id" "$user_id"
}

# Function to install Languages and their environment
function install_server() {
  local test_uuid=$1
  local question_id=$2
  local user_id=$3
  
  case $LANG in
    "ruby")
      # Install Ruby using RVM
      . "$HOME/.rvm/scripts/rvm" 
      rvm pkg install openssl
      rvm_install_output=$(rvm install $VERSION -C --with-openssl-dir=$HOME/.rvm/usr 2>&1 | tee /dev/tty)
      if [ "$?" -ne "0" ]; then
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Ruby installation failed with exit code: $? and $rvm_install_output" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      echo 'export PATH=$PATH:$HOME/.rvm/rubies/'$VERSION'/bin/' >> $HOME/.bashrc
      ;;

    "python")
      # Install Python using pyenv
      echo "Pyenv Installing"
      installation=$(pyenv install $VERSION -s && pyenv local $VERSION 2>&1)
      if [ "$?" -eq "0" ]; then
        echo "Pyenv installation and setup completed"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Installation failed with exit code: $? and $installation" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi

      # Start Install pip
      echo "$FRAMEWORK installing"
      upgraded_pip=$(pip install --upgrade pip && python -m pip install $FRAMEWORK==$FRAMEWORK_VERSION && pip install -r requirements.txt 2>&1 | tee /dev/tty)
      if [ "$?" -eq "0" ]; then
        echo "$FRAMEWORK installation compeleted"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Failed to install $FRAMEWORK and $framework_install" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi

      if [ "$FRAMEWORK" == "Django" ]; then
        python -m pip install pytz==2019.2
        if [ "$?" -ne "0" ]; then
          set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
          errorHandler $? "Failed to install pytz" "$test_uuid" "$question_id" "$user_id"
          exit $?
        fi
      fi
      ;;

    "php")
      # Install PHP using update-alternatives
      
      echo "Composer update started"
      upgraded_comp=$(sudo composer self-update --1 && sudo update-alternatives --set php /usr/bin/php$VERSION 2>&1 | tee /dev/tty)
      if [ "$?" -eq "0" ]; then
        echo "composer updation compeleted"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Failed to update composer and $upgraded_comp" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi

      echo "PHP installation started"
      installation=$(sudo add-apt-repository -y ppa:ondrej/php | tee /dev/tty && sudo apt-get -y update | tee /dev/tty && sudo apt-get -y install php$VERSION-curl 2>&1 | tee /dev/tty)
      if [ "$?" -eq "0" ]; then
        echo "PHP installation completed"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "PHP Installation failed with exit code: $? and $installation" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      echo "Package installation started"
      if [ "$FRAMEWORK" == "Laravel" ]; then
        pack_install=$(composer update && composer install && npm i && php artisan key:generate 2>&1 | tee /dev/tty)
      else
        pack_install=$(composer update && composer install 2>&1 | tee /dev/tty)
      fi
      if [ "$?" -eq "0" ]; then
        echo "Package Installation completed, Initiating database setup"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "PHP Package Installation failed with exit code: $? and $pack_install" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      ;;

    "node")
      # Install Node.js using NVM  
      . "$HOME/.nvm/nvm.sh"
      echo "Node.js installation started"
      installation=$(nvm install $VERSION 2>&1 | tee /dev/tty)
      nvm use $VERSION
      nvm alias default $VERSION
      if [ "$?" -eq "0" ]; then
        echo "Node.js installation completed"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Node.js installation failed with exit code: $? and $installation" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      echo "Package installation started"
      pack_install=$(npm install 2>&1 | tee /dev/tty)
      if [ "$?" -eq "0" ]; then
        echo "Package Installation completed, Initiating database setup"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Package installation failed with exit code: $? and $pack_install" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      ;;

    "java")
      # Install Java using SDKMAN
      sed_output=$(sed -i 's/sdkman_auto_answer=false/sdkman_auto_answer=true/g' "$HOME/.sdkman/etc/config" 2>&1 | tee /dev/tty)
      if [ "$?" -ne "0" ]; then
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Download failed. Failed to modify SDKMAN configuration using sed. Error: $sed_output" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      
      source "$HOME/.sdkman/bin/sdkman-init.sh" 2>&1
      if [ "$?" -ne "0" ]; then
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "SDKMAN initialization failed. Failed to initialize SDKMAN. Make sure SDKMAN is properly installed and initialized." "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      
      echo "Java installation started"
      installation=$(sdk install java $VERSION 2>&1 | tee /dev/tty)
      if [ "$?" -eq "0" ]; then
        echo "Java Installation completed"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Installation failed with exit code: $?. $installation" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      echo "Package installation started"
      if [ "$use_gradle" == "use_gradle" ]; then
        pack_install=$(./gradlew build 2>&1 | tee /dev/tty)
      else
        pack_install=$(mvn clean install 2>&1 | tee /dev/tty)
      fi
      if [ "$?" -eq "0" ]; then
        echo "Package Installation completed, Initiating database setup"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Package Installation failed with exit code: $?. $pack_install" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      ;;
    "go")
      echo "Package installation started"
      install_commands=$(cat <<EOF
sudo apt-get install -y bison || exit \$?
bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer) || exit \$?
source /home/gitpod/.gvm/scripts/gvm || exit \$?
gvm install go$VERSION || exit \$?
gvm use go$VERSION || exit \$?
EOF
)
      eval "$install_commands"
      go_build=$(go build -o main . 2>&1 | tee /dev/tty)
      if [ "$?" -eq "0" ]; then
        echo "Package Installation completed, Initiating database setup"
      else
        set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
        errorHandler $? "Package installation failed with exit code: $?. $go_build" "$test_uuid" "$question_id" "$user_id"
        exit $?
      fi
      ;;
    *)
      # echo "Unsupported language: $LANG"
      # exit 1
      ;;
  esac
}

# Function to set up MySQL
function setup_mysql() {
  echo "here"
  local test_uuid=$1
  local question_id=$2
  local user_id=$3
  wget -qOmysql-setup.sh https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/gitpod/database/mysql-test-setup.sh
  chmod 0755 mysql-setup.sh

  bash mysql-setup.sh
  # if [ $? -ne 0 ]; then
    # set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
    # errorHandler "$?" "MySQL setup command failed with exit code: $?" "$test_uuid" "$question_id" "$user_id"
  # fi
  echo "MySQL setup successfully"
}

# Function to set up MongoDB
function setup_mongodb() {
  local test_uuid=$1
  local question_id=$2
  local user_id=$3
  wget -qOmongodb-setup.sh https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/gitpod/database/mongo-db-setup.sh
  chmod 0755 mongodb-setup.sh

  bash mongodb-setup.sh
  # if [ $? -ne 0 ]; then
  #   set_status "$test_uuid" "$question_id" "$user_id" "ENV_SETUP_FAILED"
  #   errorHandler "$?" "MongoDB setup command failed with exit code: $?" "$test_uuid" "$question_id" "$user_id"
  # fi
  echo "MongoDB setup successfully"
}

# Start Server for LANG
function start_server() {
  local test_uuid=$1
  local question_id=$2
  local user_id=$3

  echo "Starting Server..."

  case "$LANG" in
  "node")
    start_server=$(npm start 2>&1 | tee /dev/tty)
    ;;
  "python")
    if [ "$FRAMEWORK" == "Django" ]; then
      start_server=$(python manage.py runserver 0.0.0.0:$port 2>&1 | tee /dev/tty)
    else
      start_server=$(python restapi.py 2>&1 | tee /dev/tty)
    fi
    ;;
  "java")
    # Start Java server
    if [ "$use_gradle" == "use_gradle" ]; then
      start_server=$(java -jar ./build/libs/spring-boot-in-docker.jar 2>&1 | tee /dev/tty)
    else
      start_server=$(java -jar ./target/spring-boot-in-docker.jar 2>&1 | tee /dev/tty)
    fi
    ;;
  "php")
    if [ "$FRAMEWORK" == "Laravel" ]; then
      start_server=$(php artisan serve --host=127.0.0.1 --port=$port 2>&1 | tee /dev/tty)
    elif [ "$FRAMEWORK" == "Symfony" ]; then
      start_server=$(php -S 127.0.0.1:$port -t public 2>&1 | tee /dev/tty)
    else
      start_server=$(php -S 127.0.0.1:$port 2>&1 | tee /dev/tty)
    fi
    ;;
  "go")
    start_server=$(./main)
    ;;
  *)
    # echo "Invalid LANG: $LANG"
    # exit 1
    ;;
  esac
  if [ "$?" -ne "0" ]; then
    set_status "$2" "$3" "SRVR_CONN_FAILED"
    errorHandler $? "Failed to start server for $LANG with exit code: $? $start_server" "$test_uuid" "$question_id" "$user_id"
    exit $?
  fi
}

# Arguments
repo_details=$(env | grep GITPOD_REPO_ROOTS | cut -d'=' -f2)
IFS='-' read -ra arr <<< "$repo_details"
port=8080
type="Server"
util_type=""
mode=2
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
url=$(gp url $port)

# Store user port and URL
make_curl_call "POST" "$store_user_port_and_url" "$(cat <<EOF
{
    "url": "$url",
    "port": "$port",
    "type": "$type",
    "util_type": "$util_type",
    "mode": "$mode",
    "setup_status": "SETTING_UP_ENV",
    "repo_id": "$REPO_ID",
    "ques_id": "$ques_id",
    "test_uuid": "$uuid",
    "user_id": "$user_id"
}
EOF
)" "$uuid" "$ques_id" "$user_id"

# Install Backend
install_server "$uuid" "$ques_id" "$user_id"

# MySQL Setup
if type mysql >/dev/null 2>&1; then
  echo "MySQL is already present."
else
  setup_mysql "$uuid" "$ques_id" "$user_id"
fi

# MongoDB Setup
if type mongo >/dev/null 2>&1; then
  echo "MongoDB is already present."
else
  setup_mongodb "$uuid" "$ques_id" "$user_id"
fi


# Mark starting server
set_status "$uuid" "$ques_id" "$user_id" "STARTING_SRVR"

# start_server 
start_server "$uuid" "$ques_id" "$user_id"
