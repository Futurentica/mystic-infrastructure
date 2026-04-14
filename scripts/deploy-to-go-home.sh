#!/bin/bash

set -e

# Конфигурация - просто mini
HOSTNAME="go-home"
NAMESPACE="mystic-platform"
REGISTRY="${HOSTNAME}:5000"

echo "🚀 Deploying to Mac Mini: ${HOSTNAME}"

# Проверяем доступность
if ! ssh ${HOSTNAME} "echo OK" &>/dev/null; then
    echo "❌ Cannot reach ${HOSTNAME}"
    echo "   Make sure you have SSH configured: ssh go-home"
    exit 1
fi

# Переключаем Docker context
docker context use go-home 2>/dev/null || {
    echo "Creating Docker context for ${HOSTNAME}..."
    docker context create go-home --docker "host=ssh://${HOSTNAME}"
    docker context use go-home
}

# Устанавливаем kubeconfig
export KUBECONFIG=~/.kube/config-go-home

# Создаем namespace
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Функция сборки и пуша
build_and_push() {
    local service=$1
    local dockerfile=$2
    
    echo "📦 Building ${service} for linux/amd64..."
    
    docker buildx build \
        --platform linux/amd64 \
        -t ${REGISTRY}/${service}:latest \
        -f ${dockerfile} \
        --push \
        ../${service}
    
    echo "✅ ${service} image pushed to ${REGISTRY}/${service}:latest"
}

# Деплой Redis
echo "📦 Deploying Redis..."
kubectl apply -f - << 'REDIS'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-cache
  namespace: mystic-platform
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
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cache
  namespace: mystic-platform
spec:
  selector:
    app: redis-cache
  ports:
  - port: 6379
    targetPort: 6379
REDIS

# Деплой RabbitMQ
echo "📦 Deploying RabbitMQ..."
kubectl apply -f - << 'RABBIT'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
  namespace: mystic-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.13-management-alpine
        ports:
        - containerPort: 5672
        - containerPort: 15672
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: mystic-platform
spec:
  selector:
    app: rabbitmq
  ports:
  - name: amqp
    port: 5672
  - name: management
    port: 15672
RABBIT

# Деплой Ollama
echo "📦 Deploying Ollama..."
kubectl apply -f - << 'OLLAMA'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: mystic-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:0.1.48
        ports:
        - containerPort: 11434
        resources:
          requests:
            memory: "4Gi"
            cpu: "2000m"
          limits:
            memory: "6Gi"
            cpu: "3000m"
        volumeMounts:
        - name: ollama-storage
          mountPath: /root/.ollama
        command: ["/bin/sh"]
        args: ["-c", "ollama pull qwen3:1.8b && ollama serve"]
      volumes:
      - name: ollama-storage
        hostPath:
          path: /mnt/data/ollama
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: mystic-platform
spec:
  selector:
    app: ollama
  ports:
  - port: 11434
OLLAMA

# Сборка и деплой API Gateway
if [ -d "../api-gateway" ]; then
    echo "📦 Building API Gateway..."
    build_and_push "api-gateway" "Dockerfile"
    
    echo "📦 Deploying API Gateway..."
    cat << GATEWAY | sed "s|REGISTRY_PLACEHOLDER|${REGISTRY}|g" | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: mystic-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: gateway
        image: REGISTRY_PLACEHOLDER/api-gateway:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
        - name: GATEWAY_PORT
          value: "8080"
        - name: REDIS_URL
          value: "redis://redis-cache:6379"
        - name: AUTH_SERVICE_URL
          value: "http://auth-service:8080"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: mystic-platform
spec:
  selector:
    app: api-gateway
  ports:
  - port: 8080
    targetPort: 8080
  type: LoadBalancer
GATEWAY
fi

# Ждем готовности
echo "⏳ Waiting for deployments..."
kubectl wait --for=condition=available deployment/redis-cache -n ${NAMESPACE} --timeout=60s 2>/dev/null || true
kubectl wait --for=condition=available deployment/rabbitmq -n ${NAMESPACE} --timeout=60s 2>/dev/null || true

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Services:"
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}

# Получаем IP
LB_IP=$(kubectl get svc api-gateway -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
if [ ! -z "$LB_IP" ]; then
    echo ""
    echo "🌐 API Gateway: http://${LB_IP}:8080"
    echo "🔍 Health check: curl http://${LB_IP}:8080/health"
fi

# Возвращаем Docker context
docker context use default
