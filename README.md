# KeeneticMaster

A Ruby application for managing Keenetic router static routes for specific domain groups. Automatically resolves domains to IP addresses and updates router routing tables via VPN interfaces.

## Features

- **Domain Group Management**: Organize domains into groups with individual settings
- **Automatic DNS Resolution**: Resolve domains to IP addresses using configurable DNS servers
- **VPN Interface Support**: Route traffic through specified VPN interfaces (Wireguard, etc.)
- **GitHub Integration**: Special handling for GitHub IP ranges via API
- **Batch Operations**: Efficient batch updates with progress tracking
- **Flexible Configuration**: Environment-based configuration with validation
- **Robust Error Handling**: Comprehensive error handling and logging
- **Test Coverage**: Well-tested codebase with RSpec
- **Development Tools**: Code quality tools (RuboCop, tests, development utilities)
- **Hot Reloading**: Development environment with instant file change detection

## Quick Start

### Development Environment (Hot Reload)

For development with hot reloading, see [DEVELOPMENT.md](DEVELOPMENT.md) for the complete setup guide.

**Quick development setup:**
```bash
# 1. Prepare environment (installs dependencies)
docker compose up --build -d

# 2. In separate terminals, run:
docker compose exec backend ruby cmd/web_server.rb    # Backend API
docker compose exec frontend npm start                # Frontend (hot reload)

# 3. Access the application:
# Frontend: http://localhost:3000 (with hot reload)
# Backend API: http://localhost:3201
```

### Production Deployment

### Using Docker (Recommended)

1. Create a project directory and navigate to it:
   ```bash
   mkdir keenetic-master && cd keenetic-master
   ```

2. Download the docker-compose configuration:
   ```bash
   wget https://raw.githubusercontent.com/antonzaytsev/keenetic-master/refs/heads/main/docker-compose.yml
   ```

3. Create configuration files:
   ```bash
   # Download example domains file
   wget https://raw.githubusercontent.com/antonzaytsev/keenetic-master/refs/heads/main/config/domains.yml.example -O domains.yml
   
   # Download example environment file
   wget https://raw.githubusercontent.com/antonzaytsev/keenetic-master/refs/heads/main/.env.example -O .env
   ```

4. Edit configuration files with your settings:
   ```bash
   # Edit router credentials and settings
   vim .env
   
   # Edit domain groups
   vim domains.yml
   ```

5. Start the application:
   ```bash
   # Start all services (cron job, DNS monitoring, and web UI)
   docker compose up
   
   # Or start specific services
   docker compose up app          # Just the cron job
   docker compose up web          # Just the web UI
   docker compose up dns-logs     # Just DNS log monitoring
   ```
   
   The web UI will be available at `http://localhost:4567` (or your configured port).

### Local Development Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd keenetic-master
   ```

2. Install Ruby (recommended via [asdf](https://asdf-vm.com/)):
   ```bash
   asdf plugin add ruby
   asdf install ruby
   ```

3. Set up the project:
   ```bash
   make setup
   ```

4. Configure your environment:
   ```bash
   # Copy and edit configuration files
   cp config/domains.yml.example config/domains.yml
   cp .env.example .env
   
   # Edit with your router credentials and domain groups
   vim .env
   vim config/domains.yml
   ```

5. Install dependencies:
   ```bash
   make install
   ```

## Configuration

### Environment Variables (.env)

```bash
# Keenetic router credentials (required)
KEENETIC_LOGIN=admin
KEENETIC_PASSWORD=your_password
KEENETIC_HOST=192.168.1.1

# VPN interfaces (comma-separated for multiple)
KEENETIC_VPN_INTERFACES=Wireguard0,Finland

# Domains configuration
DOMAINS_FILE=./config/domains.yml
DOMAINS_MASK=32

# DNS settings
DNS_SERVERS=1.1.1.1,8.8.8.8

# Operational settings
MINIMIZE=false
DELETE_ROUTES=true
LOG_LEVEL=INFO

# Web UI settings
WEB_PORT=4567            # Port for the web server (default: 4567)
WEB_BIND=0.0.0.0         # Bind address (default: 0.0.0.0)
WEB_HOST_PORT=4567       # Host port mapping for Docker (default: 4567)

# DNS logs monitoring (optional)
DNS_LOGS_HOST_PATH=./tmp/dns.log
DNS_LOGS_CONTAINER_PATH=/app/logs/dns.log

# Optional overrides
GITHUB_META_URL=https://api.github.com/meta
COOKIE_FILE=config/cookie
REQUEST_DUMPS_DIR=tmp/request-dumps
```

### Domain Groups (config/domains.yml)

```yaml
# Simple domain group
youtube:
  - youtube.com
  - googlevideo.com
  - ytimg.com

# Advanced domain group with settings
github:
  settings:
    mask: "24"                    # Network mask for resolved IPs
    interfaces: "Wireguard0,VPN2" # Specific interfaces for this group
  domains:
    - github.com
    - api.github.com
    - raw.githubusercontent.com

# IP ranges and direct IPs
custom_services:
  - "192.168.100.0/24"  # CIDR notation
  - "10.0.0.1"          # Direct IP
  - example.com         # Domain name

# Special GitHub integration (uses GitHub Meta API)
github_meta:
  - hooks    # GitHub webhook IPs
  - web      # GitHub web IPs
  - api      # GitHub API IPs
  - git      # GitHub Git IPs

# DNS monitoring configuration
youtube:
  settings:
    mask: "32"
    interfaces: "Wireguard0"
  domains:
    - youtube.com
    - ytimg.com
  follow_dns:           # Domains monitored from DNS logs
    - googleapis.com    # Automatically add IPs when requested
    - googlevideo.com   # Dynamic routing based on actual usage
```

## Usage

### Web User Interface

The application includes a simple web interface for managing domain groups:

```bash
# Start the web server
ruby cmd/web_server.rb

# Or with custom port
WEB_PORT=8080 ruby cmd/web_server.rb
```

Then open your browser to `http://localhost:4567` (or your custom port).

#### Web UI Features

- **Dashboard**: View all domain groups with their configurations
- **Create/Edit Groups**: Add new domain groups or modify existing ones
- **Simple & Advanced Modes**: Support for both simple domain lists and advanced configurations with settings
- **DNS Monitoring Support**: Full support for `follow_dns` configuration to monitor domains from DNS logs
- **Bulk Operations**: Add multiple domains at once (regular domains and DNS monitoring)
- **Real-time Updates**: Changes are immediately written to the domains.yml file
- **Responsive Design**: Works well on desktop and mobile devices

#### Web UI Environment Variables

```bash
WEB_PORT=4567        # Port for the web server (default: 4567)
WEB_BIND=0.0.0.0     # Bind address (default: 0.0.0.0)
WEB_HOST_PORT=4567   # Host port mapping for Docker (default: 4567)
```

#### Docker Compose Usage

```bash
# Start all services
docker compose up

# Start only the web UI
docker compose up web

# Start web UI in background
docker compose up -d web

# View logs
docker compose logs web

# Stop services
docker compose down
```

### Command Line Interface

```bash
# Update all domain groups
ruby cmd/update_group.rb

# Update specific groups
ruby cmd/update_group.rb github youtube

# Start continuous monitoring (cron job)
ruby cmd/crontab.rb

# Show help
ruby cmd/update_group.rb --help
```

### Development Commands (Makefile)

```bash
# Show all available commands
make help

# Development setup
make setup              # Initial project setup
make install           # Install dependencies
make dev               # Full development workflow

# Code quality
make test              # Run test suite
make lint              # Run RuboCop linter
make format            # Auto-fix formatting
make check             # Run tests and linting

# Operations
make update GROUPS="github youtube"  # Update specific groups
make update-all                      # Update all groups
make cron                           # Start cron job
make console                        # Interactive console

# Utilities
make clean             # Clean temporary files
```

### Interactive Console

```bash
make console

# In console:
> KeeneticMaster::UpdateAllRoutes.call
> KeeneticMaster::Configuration.keenetic_credentials
> reload!  # Reload application code
```

## Architecture

### Core Components

- **BaseClass**: Foundation class with logging and error handling
- **Configuration**: Centralized configuration management with validation
- **Client**: HTTP client for Keenetic API communication
- **UpdateDomainRoutesMinimize**: Main domain-to-route processing logic
- **MutateRouteRequest**: Base class for route manipulation operations

### Key Features

- **Dry-Monads Integration**: Functional programming patterns for error handling
- **Comprehensive Logging**: Structured logging with configurable levels
- **DNS Resolution Caching**: Efficient DNS lookups with multiple resolver support
- **Route Deduplication**: Intelligent route comparison and deduplication
- **Progress Tracking**: Visual progress bars for long operations
- **Signal Handling**: Graceful shutdown for long-running processes

## Testing

Run the test suite:

```bash
# Run all tests
make test

# Run with coverage
make test-coverage

# Run specific test files
bundle exec rspec spec/keenetic_master/configuration_spec.rb
```

## Code Quality

The project includes comprehensive code quality tools:

- **RuboCop**: Ruby style guide enforcement
- **RSpec**: Behavior-driven testing framework
- **WebMock/VCR**: HTTP interaction testing
- **Factory Bot**: Test data generation

## Development

### Adding New Features

1. Create feature branch
2. Add tests first (TDD approach)
3. Implement feature
4. Run code quality checks: `make check`
5. Update documentation if needed

### Project Structure

```
keenetic-master/
├── lib/
│   ├── keenetic_master/          # Main application classes
│   ├── base_class.rb             # Foundation class
│   ├── constants.rb              # Application constants
│   └── keenetic_master.rb        # Main module
├── cmd/                          # Command-line scripts
├── config/                       # Configuration files
├── spec/                         # Test suite
├── tmp/                          # Temporary files and logs
├── Dockerfile                    # Docker configuration
├── docker-compose.yml            # Docker Compose setup
├── Makefile                      # Development commands
└── README.md                     # This file
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes following the coding standards
4. Run tests and linting (`make check`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is available as open source under the terms of the MIT License.

## Support

For issues, questions, or contributions, please use the GitHub issue tracker.
