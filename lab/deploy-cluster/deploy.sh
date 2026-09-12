#!/usr/bin/env bash
SCRIPT_DIR=$(pwd)

STARTUP_CFG="$SCRIPT_DIR/cluster-lab/ansible_startup.cfg"
STARTUP_INI="$SCRIPT_DIR/cluster-lab/inventory_startup.ini"

MAIN_CFG="$SCRIPT_DIR/cluster-lab/ansible.cfg"
MAIN_INI="$SCRIPT_DIR/cluster-lab/inventory.ini"

PLAYBOOK="$SCRIPT_DIR/cluster-lab/playbook"

echo -e "Create authorized keys for cluster users\n\n"

if ! [ -f $HOME/.ssh/ansible-key ]; then
	ssh-keygen -t ed25519 -f $HOME/.ssh/ansible-key
fi

if ! [ -f $HOME/.ssh/developer-key ]; then
	ssh-keygen -t ed25519 -f $HOME/.ssh/developer-key
fi

if ! [ -f $HOME/.ssh/devops-key ]; then
	ssh-keygen -t ed25519 -f $HOME/.ssh/devops-key
fi

read -sp "Input password from users $(whoami) cluster for sudo/SSH: " USER_PASS
echo -e "\n"

read -sp "Input your telegram token to access the HTTP API: " TG_TOKEN
echo -e "\n"

read -sp "Input your telegram chat id: " TG_CHAT
echo -e "\n"

if ANSIBLE_CONFIG="$MAIN_CFG" ansible all -i "$MAIN_INI" -m ping > /dev/null 2>&1; then
    echo -e "Keys are already deployed. Skipping Step 1 (Bootstrap)...\n"
else
    echo -e "Starting Initial Bootstrap (Step 1)...\n"
    
    if ! ANSIBLE_CONFIG="$STARTUP_CFG" ansible all -i "$STARTUP_INI" \
        -e "ansible_password=$USER_PASS" \
        -e "ansible_ssh_pass=$USER_PASS" \
        -e "ansible_become_password=$USER_PASS" -m ping > /dev/null 2>&1; then
        
        echo "Error: Hosts are completely unavailable! Check IP addresses or SSH password."
        exit 1
    fi

    echo -e "Step 1: Initial host setup\n"
    ANSIBLE_CONFIG="$STARTUP_CFG" ansible-playbook -i "$STARTUP_INI" \
        -e "ansible_password=$USER_PASS" \
        -e "ansible_ssh_pass=$USER_PASS" \
        -e "ansible_become_password=$USER_PASS" \
        "$PLAYBOOK/00_startup.yml"

    if [ $? -ne 0 ]; then
        echo "Error while executing Step 1"
        exit 1
    fi
    echo -e "Step 1 Complete!\n\n"
fi

echo -e "Step 2: Basic host setup\n"
ANSIBLE_CONFIG="$MAIN_CFG" ansible-playbook -i "$MAIN_INI" "$PLAYBOOK/01_base_setup.yml" || exit 1

echo -e "Step 3: Configure users and groups\n"
ANSIBLE_CONFIG="$MAIN_CFG" ansible-playbook -i "$MAIN_INI" "$PLAYBOOK/02_user_setup.yml" || exit 1

echo -e "Step 4: Install docker\n"
ANSIBLE_CONFIG="$MAIN_CFG" ansible-playbook -i "$MAIN_INI" "$PLAYBOOK/03_docker_setup.yml" || exit 1

echo -e "Step 5: Install apps, monitoring and log collector\n"
ANSIBLE_CONFIG="$MAIN_CFG" ansible-playbook -i "$MAIN_INI" \
    -e "telegram_token=$TG_TOKEN" \
    -e "telegram_chat_id=$TG_CHAT" \
    "$PLAYBOOK/04_deploy.yml" || exit 1

echo -e "\nDeployment was successful!!!!!\n\n"
echo -e "Started docker containers:\n"
ANSIBLE_CONFIG="$MAIN_CFG" ansible all -i "$MAIN_INI" -m shell -a "docker ps" --become
