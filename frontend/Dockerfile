# Use Node.js
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package.json package-lock.json ./

# Install dependencies (including serve for production)
RUN npm ci && npm install -g serve

# Copy source code
COPY . .

# Accept build-time environment variables
ARG REACT_APP_API_BASE_HOST
ENV REACT_APP_API_BASE_HOST=$REACT_APP_API_BASE_HOST

ARG REACT_APP_API_BASE_PORT
ENV REACT_APP_API_BASE_PORT=$REACT_APP_API_BASE_PORT

# Build the application
RUN npm run build

EXPOSE 3000

# Serve the built app using serve
CMD ["serve", "-s", "build", "-l", "3000"]
