#!/bin/bash
# Check if user is root
if [[ "$(id -u)" -ne 0 ]]; then
    sudo -E "$0" "$@"
    exit
fi

# Global vairables
TUNNEL_USER="tunnel"
TUNNEL_URL="theemperorsplace.com"
TUNNEL_SCRIPT="/usr/local/bin/tunnel_script.sh"

# Diplay messages
print_message() {
  echo -e "\n>>> $1\n"
}

# Run installations
print_message "Updating and installing required packages..."

# Ensure python is installed
if ! command -v python3 &> /dev/null; then
    apt-get update
    apt-get install -y python3
fi

# Ensure nginx is installed
if ! command -v nginx &> /dev/null; then
    apt-get update
    apt-get install -y nginx
    systemctl enable nginx
fi

# Create tunnel user
if ! id -u $TUNNEL_USER > /dev/null 2>&1; then
adduser --disabled-password --gecos "" $TUNNEL_USER
passwd -d $TUNNEL_USER
else
    print_message "User: $TUNNEL_USER already exists."
fi

# Configure SSH settings to allow passwordless to the server
print_message "Configuring SSH..."
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#UsePAM.*/UsePAM no/' /etc/ssh/sshd_config
sed -i 's|^Include /etc/ssh/sshd_config.d/\*.conf|#Include /etc/ssh/sshd_config.d/*.conf|' /etc/ssh/sshd_config
# Add configuration for tunnel user
cat >> /etc/ssh/sshd_config <<EOL
# Allow passwordless login for tunnel user
Match User $TUNNEL_USER
    PermitEmptyPasswords yes
    PasswordAuthentication yes
    PubkeyAuthentication no
    ChallengeResponseAuthentication no
    KbdInteractiveAuthentication no
    AllowAgentForwarding yes
    GatewayPorts yes
    PermitTunnel yes
    ForceCommand $TUNNEL_SCRIPT
EOL

# Restart ssh
systemctl restart ssh


# Create the tunnel script
print_message "Creating tunnel_script.sh..."

cat > $TUNNEL_SCRIPT <<'EOF'
#!/bin/bash
REMOTE_PORT=8080
DOMAIN="theemperorsplace.com"

# Generate a random subdomain name
SUBDOMAIN=$(openssl rand -hex 4)

# Nginx configuration path
NGINX_CONFIG="/etc/nginx/conf.d/${SUBDOMAIN}.conf"

# Check if the subdomain already exists and remove
if [ -f $NGINX_CONFIG ]; then
    sudo rm $NGINX_CONFIG
fi

sudo bash -c "cat > $NGINX_CONFIG" <<EOL
server {
    listen 80;
    server_name ${SUBDOMAIN}.${DOMAIN}.com;

    location / {
        proxy_pass http://localhost:$REMOTE_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# Reload Nginx to apply changes
sudo systemctl reload nginx
echo "You can now access your service at http://${SUBDOMAIN}.${DOMAIN}"

echo "Press [CTRL+C] to exit"

# Keep the process alive
while true; do sleep 10; done

EOF

# Make tunnel script executable
chmod +x $TUNNEL_SCRIPT

print_message "Tunnel SSH Setup completed successfully:"
print_message "ssh -R 8080:localhost:3000 tunnel@$TUNNEL_URL"