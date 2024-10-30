# config.sh

# Azure Service Principal credentials
AZURE_CLIENT_ID=""       # Replace with your Azure Service Principal Client ID
AZURE_TENANT_ID=""       # Replace with your Azure Tenant ID
AZURE_CLIENT_SECRET="" # Replace with your Azure Service Principal Client Secret

# ACR and Azure Variables
ACR_NAME="trussedai"  # Azure Container Registry name
RESOURCE_GROUP="trussedai-aks"
LOCATION="east-us"  # Azure region (e.g., eastus, westus, etc.)

# Docker Hub Credentials
DOCKER_HUB_USER=""
DOCKER_HUB_PASSWORD=""


AKS_CLUSTER_NAME="trussedai-aks"
K8S_NAMESPACE="trussedai"

# SSL Certificate Paths (customer-provided)
SSL_CERT_PATH="/home/azureuser/installation/ssl/tls.crt"  # Path to SSL Certificate File
SSL_KEY_PATH="/home/azureuser/installation/ssl/tls.key"   # Path to SSL Key File

# List of Docker images to sync (DockerHub image -> ACR repository name)
IMAGES_LIST=(
  "adankar/trussed_ai_cp:latest trussedai/trussed_ai_cp:latest"
  "adankar/trussed_ai_dp:latest trussedai/trussed_ai_dp:latest"
  # Add more image pairs as needed
)

# Sensitive Application Configuration (customer-provided)
JWT_SECRET=""           # JWT Secret for your application
MONGODB_URL="mongodb+srv://trussedazure:Cosmo123@trussed-ai-devtest.mongocluster.cosmos.azure.com/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false&maxIdleTimeMS=120000"
MONGODB_NAME="trusseddb"         # MongoDB Database Name
TAIC_ADMIN_EMAIL="malluriaravindreddy@gmail.com"     # Admin Email (TAIC Admin)
TAIC_ADMIN_PASSWORD=""  # Admin Password (TAIC Admin)
DOMAIN=""               # Domain Name for the application
