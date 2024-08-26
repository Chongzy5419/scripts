#!/bin/bash

export TERM=xterm-256color

# Color settings
color_red=$(tput setaf 1)  # Red
color_green=$(tput setaf 2)  # Green
color_yellow=$(tput setaf 3)  # Yellow
color_blue=$(tput setaf 4)  # Blue
color_magenta=$(tput setaf 5)  # Magenta
color_cyan=$(tput setaf 6)  # Cyan
color_grey=$(tput setaf 7)  # Grey
color_reset=$(tput sgr0)

#   Function to prompt for input with a default value
prompt_for_input() {
  local prompt_message=$1
  local default_value=$2
  local user_input

  read -p "$prompt_message [$default_value]: " user_input
  echo "${user_input:-$default_value}"
}

# Prompt for username@ip, private key path, and sudo password if not provided
USERNAME_IP=${1:-$(prompt_for_input "Enter target machine " "ips1@server")}
PRIVATE_KEY=${2:-$(prompt_for_input "Enter PKI key path" "./id_rsa")}
SUDO_PASSWORD=${3:-$(prompt_for_input "Enter sudo password" "7v65gT-Hpfw4k-SX8PZy")}
PORT=${4:-$(prompt_for_input "Enter SSH port" "22")}

# Extracting IP address from the username@ip argument
TARGET_IP=$(echo $USERNAME_IP | awk -F'@' '{print $2}')



# FIRST TEST SSH CONNECTIVITY
echo -e "\n${color_magenta}1: Testing SSH connectivity to $TARGET_IP...${color_reset}"

SSH_CONNECTIVITY=$(ssh -i $PRIVATE_KEY -p $PORT -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME_IP "echo 'SSH connection successful'" 2>&1)
if [[ $SSH_CONNECTIVITY != *"SSH connection successful"* ]]; then
  echo "${color_red}Error: Unable to establish SSH connection to $USERNAME_IP. Please check the IP, port, and private key.${color_reset}"
  exit 1
fi
echo "${color_green}SSH connection successful.${color_reset}"



# SECOND TEST SUDO PASSWORD
echo -e "\n${color_magenta}2: Checking sudo password...${color_reset}"

SUDO_TEST=$(ssh -i $PRIVATE_KEY -p $PORT $USERNAME_IP "echo '$SUDO_PASSWORD' | sudo -S echo 'Sudo password correct'" 2>&1)
if [[ $SUDO_TEST != *"Sudo password correct"* ]]; then
  echo "${color_red}Error: Incorrect sudo password. Please check the sudo password and try again.${color_reset}"
  exit 1
fi
echo "${color_green}Sudo password is correct.${color_reset}"



# THIRD CHECK SSH PARAM
echo -e "\n${color_magenta}3: Checking SSH config on $TARGET_IP...${color_reset}"

PASSWORD_AUTH=$(ssh -o BatchMode=yes -o PreferredAuthentications=password -o ConnectTimeout=5 $USERNAME_IP -p $PORT "exit" 2>&1)
if [[ $PASSWORD_AUTH == *"Permission denied"* ]]; then
  echo "${color_green}SSH password authentication is DISABLED on $TARGET_IP.${color_reset}" 
else
  echo "${color_yellow}Warning: SSH password authentication is ENABLED on $TARGET_IP.${color_reset}"
fi



# FORTH PERFORM PORT SCAN
echo -e "\n${color_magenta}4: Scanning ports on $TARGET_IP.......${color_reset}"

PORTS=("21" "22" "23" "25" "53" "80" "110" "143" "443" "445" "3306" "3389" "8080" "8443")

for PORTS in "${PORTS[@]}"
do
  nc -zv $TARGET_IP $PORTS 2>&1 | grep "succeeded" | awk '{print $6 " " $5 " "$7 " is open"}'
done



# FIFTH TESTING WEBSITE AVAILABILITY
echo -e "\n${color_magenta}5: Attempting HTTP connection to $USERNAME_IP.......${color_reset}"

HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://$TARGET_IP)
if [ "$HTTP_STATUS" -eq 200 ]; then
  echo -e "${color_green}HTTP connection successful.${color_reset}"
else
  echo -e "${color_red}HTTP connection unsuccessful.${color_reset}"
fi

HTTPS_STATUS=$(curl -o /dev/null -s -w "%{http_code}" https://$TARGET_IP)
if [ "$HTTPS_STATUS" -eq 200 ]; then
  CERTIFICATE_VALIDITY=$(curl -vI https://$TARGET_IP 2>&1 | grep "expire date")
  
  if [ -n "$CERTIFICATE_VALIDITY" ]; then
    echo -e "${color_green}HTTPS connection successful, valid certificate.${color_reset}"
  else
    echo -e "${color_yellow}HTTPS connection successful, invalid certificate.${color_reset}"
  fi
  
elif [ "$HTTPS_STATUS" -eq 000 ]; then
  SELF_SIGNED_CERT=$(curl -vI https://$TARGET_IP 2>&1 | grep "self-signed")

  if [ -n "$SELF_SIGNED_CERT" ]; then
    echo -e "${color_yellow}HTTPS connection successful, self-signed certificate.${color_reset}"
  else
    echo -e "${color_red}HTTPS connection unsuccessful.${color_reset}"
  fi
else
  echo -e "${color_red}HTTPS connection unsuccessful.${color_reset}"
fi



#DETERMINING DISTRO
echo -e "\n${color_magenta}Determining Linux Distro on Remote Server $USERNAME_IP....... ${color_reset}"
distro=$(ssh -i "$PRIVATE_KEY" -p "$PORT" "$USERNAME_IP" "grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '\"'")
echo -e "\nDetected Distro: ${color_cyan}${distro}${color_reset}"

#EXECUTING ON REMOTE SERVER
echo -e "\n${color_magenta}Executing Script on Remote Server $USERNAME_IP.......${color_reset}"
if [ "$distro" == "rocky" ]; then
    echo "This machine is running Rocky."
    
elif [ "$distro" == "ubuntu" ]; then
    echo "This machine is running Ubuntu."
    ssh -i $PRIVATE_KEY -p $PORT $USERNAME_IP "wget -qq -O /tmp/ubuntu.sh https://raw.githubusercontent.com/Chongzy5419/scripts/main/bash/ubuntu.sh && echo '$SUDO_PASSWORD' | sudo -S bash /tmp/ubuntu.sh"

else
    echo "This machine is running a different distribution: $distro"
fi


