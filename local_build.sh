# Linux dev script that removes any old container and rebuilds a new one locally
# Put this in the repository root of your microservice

# Pass in the name of the microservice
MICROSERVICE_NAME=$1

# Find container (running or stopped) for this image
container=$(sudo docker ps -aqf "ancestor=microservice-extron-sis")

# Stop and remove if found
if [ -n "$container" ]; then
  sudo docker stop "$container" >/dev/null 2>&1
  sudo docker rm "$container"
fi

# Rebuild, but don't run
sudo docker build -t microservice-extron-sis .
