#!/bin/bash
set -euxo pipefail

#Backup and safely update sysctl settings
cp /etc/sysctl.conf /root/sysctl.conf_backup
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
echo "fs.file-max=65536" >> /etc/sysctl.conf
sysctl -p

#Set user limits properly
cp /etc/security/limits.conf /root/sec_limit.conf_backup
echo "sonarqube = nofile   65536" >> /etc/security/limits/.conf
echo "sonarqube = nproc    4096" >> /etc/security/limits/.conf

#Install Java
sudo apt update -y
sudo apt install -y openjdk-21-jdk

#Install PostgreSQL
wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -0 - | apt-key add -
sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
apt-get update -y
apt-get install postgresql postgresql-contrib -y
systemctl enable postgresql -y 
systemctl start postgresql

#Setup PostgreSQL user and DB for SonarQube
echo "postgres:admin123" | chpasswd
runusr -l postgres -c "createuser sonar"
runusr -l postgres -c "psql -c \"ALTER USER sonar WITH ENCRYPTED PASSWORD 'admin123';\""
runusr -l postgres -c "psql -c \"CREATE DATABASE sonarqube OWNER sonar;\""
runusr -l postgres -c "psql -c \"GRANT ALL PRIVILLEGES ON DATABASE sonarqube to sonar;\""
systemctl restart postgresql

#install sonarqube
mkdir -p /sonarqube/
cd /sonarqube
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-10.5.0.89998.zip
apt-get install unzip -y
unzip -o sonarqube-10.5.0.89998.zip -d /opt/
mv /opt/sonarqube-10.5.0.89998/ /opt/sonarqube

#Create SonarQube system user
sudo adduser --system --no-create-home --group --disabled-login sonar
sudo chown -R sonar:sonar /opt/sonarqube

#Configure SonarQube
cp /opt/sonarqube/conf/sonar.properties /root/sonar.properties_backup
cat <<EOT > /opt/sonarqube/conf/sonar.properties
sonar.jdbc.username=sonar
sonar.jdbc.password=admin123
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
#Web server configuration
sonar.web.host=0.0.0.0
sonar.web.port=9000


echo "=== Create systemd service for SonarQube ==="
sudo bash -c 'cat > /etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonar
Group=sonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF'

echo "=== Enable and start SonarQube service ==="
sudo systemctl daemon-reload
sudo systemctl enable sonarqube
sudo systemctl start sonarqube






