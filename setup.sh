#!/bin/bash

NODENAME="zenchain"
GREENCOLOR="\e[32m"
DEFAULTCOLOR="\e[0m"

setup() {
    curl -s https://raw.githubusercontent.com/Widiskel/Widiskel/refs/heads/main/show_logo.sh | bash
    sleep 3

    echo "Updating & Upgrading Packages..."
    sudo apt update -y && sudo apt upgrade -y

    cd $HOME
    if [ -d "node" ]; then
        echo "The 'node' directory already exists."
    else
        mkdir node
        echo "Created the 'node' directory."
    fi
    cd node

    if [ -d "$NODENAME" ]; then
        echo "The '$NODENAME' directory already exists."
    else
        mkdir $NODENAME
        echo "Created the '$NODENAME' directory."
    fi
    cd $NODENAME

}

installRequirements(){
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
            sudo apt-get remove -y $pkg
        done

        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        
        sudo apt update -y && sudo apt install -y docker-ce
        sudo systemctl start docker
        sudo systemctl enable docker

        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose

        echo "Docker installed successfully."
    else
        echo "Docker is already installed."
    fi

    if ! command -v jq &> /dev/null; then
        echo "Installing jq..."
        sudo apt install -y jq
    fi

}

process(){
    mkdir -p "chain-data"
    chmod -R 777 "chain-data"
    echo "Created the 'chain-data' directory."

    read -p "Enter your Validator Name: " VALIDATORNAME
    echo "YOURVALIDATORNAME=$VALIDATORNAME" > .env
    echo ".env file created with YOURVALIDATORNAME=$VALIDATORNAME"
    echo "Creating docker-compose-pre.yaml..."
cat <<EOF > docker-compose-pre.yaml
version: '3'
services:
  zenchain:
    image: ghcr.io/zenchain-protocol/zenchain-testnet:latest
    container_name: zenchain
    ports:
      - "9944:9944"
    volumes:
      - ./chain-data:/chain-data
    command: >
      ./usr/bin/zenchain-node
      --base-path=/chain-data
      --rpc-cors=all
      --rpc-methods=unsafe
      --unsafe-rpc-external
      --name=$VALIDATORNAME
      --bootnodes=/dns4/node-7242611732906999808-0.p2p.onfinality.io/tcp/26266/p2p/12D3KooWLAH3GejHmmchsvJpwDYkvacrBeAQbJrip5oZSymx5yrE
      --chain=zenchain_testnet
EOF

    echo "docker-compose-pre.yaml file created with validator name: $VALIDATORNAME"

    echo "Starting ZenChain node using PRE Docker Compose..."
    docker-compose -f docker-compose-pre.yaml up -d
    echo "Waiting for the ZenChain node container to start..."
    while ! docker ps | grep -q zenchain; do
        sleep 3
        echo "Waiting for ZenChain container to start..."
    done

    echo "ZenChain node container is now running!"
    echo "Waiting for 'Prometheus exporter started' in logs..."
    while true; do
        if docker logs zenchain 2>&1 | grep -q "Prometheus exporter started"; then
            echo "'Prometheus exporter started' message found in logs."
            break
        fi
        sleep 2
    done

    echo "Sending RPC request to rotate keys and get session key..."
    RESPONSE=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}' http://localhost:9944)

     if [ $? -ne 0 ]; then
        echo "Curl request failed. Exiting."
        exit 1
    fi
    # Extract the session key from the response (remove '0x' prefix)
    SESSION_KEY=$(echo $RESPONSE | jq -r '.result | select(. != null)')
    echo "Session key : $SESSION_KEY"

    if [[ $SESSION_KEY =~ ^0x ]]; then
        SESSION_KEY=${SESSION_KEY:2}
    fi

    echo "Session key (without 0x prefix): $SESSION_KEY"

    echo -e "\nTo continue to the next step, set keys for your Ethereum account by sending 0 Tokens on the Zenchain Network with this details:"
    echo -e "\nSend to: '0x0000000000000000000000000000000000000802'"
    echo -e "\nInput Data: 0xf1ec919c00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060$SESSION_KEY"
    echo -e "\n"
    while true; do
        read -p "Press Enter to continue: " user_input
        if [[ -z "$user_input" ]]; then
            echo "Proceeding to the next step..."
            echo "Stopping Zenchain container..."
            docker stop zenchain
            # Remove the Zenchain container
            echo "Removing Zenchain container..."
            docker rm zenchain
            break
        fi
    done

    echo "Creating docker-compose.yaml..."

cat <<EOF > docker-compose.yaml
version: '3'

services:
  zenchain:
    image: ghcr.io/zenchain-protocol/zenchain-testnet:latest
    container_name: zenchain
    ports:
      - "9944:9944"
    volumes:
      - ./chain-data:/chain-data
    command: ./usr/bin/zenchain-node \
      --base-path=/chain-data \
      --validator \
      --name="$VALIDATORNAME" \
      --bootnodes=/dns4/node-7242611732906999808-0.p2p.onfinality.io/tcp/26266/p2p/12D3KooWLAH3GejHmmchsvJpwDYkvacrBeAQbJrip5oZSymx5yrE \
      --chain=zenchain_testnet
    restart: always
EOF

    echo "docker-compose.yaml file created with your validator name: $VALIDATOR_NAME"
    echo "Starting ZenChain node using Docker Compose..."
    docker-compose -f docker-compose.yaml up -d
    echo "Waiting for the ZenChain node container to start..."
    while ! docker ps | grep -q zenchain; do
        sleep 3
        echo "Waiting for ZenChain container to start..."
    done

    echo "ZenChain node container is now running!"
}

finish() {
    NODEPATH=$(pwd) 
    
    echo "Setup Complete"
    echo "Your $NODENAME path is on $NODEPATH"
    echo ""
    echo "Check your node logs with : 'docker logs -f zenchain'"
    echo "Now, go to Validator Dashboard: https://node.zenchain.io/#/staking"
    echo "Cick Stake > Click To Your Account > Click Become a Validator > Input any amount you want to stake > Click Start Staking"
    echo "DONE LFG"
       
}


setup
installRequirements
process
finish
