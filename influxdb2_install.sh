#!/bin/bash
if [ -f "/usr/lib/systemd/system/influxdb.service" ] >/dev/null 2>&1
then
	printf "\n#########################################################"
	printf "\n# Uninstall old influxdb from the server"
	printf "\n#########################################################"
	systemctl daemon-reload >/dev/null 2>&1
	systemctl disable --now influxdb >/dev/null 2>&1
	yum remove -y influxdb >/dev/null 2>&1
	sleep 3
fi
rm -rf /etc/influxdb/ /var/lib/influxdb/ /var/log/influxdb/ /usr/share/influxdb/ >/dev/null 2>&1
echo -e
printf "\n#########################################################"
printf "\n# Install influxdb from the RPM repository"
printf "\n#########################################################"
printf "\n#Create influxdata repository to /etc/yum.repos.d/influxdata.repo"
cat <<EOF | sudo tee /etc/yum.repos.d/influxdata.repo >/dev/null
[influxdata]
name = InfluxData Repository - Stable
baseurl = https://repos.influxdata.com/stable/\$basearch/main
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive_compat.key
EOF
printf "\n#Install influxdb from repository"
echo y|yum install influxdb2 -y >/dev/null
echo -e
printf "\n#########################################################"
printf "\n#Enable and start influxdb"
printf "\n#########################################################"
systemctl daemon-reload >/dev/null 2>&1
systemctl enable --now influxdb >/dev/null
echo -e
printf "\n#########################################################"
printf "\n#Config nginx proxy for influxdb"
printf "\n#########################################################"
if [ ! -f "/usr/lib/systemd/system/nginx.service" ] 
then
	yum install -y nginx >/dev/null
fi 
if [ ! -d "/etc/nginx/conf.d/" 
then
	mkdir -p etc/nginx/conf.d >/dev/null
fi
cat <<EOF | sudo tee /etc/nginx/conf.d/influxdb.conf >/dev/null
server_names_hash_bucket_size 64;
server {
    listen       80;
    server_name  $domain;

    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Range \$http_range;
        proxy_set_header If-Range \$http_if_range;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:8086;
    }
	
    location /influxdb2/ {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Range \$http_range;
        proxy_set_header If-Range \$http_if_range;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:8086;
    }
}
EOF
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx >/dev/null 2>&1
firewall-cmd --permanent --add-service={http,https} >/dev/null 2>&1
firewall-cmd --reload >/dev/null 2>&1
echo -e
printf "\n#########################################################"
printf "\n#Netstat check open port \n"
sleep 10 >/dev/null
netstat -antp | grep -E 'LISTEN.+(influxd|nginx)'
printf "\n#########################################################"
rm -- "$0"
