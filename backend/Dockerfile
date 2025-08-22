FROM node:18-alpine

WORKDIR /app

# Cache bust: 2025-08-18-11:58
# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --production

# Copy application files
COPY . .

# Cloud Run sets PORT env variable dynamically
# Don't hardcode the port - let Cloud Run handle it
# EXPOSE directive removed - Cloud Run handles port exposure

# Start the application
CMD ["node", "server.js"]