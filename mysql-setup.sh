# MySQL Setup
set -e
sudo install-packages mysql-server
sudo mkdir -p /var/run/mysqld /var/log/mysql
sudo chown -R gitpod:gitpod /etc/mysql /var/run/mysqld /var/log/mysql /var/lib/mysql /var/lib/mysql-files /var/lib/mysql-keyring /var/lib/mysql-upgrade
wget -qOmysqld.cnf https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/backend-project/gitpod/mysqld.cnf 
sudo mv mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf 
wget -qOclient.cnf https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/backend-project/gitpod/client.cnf 
sudo mv client.cnf /etc/mysql/mysql.conf.d/ 
wget -qOmysql-bashrc-launch.sh https://codejudge-starter-repo-artifacts.s3.ap-south-1.amazonaws.com/backend-project/gitpod/mysql-bashrc-launch.sh 
chmod 0755 mysql-bashrc-launch.sh
sudo mv mysql-bashrc-launch.sh /etc/mysql/mysql-bashrc-launch.sh 
. "/etc/mysql/mysql-bashrc-launch.sh"
sudo mysql -e "ALTER USER root@localhost IDENTIFIED WITH mysql_native_password BY 'admin'"
sudo mysql -u root --password=admin -e "create database db"
