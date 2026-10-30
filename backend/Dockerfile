FROM node:20-alpine

WORKDIR /app

# Cache bust: 2025-08-18-11:58
# Copy package files
COPY package*.json ./

# Fonts for server-drawn images (shared quote cards: services/quoteCard.js)
RUN apk add --no-cache fontconfig font-dejavu

# Install dependencies
RUN npm ci --production

# Copy application files
COPY . .

# Our own fonts (Gelasio: the App Clip generic card's serif headline)
RUN mkdir -p /usr/share/fonts/favcircles && cp assets/fonts/*.ttf /usr/share/fonts/favcircles/ && fc-cache -f

# Cloud Run sets PORT env variable dynamically
# Don't hardcode the port - let Cloud Run handle it
# EXPOSE directive removed - Cloud Run handles port exposure

# Start the application
CMD ["node", "server.js"]