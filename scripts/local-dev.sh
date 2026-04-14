#!/bin/bash

set -e

NAMESPACE="mystic-platform"
echo "🚀 Starting Mystic Platform infrastructure..."

# Создаем namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Деплоим Redis
cat << 'REDIS' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cache
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-cache
  template:
    metadata:
      labels:
        app: redis-cache
    spec:
      containers:
      - name: redis
        image: redis:7.2-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cache
  namespace: $NAMESPACE
spec:
  selector:
    app: redis-cache
  ports:
  - port: 6379
    targetPort: 6379
REDIS

# Деплоим API Gateway
cd ../api-gateway
docker build -t api-gateway:latest .
k3d image import api-gateway:latest -c mystic-platform
kubectl apply -f k8s/deployment.yaml -n $NAMESPACE

# Ждем готовности
echo "⏳ Waiting for pods..."
kubectl wait --for=condition=ready pod -l app=redis-cache -n $NAMESPACE --timeout=60s
kubectl wait --for=condition=ready pod -l app=api-gateway -n $NAMESPACE --timeout=60s

echo "✅ Infrastructure is ready!"
echo ""
echo "📊 Services:"
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE
echo ""
echo "🌐 Gateway доступен на: http://localhost:8080"
echo "🔍 Проверка: curl http://localhost:8080/health"
