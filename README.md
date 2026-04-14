# Mystic Platform Infrastructure

Kubernetes manifests and deployment scripts for Mystic Platform.

## Structure
├── k8s/ # Kubernetes manifests
│ ├── namespace.yaml # Namespace definition
│ ├── redis.yaml # Redis deployment
│ ├── rabbitmq.yaml # RabbitMQ deployment
│ ├── postgres-auth.yaml # Auth database
│ ├── postgres-profile.yaml # Profile database
│ └── ingress.yaml # Ingress configuration
├── docker-compose/ # Local development
│ └── docker-compose.yml
└── scripts/ # Deployment scripts
  ├── deploy.sh # Full deployment
  └── local-dev.sh # Local development

## Usage

```bash
# Deploy all infrastructure
./scripts/deploy.sh

# Local development
./scripts/local-dev.sh
````
