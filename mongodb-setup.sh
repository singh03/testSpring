set -e
sudo mkdir -p /data/db
sudo chown -R $USER:$USER /data/db
wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add -
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list
sudo apt-get update
cd /tmp
wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb
cd 
sudo apt-get install -y mongodb-org
# BIND TO ALL ADAPTERS IN CONTAINER
sudo sed -i "s,\\(^[[:blank:]]*bindIp:\\) .*,\\1 0.0.0.0," /etc/mongod.conf
sudo /usr/bin/mongod --port 27017 --dbpath /data/db >/dev/null 2>&1 &
ps aux | grep mongo
sleep 5
wget https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/backend-project/database/mongo-database.js
mongo < mongo-database.js
rm -rf mongo-database.js
