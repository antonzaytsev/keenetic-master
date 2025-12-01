# KeeneticMaster Frontend Setup

This project has been updated to use a separate React frontend with a Ruby API backend.

## Architecture

- **Backend**: Ruby/Sinatra API-only server (port 4567)
- **Frontend**: React TypeScript application (port 3000)
- **Database**: PostgreSQL (port 5433)

## Running with Docker Compose

The easiest way to run both services:

```bash
# Build and start all services
docker-compose up --build

# Or run in background
docker-compose up -d --build
```

This will start:
- PostgreSQL database on port 5433
- Backend API on port 4567
- Frontend React app on port 3000
- Background services (dns-logs)

Access the application at http://localhost:3000

## Running for Development

### Backend API

```bash
# Install dependencies
bundle install

# Start the API server
ruby cmd/web_server.rb
```

The API will be available at http://localhost:4567

### Frontend

```bash
# Navigate to frontend directory
cd frontend

# Install dependencies
npm install

# Start the development server
npm start
```

The frontend will be available at http://localhost:3000

## API Endpoints

The backend provides the following API endpoints:

- `GET /` - API information
- `GET /api/domain-groups` - List all domain groups with statistics
- `GET /api/domains/:name` - Get specific domain group
- `POST /api/domains/:name` - Create/update domain group
- `DELETE /api/domains/:name` - Delete domain group
- `GET /api/sync-stats` - Get sync statistics and logs
- `GET /api/sync-logs` - Get paginated sync logs
- `GET /health` - Health check

## Environment Variables

### Backend (.env)
```
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=keenetic_master
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
```

### Frontend
```
REACT_APP_API_BASE_URL=http://localhost:3200
```

## Features

The React frontend includes:

### Domain Groups Page (/)
- View all domain groups with statistics
- Search and filter functionality
- Domain count and route statistics
- Sync status indicators
- Delete domain groups

### Sync Status Page (/sync-status)
- Sync statistics dashboard
- Recent failures highlighting
- Comprehensive sync log table with filtering
- Auto-refresh functionality

## Key Changes from SSR Version

1. **Separated Concerns**: Frontend and backend are now separate services
2. **API-First**: Backend provides JSON APIs instead of rendering templates
3. **React Components**: All UI components are now React-based
4. **Real-time Updates**: Auto-refresh functionality for data freshness
5. **Responsive Design**: Bootstrap-based responsive UI
6. **Type Safety**: Full TypeScript implementation
7. **Docker Support**: Both services containerized

## Development Notes

- The backend includes CORS support for frontend development
- All original functionality has been preserved
- Search and filtering work the same as before
- Auto-refresh intervals: 30s for domain groups and IP addresses, 15s for sync status
