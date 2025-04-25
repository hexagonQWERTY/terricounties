#!/bin/bash
# deploy.sh - Complete deployment script for Hetzner with Docker Hub and R2
# This script:
# 1. Builds and uploads the Docker image to Docker Hub with appropriate tag
# 2. Copies the update script to Hetzner server
# 3. Executes the update script on the Hetzner server

set -e  # Exit immediately if a command exits with a non-zero status

# Check command line arguments
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Error: Please specify environment and host, with optional subdomain"
    echo "Usage: $0 [prod|staging] [eu|us|staging] [subdomain]"
    exit 1
fi

# Validate first argument (environment)
if [ "$1" != "prod" ] && [ "$1" != "staging" ]; then
    echo "Error: First argument must be either 'prod' or 'staging'"
    echo "Usage: $0 [prod|staging] [eu|us|staging] [subdomain]"
    exit 1
fi

# Validate second argument (host)
if [ "$2" != "eu" ] && [ "$2" != "us" ] && [ "$2" != "staging" ]; then
    echo "Error: Second argument must be either 'eu', 'us', or 'staging'"
    echo "Usage: $0 [prod|staging] [eu|us|staging] [subdomain]"
    exit 1
fi

# Function to print section headers
print_header() {
    echo "======================================================"
    echo "🚀 $1"
    echo "======================================================"
}

ENV=$1
HOST=$2
SUBDOMAIN=$3  # Optional third argument for custom subdomain

# Set subdomain - use the custom subdomain if provided, otherwise use REGION
if [ -n "$SUBDOMAIN" ]; then
    echo "Using custom subdomain: $SUBDOMAIN"
else
    SUBDOMAIN=$HOST
    echo "Using host as subdomain: $SUBDOMAIN"
fi

# Load common environment variables first
if [ -f .env ]; then
    echo "Loading common configuration from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Load environment-specific variables
if [ -f .env.$ENV ]; then
    echo "Loading $ENV-specific configuration from .env.$ENV file..."
    export $(grep -v '^#' .env.$ENV | xargs)
else
    echo "Error: Environment file .env.$ENV not found"
    exit 1
fi

if [ "$HOST" == "staging" ]; then
    print_header "DEPLOYING TO STAGING HOST"
    SERVER_HOST=$SERVER_HOST_STAGING
elif [ "$HOST" == "us" ]; then
    print_header "DEPLOYING TO US HOST"
    SERVER_HOST=$SERVER_HOST_US
else
    print_header "DEPLOYING TO EU HOST"
    SERVER_HOST=$SERVER_HOST_EU
fi

# Check required environment variables
if [ -z "$SERVER_HOST" ]; then
    echo "Error: ${HOST} not defined in .env file or environment"
    exit 1
fi

# Configuration
UPDATE_SCRIPT="./update.sh"                    # Path to your update script
REMOTE_USER="openfront"                        
REMOTE_UPDATE_PATH="/home/$REMOTE_USER"        
REMOTE_UPDATE_SCRIPT="$REMOTE_UPDATE_PATH/update-openfront.sh"  # Where to place the script on server

IMAGE_NAME="${DOCKER_USERNAME}/${DOCKER_REPO}"
DOCKER_IMAGE="${IMAGE_NAME}:${VERSION_TAG}"

# Check if update script exists
if [ ! -f "$UPDATE_SCRIPT" ]; then
    echo "Error: Update script $UPDATE_SCRIPT not found!"
    exit 1
fi

# Step 1: Build and upload Docker image to Docker Hub
print_header "STEP 1: Building and uploading Docker image to Docker Hub"
echo "Environment: ${ENV}"
echo "Host: ${HOST}"
echo "Subdomain: ${SUBDOMAIN}"
echo "Using version tag: $VERSION_TAG"
echo "Docker repository: $DOCKER_REPO"

# Get Git commit for build info
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
echo "Git commit: $GIT_COMMIT"

docker buildx build \
  --platform linux/amd64 \
  --build-arg GIT_COMMIT=$GIT_COMMIT \
  -t $DOCKER_USERNAME/$DOCKER_REPO:$VERSION_TAG \
  --push \
  .

if [ $? -ne 0 ]; then
    echo "❌ Docker build failed. Stopping deployment."
    exit 1
fi

echo "✅ Docker image built and pushed successfully."

# Step 2: Copy update script to Hetzner server
print_header "STEP 2: Copying update script to server"
echo "Target: $REMOTE_USER@$SERVER_HOST"

# Make sure the update script is executable
chmod +x $UPDATE_SCRIPT

# Copy the update script to the server
scp -i $SSH_KEY $UPDATE_SCRIPT $REMOTE_USER@$SERVER_HOST:$REMOTE_UPDATE_SCRIPT

if [ $? -ne 0 ]; then
    echo "❌ Failed to copy update script to server. Stopping deployment."
    exit 1
fi

ssh -i $SSH_KEY $REMOTE_USER@$SERVER_HOST "chmod +x $REMOTE_UPDATE_SCRIPT && \
cat > $REMOTE_UPDATE_PATH/.env << 'EOL'
GAME_ENV=$ENV
ENV=$ENV
HOST=$HOST
SUBDOMAIN=$SUBDOMAIN
DOCKER_IMAGE=$DOCKER_IMAGE
DOCKER_TOKEN=$DOCKER_TOKEN
ADMIN_TOKEN=$ADMIN_TOKEN
CF_ACCOUNT_ID=$CF_ACCOUNT_ID
R2_ACCESS_KEY=$R2_ACCESS_KEY
R2_SECRET_KEY=$R2_SECRET_KEY
R2_BUCKET=$R2_BUCKET
CF_API_TOKEN=$CF_API_TOKEN
DOMAIN=$DOMAIN
SUBDOMAIN=$SUBDOMAIN
MON_USERNAME=$MON_USERNAME
MON_PASSWORD=$MON_PASSWORD
EOL
chmod 600 $REMOTE_UPDATE_PATH/.env && \
$REMOTE_UPDATE_SCRIPT"

if [ $? -ne 0 ]; then
    echo "❌ Failed to execute update script on server."
    exit 1
fi

print_header "DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "✅ New version deployed to ${ENV} environment in ${HOST} with subdomain ${SUBDOMAIN}!"
echo "🌐 Check your server to verify the deployment."
echo "======================================================="