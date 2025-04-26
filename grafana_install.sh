#!/bin/bash
domain=grafana.domain.net

printf "\n#########################################################"
printf "\n# Uninstall old grafana from the server"
printf "\n#########################################################"
if [ -f "/usr/lib/systemd/system/grafana-server.service" ] >/dev/null 2>&1
then
	systemctl daemon-reload >/dev/null 2>&1
	systemctl disable --now grafana >/dev/null 2>&1
	yum remove -y grafana >/dev/null 2>&1
	sleep 3
fi
rm -rf /etc/grafana/ /var/lib/grafana/ /var/log/grafana/ /usr/share/grafana/ >/dev/null 2>&1
if [ ! -f "/usr/lib/systemd/system/nginx.service" ] >/dev/null
then
	systemctl restart nginx >/dev/null
	sleep 3
fi 
echo -e
printf "\n#########################################################"
printf "\n# Install Grafana from the RPM repository"
printf "\n#########################################################"

printf "\n#Import grafana gpg key from https://rpm.grafana.com/gpg.key"
wget -q -O gpg.key https://rpm.grafana.com/gpg.key >/dev/null
sudo rpm --import gpg.key >/dev/null
sudo rm -f gpg.key >/dev/null

printf "\n#Create grafana repository to /etc/yum.repos.d/grafana.repo"
cat <<EOF | sudo tee /etc/yum.repos.d/grafana.repo >/dev/null
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
exclude=*beta*
EOF
printf "\n#Install grafana-server from repository"
echo y|yum install grafana -y >/dev/null
systemctl stop grafana-server  >/dev/null 2>&1
echo -e
printf "\n#########################################################"
printf "\n#Create config file to /etc/grafana/custom.ini"
printf "\n#\n#Website: $domain"
printf "\n#########################################################"
cat <<EOF | sudo tee /etc/grafana/custom.ini >/dev/null
##################### Grafana Configuration #####################
#
# Everything has defaults so you only need to uncomment things you want to
# change

# possible values : production, development

#################################### Server ####################################
[server]
# Protocol (http, https, h2, socket)
protocol = http

# The ip address to bind to, empty will bind to all interfaces
http_addr = 127.0.0.1

# The http port  to use
http_port = 3000

# The public facing domain name used to access grafana from a browser
domain = $domain

# The full public facing url you use in browser, used for redirects and emails
# If you use reverse proxy and sub path specify full url (with sub path)
root_url = %(protocol)ss://%(domain)s/

#################################### Security ####################################
[security]
# disable creation of admin user on first start of grafana
disable_initial_admin_creation = false

# default admin user, created on startup
admin_user = admin

# default admin password, can be changed before first start of grafana,  or in profile settings
admin_password = admin

# default admin email, created on startup
#admin_email = admin@domain.net

#################################### Users ###############################
[users]
# disable user signup / registration
allow_sign_up = true

# Allow non admin users to create organizations
allow_org_create = false

# Set to true to automatically assign new users to the default organization (id 1)
auto_assign_org = true

# Set this value to automatically add new users to the provided organization (if auto_assign_org above is set to true)
auto_assign_org_id = 1

# Default role new users will be automatically assigned
auto_assign_org_role = Viewer

# Require email validation before sign up completes
verify_email_enabled = true

# Background text for the user field on the login page
login_hint = email or username
password_hint = password

# Default UI theme ("dark" or "light")
default_theme = dark

# Default UI language (supported IETF language tag, such as en-US)
default_language = en-US

# Path to a custom home page. Users are only redirected to this if the default home dashboard is used. It should match a frontend route and contain a leading slash.
;home_page =

# Viewers can edit/inspect dashboard settings in the browser. But not save the dashboard.
viewers_can_edit = false

# Editors can administrate dashboard, folders and teams they create
editors_can_admin = false

# The duration in time a user invitation remains valid before expiring. This setting should be expressed as a duration. Examples: 6h (hours), 2d (days), 1w (week). Default is 24h (24 hours). The minimum supported duration is 15m (15 minutes).
user_invite_max_lifetime_duration = 24h

# Enter a comma-separated list of users login to hide them in the Grafana UI. These users are shown to Grafana admins and themselves.
; hidden_users =

[auth]
# Login cookie name
login_cookie_name = grafana_session

# Disable usage of Grafana build-in login solution.
disable_login = false

# The maximum lifetime (duration) an authenticated user can be inactive before being required to login at next visit. Default is 7 days (7d). This setting should be expressed as a duration, e.g. 5m (minutes), 6h (hours), 10d (days), 2w (weeks), 1M (month). The lifetime resets at each successful token rotation.
login_maximum_inactive_lifetime_duration = 7d

# The maximum lifetime (duration) an authenticated user can be logged in since login time before being required to login. Default is 30 days (30d). This setting should be expressed as a duration, e.g. 5m (minutes), 6h (hours), 10d (days), 2w (weeks), 1M (month).
login_maximum_lifetime_duration = 1M

# How often should auth tokens be rotated for authenticated users when being active. The default is each 10 minutes.
token_rotation_interval_minutes = 10

# Set to true to disable (hide) the login form, useful if you use OAuth, defaults to false
disable_login_form = false

# Set to true to disable the sign out link in the side menu. Useful if you use auth.proxy or auth.jwt, defaults to false
disable_signout_menu = false

# Set to true to enable SigV4 authentication option for HTTP-based datasources.
sigv4_auth_enabled = false

# Set to true to enable verbose logging of SigV4 request signing
sigv4_verbose_logging = false

#################################### Anonymous Auth ######################
[auth.anonymous]
# enable anonymous access
enabled = true

# specify organization name that should be used for unauthenticated users
;org_name = Main Org.
org_name = Main Org.

# specify role for unauthenticated users
org_role = Viewer

# mask the Grafana version number for unauthenticated users
hide_version = false

#################################### Basic Auth ##########################
[auth.basic]
enabled = true

#################################### Auth LDAP ##########################
[auth.ldap]
;enabled = false
;config_file = /etc/grafana/ldap.toml
;allow_sign_up = true
# prevent synchronizing ldap users organization roles
;skip_org_role_sync = false

# LDAP background sync (Enterprise only)
# At 1 am every day
;sync_cron = "0 1 * * *"
;active_sync_enabled = true

#################################### SMTP / Emailing ##########################
# [smtp]
# enabled = true
# host = smtp.office365.com:587
# user = admin@domain.net
# If the password contains # or ; you have to wrap it with triple quotes. Ex """#password;"""
# password = app_password
;cert_file =
;key_file =
;skip_verify = false
# from_address = 
# from_name = Grafana
# EHLO identity in SMTP dialog (defaults to instance_name)
;ehlo_identity = dashboard.example.com
# SMTP startTLS policy (defaults to 'OpportunisticStartTLS')
;startTLS_policy = NoStartTLS

[emails]
welcome_email_on_sign_up = true
templates_pattern = emails/*.html, emails/*.txt
content_types = text/html

#################################### Logging ##########################
[log]
# Either "console", "file", "syslog". Default is console and  file
# Use space to separate multiple modes, e.g. "console file"
;mode = console file

# Either "debug", "info", "warn", "error", "critical", default is "info"
;level = info

# optional settings to set different levels for specific loggers. Ex filters = sqlstore:debug
;filters =

# Set the default error message shown to users. This message is displayed instead of sensitive backend errors which should be obfuscated. Default is the same as the sample value.
;user_facing_default_error = "please inspect Grafana server log for details"

# For "console" mode only
[log.console]
;level =

# log line format, valid options are text, console and json
;format = console

# For "file" mode only
[log.file]
;level =

# log line format, valid options are text, console and json
;format = text

# This enables automated log rotate(switch of following options), default is true
;log_rotate = true

# Max line number of single file, default is 1000000
;max_lines = 1000000

# Max size shift of single file, default is 28 means 1 << 28, 256MB
;max_size_shift = 28

# Segment log daily, default is true
;daily_rotate = true

# Expired days of log file(delete after max days), default is 7
;max_days = 7

[log.syslog]
;level =

# log line format, valid options are text, console and json
;format = text

# Syslog network type and address. This can be udp, tcp, or unix. If left blank, the default unix endpoints will be used.
;network =
;address =

# Syslog facility. user, daemon and local0 through local7 are valid.
;facility =

# Syslog tag. By default, the process' argv[0] is used.
;tag =

[log.frontend]
# Should Faro javascript agent be initialized
;enabled = false

# Custom HTTP endpoint to send events to. Default will log the events to stdout.
;custom_endpoint = /log-grafana-javascript-agent

# Requests per second limit enforced an extended period, for Grafana backend log ingestion endpoint (/log).
;log_endpoint_requests_per_second_limit = 3

# Max requests accepted per short interval of time for Grafana backend log ingestion endpoint (/log).
;log_endpoint_burst_limit = 15

# Should error instrumentation be enabled, only affects Grafana Javascript Agent
;instrumentations_errors_enabled = true

# Should console instrumentation be enabled, only affects Grafana Javascript Agent
;instrumentations_console_enabled = false

# Should webvitals instrumentation be enabled, only affects Grafana Javascript Agent
;instrumentations_webvitals_enabled = false

# Api Key, only applies to Grafana Javascript Agent provider
;api_key = testApiKey

#################################### Usage Quotas ########################
[quota]
; enabled = false

#### set quotas to -1 to make unlimited. ####
# limit number of users per Org.
; org_user = 10

# limit number of dashboards per Org.
; org_dashboard = 100

# limit number of data_sources per Org.
; org_data_source = 10

# limit number of api_keys per Org.
; org_api_key = 10

# limit number of alerts per Org.
;org_alert_rule = 100

# limit number of orgs a user can create.
; user_org = 10

# Global limit of users.
; global_user = -1

# global limit of orgs.
; global_org = -1

# global limit of dashboards
; global_dashboard = -1

# global limit of api_keys
; global_api_key = -1

# global limit on number of logged in users.
; global_session = -1

# global limit of alerts
;global_alert_rule = -1

# global limit of correlations
; global_correlations = -1

#################################### Explore #############################
[explore]
# Enable the Explore section
enabled = true

#################################### Help #############################
[help]
# Enable the Help section
enabled = false

#################################### Profile #############################
[profile]
# Enable the Profile section
enabled = true

#################################### News #############################
[news]
# Enable the news feed section
news_feed_enabled = false

#################################### Query #############################
[query]
# Set the number of data source queries that can be executed concurrently in mixed queries. Default is the number of CPUs.
;concurrent_query_limit =

#################################### Query History #############################
[query_history]
# Enable the Query history
enabled = true

EOF
chown root.grafana /etc/grafana/custom.ini >/dev/null
echo -e 
printf "\n#Change Grafana config_file"
sed -i 's/grafana.ini/custom.ini/g' /etc/sysconfig/grafana-server >/dev/null
echo -e
printf "\n#########################################################"
printf "\n#Enable and start grafana-server"
printf "\n#########################################################"
systemctl daemon-reload >/dev/null 2>&1
systemctl enable --now grafana-server >/dev/null
echo -e
printf "\n#########################################################"
printf "\n#Config nginx proxy for grafana"
printf "\n#########################################################"
if [ ! -f "/usr/lib/systemd/system/nginx.service" ] 
then
	yum install -y nginx >/dev/null
fi 
if [ ! -d "/etc/nginx/conf.d/" 
then
	mkdir -p etc/nginx/conf.d >/dev/null
fi
cat <<EOF | sudo tee /etc/nginx/conf.d/grafana.conf >/dev/null
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
        proxy_pass http://127.0.0.1:3000;
        # the max size of file to upload
        client_max_body_size 20000m;
    }
}
EOF
systemctl enable nginx >/dev/null
systemctl restart nginx >/dev/null
firewall-cmd --permanent --add-service={http,https} >/dev/null 2>&1
firewall-cmd --reload >/dev/null 2>&1
echo -e
printf "\n#########################################################"
printf "\n#Netstat check open port \n"
sleep 10 >/dev/null
netstat -antp | grep -E 'LISTEN.+(grafana|nginx)'
printf "\n#########################################################"
rm -- "$0"
