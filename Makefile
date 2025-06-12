.PHONY: help install test lint format clean console update cron

# Default target
help:
	@echo "KeeneticMaster Development Commands"
	@echo ""
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

# Start cron job for continuous updates
cron:
	bundle exec ruby cmd/crontab.rb

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