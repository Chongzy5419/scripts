sudo apt update && sudo apt install -y sshpass
#!/bin/bash

# Set variables
REMOTE_HOST="102.140.93.54"
REMOTE_USER="tunneluser"
KEY_PATH="$HOME/.ssh/tunneluser_id_rsa"
SSH_CONFIG="$HOME/.ssh/config"
PORT=2222
MAX_PORT=2299

# Step 1: Create SSH config entry
mkdir -p ~/.ssh
chmod 700 ~/.ssh
grep -q "Host sshtunnel" "$SSH_CONFIG" 2>/dev/null || cat <<EOF >> "$SSH_CONFIG"

Host sshtunnel
    HostName $REMOTE_HOST
    User $REMOTE_USER
    IdentityFile $KEY_PATH
EOF
chmod 600 "$SSH_CONFIG"

# Step 2: Generate SSH key if not exists
if [ ! -f "$KEY_PATH" ]; then
    ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N ""
fi

# Step 3: Send public key to remote
if ! command -v sshpass >/dev/null 2>&1; then
    echo "Installing sshpass..."
    sudo apt update && sudo apt install -y sshpass
fi
sshpass -p 'abc123' ssh-copy-id -o StrictHostKeyChecking=no -i "${KEY_PATH}.pub" sshtunnel

# Step 4: Install autossh
if ! command -v autossh >/dev/null 2>&1; then
    echo "Installing autossh..."
    sudo apt install -y autossh
fi

# Step 5: Check available port
echo "Checking for available port on remote..."
while ssh sshtunnel "netstat -tln | grep -q :$PORT"; do
    ((PORT++))
    if [ "$PORT" -gt "$MAX_PORT" ]; then
        echo "No available ports found in range."
        exit 1
    fi
done
echo "Using remote port: $PORT"

# Step 6: Create systemd service
SERVICE_FILE="/etc/systemd/system/sshtunnel.service"
SERVICE_NAME="sshtunnel"

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Persistent Reverse SSH Tunnel to sshtunnel
After=network.target

[Service]
User=$USER
ExecStart=/usr/bin/autossh -N -R 0.0.0.0:$PORT:localhost:22 sshtunnel
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Step 7: Enable and start service
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

echo "Reverse SSH tunnel setup complete. Tunnel accessible at $REMOTE_HOST:$PORT"
