#!/bin/sh

PROXY_USER=user
PROXY_PASS=password
PROXY_PORT=3128
PROXY_HTTPS_PORT=3129

# Clear the repository index caches
yum clean all

# Update the operating system
yum update -y

# Install httpd-tools to get htpasswd
yum install httpd-tools -y

# Create the htpasswd file
htpasswd -c -b /etc/squid/passwords $PROXY_USER $PROXY_PASS

# Install squid
yum install squid -y

# Backup the original squid config
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak
mkdir /etc/squid/ssl_cert
chown -R squid.squid /etc/squid/ssl_cert
cd /etc/squid/ssl_cert
openssl req -new -newkey rsa:1024 -days 1365 -nodes -x509 -keyout myca.pem -out myca.pem

# Set up the squid config
cat << EOF > /etc/squid/squid.conf
auth_param basic program /usr/lib64/squid/ncsa_auth /etc/squid/passwords
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
forwarded_for delete
http_port 0.0.0.0:$PROXY_PORT
https_port 0.0.0.0:$PROXY_HTTPS_PORT key=/etc/squid/ssl_cert/myca.pem
EOF

# Set squid to start on boot
chkconfig squid on

# Start squid
/etc/init.d/squid start

# Set up the iptables config
cat << EOF > /etc/sysconfig/iptables
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT

#######################################################
# BEGIN CUSTOM RULES
#######################################################

# Allow SSH from anywhere
-A INPUT -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT

# Allow squid access from anywhere
-A INPUT -m state --state NEW -m tcp -p tcp --dport $PROXY_PORT -j ACCEPT
-A INPUT -m state --state NEW -m tcp -p tcp --dport $PROXY_HTTPS_PORT -j ACCEPT

#######################################################
# END CUSTOM RULES
#######################################################

-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
EOF

# Restart iptables
/etc/init.d/iptables restart