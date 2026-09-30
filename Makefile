.PHONY: help up up-all infra down clean build test test-unit web smoke load logs kafka-topics k8s-images k8s-deploy

help:            ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env         ## Build and start everything (infra, services, frontend)
	docker compose up --build -d
	@echo "Shop: http://localhost:3000   Kafka UI: http://localhost:8090   Jaeger: http://localhost:16686   Mail: http://localhost:8025"

up-all: .env     ## Same as up, plus Prometheus and Grafana
	docker compose -f docker-compose.yml -f docker-compose.observability.yml up --build -d
	@echo "Grafana: http://localhost:3001 (admin/admin)"

infra: .env      ## Start only infrastructure, to run services from your IDE
	docker compose up -d kafka kafka-ui postgres mongo redis elasticsearch mailpit jaeger

down:            ## Stop containers
	docker compose -f docker-compose.yml -f docker-compose.observability.yml down

clean:           ## Stop containers and delete all data volumes
	docker compose -f docker-compose.yml -f docker-compose.observability.yml down -v

build:           ## Compile all Java modules
	mvn -B -DskipTests package

test:            ## All tests, including Testcontainers (needs Docker)
	mvn -B verify

test-unit:       ## Unit tests only (no Docker)
	mvn -B test -Dtest='!*IntegrationTest,!OversellPreventionTest' -Dsurefire.failIfNoSpecifiedTests=false

web:             ## Run the frontend in dev mode
	cd apps/web && npm install && npm run dev

smoke:           ## End-to-end smoke test against the running stack
	./tests/e2e/smoke.sh

load:            ## k6 flash-sale load test
	k6 run tests/load/checkout.k6.js

logs:            ## Follow logs of the saga participants
	docker compose logs -f order-service inventory-service payment-service

kafka-topics:    ## List Kafka topics
	docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

SERVICES := api-gateway auth-service catalog-service cart-service order-service inventory-service payment-service shipping-service notification-service search-service

k8s-images:      ## Build all images and load them into a kind cluster
	for s in $(SERVICES); do docker build -f docker/service.Dockerfile --build-arg SERVICE=$$s -t ecommerce/$$s:latest . && kind load docker-image ecommerce/$$s:latest; done
	docker build --build-arg NEXT_PUBLIC_API_URL=http://api.shop.localhost -t ecommerce/web:latest apps/web && kind load docker-image ecommerce/web:latest

k8s-deploy:      ## Apply the Kubernetes manifests
	kubectl apply -k infra/k8s/base
