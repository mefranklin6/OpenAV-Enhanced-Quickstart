#!/bin/bash

# This is a modified version of OpenAV's quickstart file.
# Intended for use with OpenAV-Enhanced-Quickstart at github.com/mefranklin

# pass in any microservices needed, delimited by spaces
microservices="$*"

BOLD="\033[1m"
BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"
RESET="\033[0m"


echo -e "   ___                      ___     __ "
echo -e "  / _ \ _ __   ___ _ __    / \ \   / / "
echo -e " | | | | '_ \ / _ \ '_ \  / _ \ \ / /  "
echo -e " | |_| | |_) |  __/ | | |/ ___ \ V /   "
echo -e "  \___/| .__/ \___|_| |_/_/   \_\_/    "
echo -e "       |_|                             "
echo -e ""

interactive=0
mode="production"
LOCAL_REGISTRY_HOST=localhost:5000


echo -e "> raspi64 architecture?"
architecture=""
if [ "`uname -m`" = "aarch64" ]
then
    echo -e ">   yes"
    architecture="_raspi64"
else
    echo -e ">   no"
fi

echo -e "> checking for docker binary"
which docker > /dev/null
if [ $? -eq 1 -a -f /Applications/Docker.app/Contents/Resources/bin/docker ]
then
    export PATH=$PATH:/Applications/Docker.app/Contents/Resources/bin
fi
which docker > /dev/null
if [ $? -eq 1 ]
then
    echo -e ">   ${RED}not installed${RESET}"
    echo -e "error: Docker is needed, please install it before running this script: https://docs.docker.com/engine/install/"
    exit 1
else
    echo -e ">   ${GREEN}ok${RESET}"
fi
sudo_docker=""
if [ "$architecture" == "_raspi64" ]
then
    sudo_docker="sudo"
fi

echo -e "> checking that Docker is up & running"
$sudo_docker docker ps >/dev/null 2>&1
if [ $? -eq 1 ]
then
    echo -e "error: Docker is not currently running please start it before running this script"
    exit 1
else
    echo -e ">   ${GREEN}ok${RESET}"
fi

echo -e "> checking for netcat binary"
which nc > /dev/null
if [ $? -eq 1 ]
then
    echo -e ">   ${RED}not installed${RESET}"
    echo -e "error: netcat is needed, please install it before running this script"
    exit 1
else
    echo -e ">   ${GREEN}ok${RESET}"
fi
netcat_options=""
if [ "`uname -s`" == "Darwin" ];
then
    netcat_options=" -G 3 "
fi

echo -e "> creating \"openav\" Docker network"

# Discover candidate NICs and IPs for Docker Swarm advertise address
swarm_advertise_addr=""
candidate_nics=()
candidate_ips=()

if command -v ip >/dev/null 2>&1
then
    hw_nics=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth|^wlan' || true)
    for nic in $hw_nics
    do
        nic_ip=$(ip -4 addr show "$nic" | awk '/inet / {print $2}' | cut -d"/" -f1 | head -n1)
        if [ -n "$nic_ip" ]
        then
            candidate_nics+=("$nic")
            candidate_ips+=("$nic_ip")
        fi
    done
elif command -v ifconfig >/dev/null 2>&1
then
    hw_nics=$(ifconfig | grep 'flags=' | cut -d: -f1 | grep '^en\|^eth\|^wlan' || true)
    for nic in $hw_nics
    do
        nic_ip=$(ifconfig "$nic" | grep inet | grep -v inet6 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk '{print $2}' | head -n1)
        if [ -n "$nic_ip" ]
        then
            candidate_nics+=("$nic")
            candidate_ips+=("$nic_ip")
        fi
    done
fi

candidate_count=${#candidate_nics[@]}
if [ "$candidate_count" -eq 1 ]
then
    swarm_advertise_addr="${candidate_ips[0]}"
    echo -e ">   using NIC ${candidate_nics[0]} (${swarm_advertise_addr}) for swarm advertise address"
elif [ "$candidate_count" -gt 1 ]
then
    echo -e ">   multiple NICs detected; please choose one for swarm advertise address:"
    idx=1
    for i in "${!candidate_nics[@]}"
    do
        echo -e ">     ${idx}) ${candidate_nics[$i]} - ${candidate_ips[$i]}"
        idx=$((idx+1))
    done

    read -p ">   Enter selection [1-${candidate_count}]: " selection
    if [ -n "$selection" ] && [ "$selection" -ge 1 ] 2>/dev/null && [ "$selection" -le "$candidate_count" ] 2>/dev/null
    then
        chosen_index=$((selection-1))
        swarm_advertise_addr="${candidate_ips[$chosen_index]}"
        echo -e ">   using NIC ${candidate_nics[$chosen_index]} (${swarm_advertise_addr}) for swarm advertise address"
    else
        echo -e ">   invalid selection; continuing without explicit advertise address"
    fi
fi

if [ -n "$swarm_advertise_addr" ]
then
    $sudo_docker docker swarm init --advertise-addr "$swarm_advertise_addr" 2>/dev/null
else
    $sudo_docker docker swarm init 2>/dev/null
fi

$sudo_docker docker network create -d overlay --attachable openav 2>/dev/null

# Only load specified microservices
# microservices="microservice-pjlink microservice-extron-sis microservice-apc-pdu"

echo -e "> instantiating microservices"
i=1
count=$(echo $microservices | wc -w | sed 's/ //g')
for microservice in $microservices
do
    echo -en "\033[2K\033[1G   ${i}/${count} ${MAGENTA}$microservice${RESET} ..."
    $sudo_docker docker stop $microservice > /dev/null 2>&1
    $sudo_docker docker rm $microservice > /dev/null 2>&1

    # Prefer local registry image if available, otherwise fall back to GHCR
    local_image="$LOCAL_REGISTRY_HOST/$microservice:latest"
    remote_image="ghcr.io/dartmouth-openav/$microservice:${mode}$architecture"
    image=""

    if [ -n "$LOCAL_REGISTRY_HOST" ]
    then
        $sudo_docker docker pull "$local_image" > /dev/null 2>&1
        if [ $? -eq 0 ]
        then
            echo -en " (using local registry image $local_image) ..."
            image="$local_image"
        fi
    fi

    # If local image is not available, use official OpenAV image from GHCR
    if [ -z "$image" ]
    then
        echo -en " (using GHCR image $remote_image) ..."
        $sudo_docker docker pull "$remote_image" > /dev/null 2>&1
        image="$remote_image"
    fi

    extra_params=$($sudo_docker docker inspect --format '{{ index .Config.Labels "CONTAINER_LAUNCH_EXTRA_PARAMETERS"}}' "$image" 2>/dev/null)

    $sudo_docker docker run -tdi \
        --restart unless-stopped \
        --network openav \
        --network-alias $microservice \
        --name $microservice \
        $extra_params \
        "$image" > /dev/null 2>&1

    i=$((i+1))
done
echo -e ""

# Automatically create and use ~/OpenAV_system_configurations
system_configs_folder=/opt/OpenAV/"OpenAV_system_configurations"
if [ ! -d /opt/OpenAV/"OpenAV_system_configurations" ]
then
    echo -e "> creating system configuration directory OpenAV_system_configurations"
    mkdir /opt/OpenAV/"OpenAV_system_configurations"
    if [ $? -eq 1 ]
    then
        echo -e "error: couldn't create directory OpenAV_system_configurations, can't proceed further"
        exit 1
    fi
fi

orchestrator_deploy_args="-e DNS_HARD_CACHE=false \
-e SYSTEM_CONFIGURATIONS_VIA_VOLUME=true \
-e TZ=America/Los_Angeles \
-v ${system_configs_folder}:/system_configurations"

echo -e "> instantiating ${CYAN}orchestrator${RESET}"
$sudo_docker docker stop orchestrator > /dev/null 2>&1
$sudo_docker docker rm orchestrator > /dev/null 2>&1
$sudo_docker docker pull ghcr.io/dartmouth-openav/orchestrator:${mode}$architecture > /dev/null 2>&1
echo -e ">   finding available port"
for orchestrator_port in $(seq 81 65535)
do
    echo -e ">     $orchestrator_port"
    if ! nc -z -w 3 $netcat_options localhost $orchestrator_port 2>/dev/null
    then
        break
    fi
done
$sudo_docker docker run -tdi \
    --restart unless-stopped \
    -p $orchestrator_port:80 \
    -e ADDRESS_MICROSERVICES_BY_NAME=true \
    $orchestrator_deploy_args \
    --network openav \
    --network-alias orchestrator \
    --name orchestrator \
    ghcr.io/dartmouth-openav/orchestrator:${mode}$architecture > /dev/null 2>&1
$sudo_docker docker exec -ti orchestrator sh -c 'echo \* > /authorization.json'

echo -e "> picking from available IPs for communication"
ip=localhost

# Prefer the swarm advertise address if one was chosen earlier
if [ -n "$swarm_advertise_addr" ]
then
    ip="$swarm_advertise_addr"
    echo -e ">   using swarm advertise address $ip for UI/orchestrator URLs"

# If connected over SSH, prefer the SSH client IP
elif [ -n "${SSH_CONNECTION}" ]
then
    ip=$(echo "${SSH_CONNECTION}" | cut -d" " -f3)
else
    # Try to use the modern 'ip' command first
    if command -v ip >/dev/null 2>&1
    then
        hardware_nics=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth|^wlan' || true)
        for hardware_nic in $hardware_nics
        do
            potential_ip=$(ip -4 addr show "$hardware_nic" | awk '/inet / {print $2}' | cut -d"/" -f1 | sort -u)
            if [ -n "$potential_ip" ]
            then
                echo -e ">  ${hardware_nic} ${potential_ip}"
                if nc -z -w 3 $netcat_options $potential_ip $orchestrator_port 2>/dev/null
                then
                    ip=$potential_ip
                    break
                fi
            fi
        done
    # Fallback to legacy 'ifconfig' if available
    elif command -v ifconfig >/dev/null 2>&1
    then
        hardware_nics=$(ifconfig | grep 'flags=' | cut -d: -f1 | grep '^en\|^eth\|^wlan' || true)
        for hardware_nic in $hardware_nics
        do
            potential_ip=$(ifconfig "$hardware_nic" | grep inet | grep -v inet6 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -d" " -f2 | sort -u)
            if [ -n "$potential_ip" ]
            then
                echo -e ">  ${hardware_nic} ${potential_ip}"
                if nc -z -w 3 $netcat_options $potential_ip $orchestrator_port 2>/dev/null
                then
                    ip=$potential_ip
                    break
                fi
            fi
        done
    fi
fi

echo -e "> instantiating ${BLUE}UI${RESET}"
$sudo_docker docker stop frontend-web > /dev/null 2>&1
$sudo_docker docker rm frontend-web > /dev/null 2>&1
$sudo_docker docker pull ghcr.io/dartmouth-openav/frontend-web:${mode}$architecture > /dev/null 2>&1
echo -e ">   finding available port"
for ui_port in $(seq 80 65535)
do
    echo -e ">     $ui_port"
    if ! nc -z -w 3 $netcat_options localhost $ui_port 2>/dev/null
    then
        break
    fi
done
$sudo_docker docker run -tdi \
    --restart unless-stopped \
    -p $ui_port:80 \
    -e HOME_ORCHESTRATOR=http://$ip:$orchestrator_port \
    --network openav \
    --network-alias frontend-web \
    --name frontend-web \
    ghcr.io/dartmouth-openav/frontend-web:${mode}$architecture > /dev/null 2>&1

ui_port_if_not_80=""
if [ "$ui_port" != "80" ]
then
    ui_port_if_not_80=":$ui_port"
fi

echo -e "> ${CYAN}orchestrator${RESET} available at: http://${ip}:$orchestrator_port"
echo -e "> ${BLUE}UI${RESET} available at: http://${ip}$ui_port_if_not_80"
echo -e "> Configuration files directory: ${system_configs_folder}"
