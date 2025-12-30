# OpenAV-Enhanced-Quickstart

Manual steps to get an [OpenAV](https://github.com/dartmouth-openav) system up and running without the full CI/CD pipeline

You'll have a fully functional system up and running with a local Docker Registry that can be used for running unofficial or in-development device microservices.  This is useful for running full test rooms, development outside of Dartmouth, and as a transitional step between OpenAV's quickstart script and implementing the full CI/CD pipeline.

For simple testing or basic proof of concept, use [quickstart.sh](https://raw.githubusercontent.com/Dartmouth-OpenAV/.github/refs/heads/main/quickstart.sh) instead

## Requirements

- A linux server with internet connection and connection to the devices you want to control
- A workstation (OS agnostic) with internet connection and connection to the server
- If your workstation is Windows, [WinSCP](https://winscp.net/eng/index.php) will make things easier but is not required
- If your workstation is Windows, it is recommended to [install the latest PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5) (not 'Windows PowerShell' that comes with the OS, just 'PowerShell')
- At least one OpenAV room configuration JSON file

## Install Docker Engine

Install on your workstation and the server.  Server must be some flavor of Linux but the workstation can be any OS.  
If your workstation is Windows, I recommend [Rancher Desktop](https://rancherdesktop.io/) instead of Docker Desktop (you'd need to pay for Docker Desktop)

<https://docs.docker.com/engine/install/>

## Make an app directory and assign permissions

```bash
# On Server
cd /opt
sudo mkdir OpenAV
sudo groupadd oav-managers
sudo usermod -aG docker,oav-managers <username>
sudo chgrp oav-managers /opt/OpenAV
sudo chmod -R 775 /opt/OpenAV
sudo chmod g+s /opt/OpenAV

# log off and back on again here to apply latest permissions to your user

mkdir /opt/OpenAV/OpenAV_system_configurations 
```

## Copy files

- Copy `start.sh` script to `/opt/OpenAV` on the server

- Copy room JSON config files to `/opt/OpenAV/OpenAV_system_configurations` on the server

## Install and Configure a Local Docker Registry

```bash
# On server
sudo mkdir -p /docker-registry-storage
sudo mkdir -p /docker-registry-auth

# Make sure to change username and password below!
docker run --rm \
  --entrypoint htpasswd \
  httpd:2 -Bbn <myuser> <mypassword> | sudo tee /docker-registry-auth/htpasswd

docker run -d \
  -p 5000:5000 \
  --name registry \
  --restart always \
  --memory="1g" \
  --cpus="1.0" \
  -v /docker-registry-storage:/var/lib/registry \
  -v /docker-registry-auth:/auth \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -e REGISTRY_STORAGE_DELETE_ENABLED=true \
  -e REGISTRY_LOG_LEVEL=info \
  -e OTEL_TRACES_EXPORTER=none \
  registry:3

```

## Clone any in-development or unofficial microservice and build a local image on a workstation

### From scratch, using microservice-extron-sis as an example

```bash
# On workstation
cd # <to where you want the repo>
git clone https://github.com/mefranklin6/microservice-extron-sis
cd microservice-extron-sis
git submodule sync --recursive
git submodule update --init --recursive --depth 1

# If your microservice repo does not have local_build scripts, you can copy them from this repo
./local_build.ps1 -Name "microservice-extron-sis" # or './local_build.sh microservice-extron-sis' if on Linux

docker login <registry_host>:5000 
# use username and pw you made in the previous step to login

# Until we move to prod and get a cert for TLS, you need to configure your docker host
# ...to accept the registry as an 'unsecure-registry'.  See your engine's documentation

docker tag microservice-extron-sis:latest <registry_host>:5000/microservice-extron-sis:latest
docker push <registry_host>:5000/microservice-extron-sis:latest

```

*If you get errors running copied .sh scripts, it may be due to Windows adding a carriage return to the line feed for new lines.  You can remove them with `sed -i 's/\r$//' your_script.sh`.  This seems to be an issue only with some distros like Ubuntu, where others like Mint handle it fine.*

### If simply updating to the latest version of the microservice

```bash
# On workstation
git pull
./local_build.sh <microservice name>

docker login <registry_host>:5000
# enter your credentials here
docker tag microservice-extron-sis:latest <registry_host>:5000/microservice-extron-sis:latest
docker push <registry_host>:5000/microservice-extron-sis:latest
```

## Start the System

```bash
# On server 

# localhost address is added to 'unsecure-registry' list by default
docker login 127.0.0.1:5000
# enter your credentials here

cd /opt/OpenAV
sudo chmod +x start.sh
./start.sh <microservices you need delimited by spaces>
```

## Check the system

The script will tell you where the UI is. It's typically the IP of the docker host on port 80. To get to specific systems you need to add parameters in the URL. `http://<ui_url>/?system=my_system` for example if you had a `my_system.json` config file in OpenAV_system_configurations.

## Check orchestrator errors endpoint

On any browser:
`http://<orchestrator_url>:<port>/api/errors`

## Check container logs

You can find the container names with `docker ps`

`docker logs <container_name>`  You can add a `-f` for live scrolling logs.
