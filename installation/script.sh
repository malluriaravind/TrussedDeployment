#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Enable debugging (optional; uncomment for debugging)
# set -x

# Source the config.sh file for variables using absolute path
source /home/azureuser/installation/config.sh  # Ensure the absolute path is correct

# Define the Kubernetes secret names
K8S_SECRET_NAME="acr-secret"
SSL_SECRET_NAME="ssl-cert-secret"
APP_SECRETS_NAME="app-secrets"

# Define the Helm release name
HELM_RELEASE_NAME="my-app"

# Function to check if required sensitive values are set
check_sensitive_values() {
  echo "Checking for sensitive values in config.sh..."

  missing=false

  # List of required variables (Removed SMTP_USER and SMTP_PASSWORD)
  required_vars=("JWT_SECRET" "MONGODB_URL" "MONGODB_NAME" "TAIC_ADMIN_EMAIL" "TAIC_ADMIN_PASSWORD" "DOMAIN" "SSL_CERT_PATH" "SSL_KEY_PATH")

  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "Error: $var is not set in config.sh."
      missing=true
    fi
  done

  if [ "$missing" = true ]; then
    echo "Please set all required variables in config.sh and try again."
    exit 1
  fi

  echo "All required sensitive values are set."
}

# Function to install Azure CLI if not installed
install_azure_cli() {
  echo "Azure CLI is not installed. Installing Azure CLI..."
  if command -v apt-get &> /dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  elif command -v yum &> /dev/null; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo sh -c 'echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
    sudo yum install -y azure-cli
  else
    echo "Unsupported package manager. Please install Azure CLI manually."
    exit 1
  fi
  echo "Azure CLI installed successfully."
}

# Function to install kubectl if not installed
install_kubectl() {
  echo "kubectl is not installed. Installing kubectl..."
  if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https ca-certificates curl
    sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -y
    sudo apt-get install -y kubectl
  elif command -v yum &> /dev/null; then
    sudo tee /etc/yum.repos.d/kubernetes.repo <<-'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
    sudo yum install -y kubectl
  else
    echo "Unsupported package manager. Please install kubectl manually."
    exit 1
  fi
  echo "kubectl installed successfully."
}

# Function to install Docker if not installed
install_docker() {
  echo "Docker is not installed. Installing Docker..."
  if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y docker.io
    sudo systemctl start docker
    sudo systemctl enable docker
  elif command -v yum &> /dev/null; then
    sudo yum update -y
    sudo yum install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
  else
    echo "Unsupported package manager. Please install Docker manually."
    exit 1
  fi
  echo "Docker installed successfully."
}

# Function to install OpenSSL if not installed
install_openssl() {
  echo "Checking for OpenSSL..."
  if ! command -v openssl &> /dev/null; then
    echo "OpenSSL is not installed. Installing OpenSSL..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get update -y
      sudo apt-get install -y openssl
    elif command -v yum &> /dev/null; then
      sudo yum update -y
      sudo yum install -y openssl
    else
      echo "Unsupported package manager. Please install OpenSSL manually."
      exit 1
    fi
    echo "OpenSSL installed successfully."
  else
    echo "OpenSSL is already installed."
  fi
}

# Function to install jq if not installed
install_jq() {
  echo "Checking for jq..."
  if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Installing jq..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get update -y
      sudo apt-get install -y jq
    elif command -v yum &> /dev/null; then
      sudo yum update -y
      sudo yum install -y jq
    else
      echo "Unsupported package manager. Please install jq manually."
      exit 1
    fi
    echo "jq installed successfully."
  else
    echo "jq is already installed."
  fi
}

# Function to install Helm if not installed
install_helm() {
  echo "Checking for Helm..."
  if ! command -v helm &> /dev/null; then
    echo "Helm is not installed. Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    if [ $? -ne 0 ]; then
      echo "Failed to install Helm. Exiting."
      exit 1
    fi
    echo "Helm installed successfully."
  else
    echo "Helm is already installed."
  fi
}

# Function to install required tools if not present
install_tools() {
  # Check if Azure CLI is installed
  if ! command -v az &> /dev/null; then
    install_azure_cli
  else
    echo "Azure CLI is already installed."
  fi

  # Update Azure CLI to the latest version
  echo "Updating Azure CLI to the latest version..."
  az upgrade --yes
  echo "Azure CLI updated successfully."

  # Check if kubectl is installed
  if ! command -v kubectl &> /dev/null; then
    install_kubectl
  else
    echo "kubectl is already installed."
  fi

  # Check if Docker is installed
  if ! command -v docker &> /dev/null; then
    install_docker
  else
    echo "Docker is already installed."
  fi

  # Check if OpenSSL is installed
  install_openssl

  # Check if jq is installed
  install_jq

  # Check if Helm is installed
  install_helm
}

# Function to perform Azure login using Service Principal
azure_login() {
  echo "Logging into Azure using Service Principal..."
  if [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ]; then
    echo "Azure Service Principal credentials are not set in config.sh. Exiting."
    exit 1
  fi

  az login --service-principal --username "$AZURE_CLIENT_ID" --password "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" &>/dev/null
  if [ $? -ne 0 ]; then
    echo "Azure login failed. Please check your credentials. Exiting."
    exit 1
  fi
  echo "Azure login successful."
}

# Function to set Azure subscription if specified
set_azure_subscription() {
  if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Setting Azure subscription to '$AZURE_SUBSCRIPTION_ID'..."
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    if [ $? -ne 0 ]; then
      echo "Failed to set Azure subscription to '$AZURE_SUBSCRIPTION_ID'. Exiting."
      exit 1
    fi
    echo "Azure subscription set successfully."
  fi
}

# Function to authenticate to Kubernetes cluster
authenticate_k8s_cluster() {
  echo "Authenticating to Kubernetes cluster '$AKS_CLUSTER_NAME' in resource group '$RESOURCE_GROUP'..."
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing &>/dev/null
  if [ $? -ne 0 ]; then
    echo "Failed to authenticate to Kubernetes cluster. Exiting."
    exit 1
  fi
  echo "Kubernetes cluster authentication successful."
}

# Function to ensure Kubernetes namespace exists
ensure_k8s_namespace() {
  echo "Checking if Kubernetes namespace '$K8S_NAMESPACE' exists..."
  NAMESPACE_EXIST=$(kubectl get namespace "$K8S_NAMESPACE" --ignore-not-found)
  if [ -z "$NAMESPACE_EXIST" ]; then
    echo "Namespace '$K8S_NAMESPACE' does not exist. Creating namespace..."
    kubectl create namespace "$K8S_NAMESPACE"
    if [ $? -ne 0 ]; then
      echo "Failed to create namespace '$K8S_NAMESPACE'. Exiting."
      exit 1
    fi
    echo "Namespace '$K8S_NAMESPACE' created successfully."
  else
    echo "Namespace '$K8S_NAMESPACE' already exists."
  fi
}

# Function to check or create ACR
ensure_acr_exists() {
  echo "Checking if Azure Container Registry (ACR) '$ACR_NAME' exists in resource group '$RESOURCE_GROUP'..."
  EXISTING_ACR=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query "name" -o tsv 2>/dev/null)
  if [ -z "$EXISTING_ACR" ]; then
    echo "ACR '$ACR_NAME' does not exist. Creating ACR..."
    az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" --sku Basic --location "$LOCATION" --admin-enabled true
    if [ $? -ne 0 ]; then
      echo "Failed to create ACR '$ACR_NAME'. Exiting."
      exit 1
    fi
    echo "ACR '$ACR_NAME' created successfully."
  else
    echo "ACR '$ACR_NAME' already exists."
  fi
}

# Function to retrieve current ACR credentials
get_acr_credentials() {
  echo "Retrieving ACR admin credentials..."
  ACR_CREDENTIALS=$(az acr credential show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" -o json)
  if [ $? -ne 0 ]; then
    echo "Failed to retrieve ACR credentials. Exiting."
    exit 1
  fi

  ACR_USERNAME=$(echo "$ACR_CREDENTIALS" | jq -r '.username')
  ACR_PASSWORD=$(echo "$ACR_CREDENTIALS" | jq -r '.passwords[0].value')

  if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
    echo "Failed to retrieve ACR username or password. Exiting."
    exit 1
  fi
  echo "ACR admin credentials retrieved successfully."
}

# Function to check and update Kubernetes secret for ACR credentials
check_and_update_secret() {
  echo "Checking and updating Kubernetes secret '$K8S_SECRET_NAME' if credentials have changed..."

  # Retrieve current ACR credentials
  get_acr_credentials

  # Check if Kubernetes secret exists
  SECRET_EXIST=$(kubectl get secret "$K8S_SECRET_NAME" --namespace "$K8S_NAMESPACE" --ignore-not-found)

  if [ -z "$SECRET_EXIST" ]; then
    echo "Secret '$K8S_SECRET_NAME' does not exist. Creating the secret..."
    kubectl create secret docker-registry "$K8S_SECRET_NAME" \
      --docker-server="$ACR_NAME.azurecr.io" \
      --docker-username="$ACR_USERNAME" \
      --docker-password="$ACR_PASSWORD" \
      --docker-email="noreply@example.com" \
      --namespace "$K8S_NAMESPACE"
    if [ $? -ne 0 ]; then
      echo "Failed to create Kubernetes secret '$K8S_SECRET_NAME'. Exiting."
      exit 1
    fi
    echo "Kubernetes secret '$K8S_SECRET_NAME' created successfully."
  else
    echo "Kubernetes secret '$K8S_SECRET_NAME' already exists. Skipping creation."
  fi
}

# Function to store SSL certificates in Kubernetes secret
store_ssl_in_k8s_secret() {
  echo "Storing SSL certificates in Kubernetes secret..."

  # Check if the secret already exists
  SECRET_EXIST=$(kubectl get secret "$SSL_SECRET_NAME" --namespace "$K8S_NAMESPACE" --ignore-not-found)

  if [ -z "$SECRET_EXIST" ]; then
    echo "Secret '$SSL_SECRET_NAME' does not exist. Creating the secret..."
    kubectl create secret tls "$SSL_SECRET_NAME" \
      --cert="$SSL_CERT_PATH" \
      --key="$SSL_KEY_PATH" \
      --namespace "$K8S_NAMESPACE"
    if [ $? -ne 0 ]; then
      echo "Failed to create Kubernetes secret with SSL certificates. Exiting."
      exit 1
    fi
    echo "SSL certificates stored in Kubernetes secret '$SSL_SECRET_NAME' successfully."
  else
    echo "Kubernetes secret '$SSL_SECRET_NAME' already exists. Skipping creation."
  fi
}

# Function to create Kubernetes secret with sensitive app values
create_app_secrets() {
  echo "Creating Kubernetes secret '$APP_SECRETS_NAME' with application sensitive values..."

  # Check if the secret already exists
  SECRET_EXIST=$(kubectl get secret "$APP_SECRETS_NAME" --namespace "$K8S_NAMESPACE" --ignore-not-found)

  if [ -z "$SECRET_EXIST" ]; then
    echo "Secret '$APP_SECRETS_NAME' does not exist. Creating the secret..."
    kubectl create secret generic "$APP_SECRETS_NAME" \
      --namespace "$K8S_NAMESPACE" \
      --from-literal=jwtSecret="$JWT_SECRET" \
      --from-literal=databaseUrl="$MONGODB_URL" \
      --from-literal=databaseName="$MONGODB_NAME" \
      --from-literal=rootUserEmail="$TAIC_ADMIN_EMAIL" \
      --from-literal=rootUserPassword="$TAIC_ADMIN_PASSWORD" \
      --from-literal=domain="$DOMAIN"
    if [ $? -ne 0 ]; then
      echo "Failed to create Kubernetes secret '$APP_SECRETS_NAME'. Exiting."
      exit 1
    fi
    echo "Kubernetes secret '$APP_SECRETS_NAME' created successfully."
  else
    echo "Kubernetes secret '$APP_SECRETS_NAME' already exists. Skipping creation."
  fi
}

# Function to deploy the application using Helm (handles install and upgrade)
deploy_with_helm() {
  echo "Deploying application using Helm..."

  # Define the absolute path to the Helm chart directory
  HELM_CHART_DIR="/home/azureuser/trussedai/trussedai-helm"

  # Check if the Helm chart directory exists (directly or within a subdirectory)
  if [ -d "$HELM_CHART_DIR/helm-chart" ]; then
    CHART_PATH="$HELM_CHART_DIR/helm-chart"
  elif [ -f "$HELM_CHART_DIR/Chart.yaml" ]; then
    CHART_PATH="$HELM_CHART_DIR"
  else
    echo "Helm chart not found in '$HELM_CHART_DIR'. Exiting."
    exit 1
  fi

  echo "Using Helm chart directory: $CHART_PATH"

  # Change to the Helm chart directory
  cd "$CHART_PATH"

  # Ensure that 'values.yaml' exists
  if [ ! -f "./values.yaml" ]; then
    echo "'values.yaml' does not exist in '$CHART_PATH'. Exiting."
    exit 1
  fi

  # Check if the Helm release already exists
  helm_release_exists=$(helm list --namespace "$K8S_NAMESPACE" --filter "^$HELM_RELEASE_NAME$" -o json | jq 'length')

  if [ "$helm_release_exists" -eq 0 ]; then
    echo "Helm release '$HELM_RELEASE_NAME' does not exist. Performing 'helm install'..."
    helm install "$HELM_RELEASE_NAME" . \
      --namespace "$K8S_NAMESPACE" \
      --values ./values.yaml
    if [ $? -ne 0 ]; then
      echo "Helm install failed. Exiting."
      exit 1
    fi
    echo "Helm install completed successfully."
  else
    echo "Helm release '$HELM_RELEASE_NAME' exists. Performing 'helm upgrade'..."
    helm upgrade "$HELM_RELEASE_NAME" . \
      --namespace "$K8S_NAMESPACE" \
      --values ./values.yaml
    if [ $? -ne 0 ]; then
      echo "Helm upgrade failed. Exiting."
      exit 1
    fi
    echo "Helm upgrade completed successfully."
  fi

  echo "Application deployed successfully with Helm."
}

# Main Execution Flow

# Step 0: Check sensitive values
check_sensitive_values

# Step 1: Install necessary tools
install_tools

# Step 2: Azure login
azure_login

# Step 3: Set Azure subscription if specified
set_azure_subscription

# Step 4: Authenticate to Kubernetes cluster
authenticate_k8s_cluster

# Step 5: Ensure Kubernetes namespace exists
ensure_k8s_namespace

# Step 6: Ensure ACR exists
ensure_acr_exists

# Step 7: Store SSL certificates in Kubernetes secret
store_ssl_in_k8s_secret

# Step 8: Check and update Kubernetes secret for ACR credentials
check_and_update_secret

# Step 9: Create Kubernetes secret with application sensitive values
create_app_secrets

# Step 10: Deploy application using Helm (handles install and upgrade)
deploy_with_helm

echo "All tasks completed successfully."
