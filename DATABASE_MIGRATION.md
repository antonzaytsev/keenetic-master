# Database Migration Guide

This guide explains how to migrate from YAML-based storage to PostgreSQL database for Keenetic Master.

## Overview

The application now uses PostgreSQL to store:
- Domain groups and their settings
- Individual domains (regular and DNS monitoring)
- Generated routes and their sync status
- Sync operation logs

## Migration Steps

### 1. Start PostgreSQL

```bash
# Using Docker Compose (recommended)
docker-compose up postgres -d

# Or start all services
docker-compose up -d
```

### 2. Run Database Setup

```bash
# Initialize database tables
ruby cmd/database_manager.rb setup

# Check status
ruby cmd/database_manager.rb status
```

### 3. Migrate YAML Data

```bash
# Migrate from default domains file
ruby cmd/database_manager.rb migrate

# Or specify custom file
ruby cmd/database_manager.rb migrate -f config/domains.yml

# Verify migration
ruby cmd/database_manager.rb verify
```

### 4. Test Database Sync

```bash
# Sync database with router
ruby cmd/database_manager.rb sync
```

## Environment Variables

Add these to your `.env` file:

```bash
# Database configuration
DATABASE_HOST=localhost
DATABASE_PORT=5433
DATABASE_NAME=keenetic_master
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
```

For Docker Compose, these are already configured.

## Key Changes

### Web Interface
- No changes to the UI - it works the same way
- Data is now stored in PostgreSQL instead of YAML
- All API endpoints updated to use database

### Route Management
- Routes are now generated and stored in database first
- Sync to router happens in a separate step
- Better tracking of sync status and failures

### Command Line Tools
- `cmd/database_manager.rb` - Database management
- `cmd/update_group.rb` - Still works, now uses database

## Architecture

```
UI → Database → Router
     ↑       ↓
   Storage  Sync Layer
```

1. **UI Updates**: Web interface saves domain groups to database
2. **Route Generation**: Database generates routes from domains
3. **Router Sync**: Sync layer applies routes to Keenetic router
4. **Status Tracking**: Database tracks sync status and logs

## Benefits

- **Persistence**: Data survives container restarts
- **Atomicity**: Database transactions ensure consistency
- **Tracking**: Full sync history and error logging
- **Scalability**: Better performance with larger datasets
- **Rollback**: Easy to rollback changes if needed

## Rollback

If you need to revert to YAML:

```bash
# Clear database
ruby cmd/database_manager.rb rollback

# Your original domains.yml.backup file is preserved
```

## Troubleshooting

### Connection Issues
```bash
# Check PostgreSQL status
docker-compose ps postgres

# Check database connection
ruby cmd/database_manager.rb status
```

### Migration Issues
```bash
# Verify migration integrity
ruby cmd/database_manager.rb verify

# Check logs
docker-compose logs app
```

### Sync Issues
```bash
# Check recent failures
ruby -e "require_relative 'lib/database'; require_relative 'lib/models'; Database.setup!; puts SyncLog.recent_failures.all"

# Force full sync
ruby cmd/database_manager.rb sync
```

## Development

### Database Schema
- `domain_groups` - Domain group settings
- `domains` - Individual domains
- `routes` - Generated routes with sync status
- `sync_log` - Operation history

### Adding New Features
- Use Sequel models in `lib/models.rb`
- Database connection via `Database.connection`
- Sync operations via `DatabaseRouterSync`
