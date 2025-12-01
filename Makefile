.PHONY: help install test lint format clean console update cron dev-up dev-down dev-logs

# Default target
help:
	@echo "KeeneticMaster Development Commands"
	@echo ""
	@echo "Backend Commands:"
	@echo "  install    Install dependencies"
	@echo "  test       Run test suite"
	@echo "  lint       Run RuboCop linter"
	@echo "  format     Auto-fix code formatting issues"
	@echo "  clean      Clean temporary files and logs"
	@echo "  console    Start interactive console"
	@echo "  update     Update specific domain groups"
	@echo "  cron       Start cron job for continuous updates"
	@echo "  setup      Initial project setup"
	@echo ""
	@echo "Development Environment (with hot reload):"
	@echo "  dev-up     Start development environment with hot reloading"
	@echo "  dev-down   Stop development environment"
	@echo "  dev-logs   Follow development logs"
	@echo "  dev-shell  Open shell in frontend container"
	@echo ""
	@echo "Production Environment:"
	@echo "  up         Start production environment"
	@echo "  down       Stop production environment"
	@echo "  logs       Follow production logs"
	@echo ""

# Install dependencies
install:
	bundle install

# Run test suite
test:
	bundle exec rspec

# Run test suite with coverage
test-coverage:
	COVERAGE=true bundle exec rspec

# Run RuboCop linter
lint:
	bundle exec rubocop

# Auto-fix formatting issues
format:
	bundle exec rubocop -A

# Clean temporary files and logs
clean:
	rm -rf tmp/logs/*
	rm -rf tmp/request-dumps/*
	rm -rf spec/examples.txt

# Start interactive console
console:
	bundle exec pry -r ./config/application

# Update specific domain groups (usage: make update GROUPS="github youtube")
update:
	@if [ -z "$(GROUPS)" ]; then \
		echo "Usage: make update GROUPS=\"group1 group2\""; \
		exit 1; \
	fi
	bundle exec ruby cmd/update_group.rb $(GROUPS)

# Update all domain groups
update-all:
	bundle exec ruby cmd/update_group.rb

# Initial project setup
setup: install
	@echo "Setting up KeeneticMaster..."
	@if [ ! -f .env ]; then \
		echo "Creating .env file from example..."; \
		cp .env.example .env 2>/dev/null || echo "Please create .env file manually"; \
	fi
	@if [ ! -f config/domains.yml ]; then \
		echo "Creating domains.yml from example..."; \
		cp config/domains.yml.example config/domains.yml 2>/dev/null || echo "Please create config/domains.yml manually"; \
	fi
	@mkdir -p tmp/logs tmp/request-dumps config
	@echo "Setup complete! Please edit .env and config/domains.yml with your settings."

# Run all checks (tests and linting)
check: test lint

# Development workflow
dev: clean install test lint

# Production deployment preparation
deploy-check: clean install test lint
	@echo "All checks passed! Ready for deployment."

# Development environment with hot reloading
dev-up:
	@echo "Starting development environment with hot reloading..."
	@echo "Frontend will be available at http://localhost:3200 with hot reload enabled"
	@echo "Backend API will be available at http://localhost:3201"
	@echo ""
	BACKEND_HOST=localhost BACKEND_PORT=3201 FRONTEND_PORT=3200 docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d
	@echo ""
	@echo "Development environment started!"
	@echo "- Frontend: http://localhost:3200 (hot reload enabled)"
	@echo "- Backend:  http://localhost:3201"
	@echo ""
	@echo "Use 'make dev-logs' to follow logs or 'make dev-down' to stop"

dev-down:
	@echo "Stopping development environment..."
	docker compose -f docker-compose.yml -f docker-compose.dev.yml down

dev-logs:
	@echo "Following development logs... (Ctrl+C to exit)"
	docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f

dev-shell:
	@echo "Opening shell in frontend development container..."
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec frontend sh

# Production environment commands
up:
	@echo "Starting production environment..."
	docker compose up --build -d

down:
	@echo "Stopping production environment..."
	docker compose down

logs:
	@echo "Following production logs... (Ctrl+C to exit)"
	docker compose logs -f

# Local development (without Docker)
dev-local:
	@echo "Starting local development..."
	@echo "Make sure backend is running on port 3201"
	@echo "Frontend will start on port 3000 with hot reload"
	cd frontend && npm run start:dev
