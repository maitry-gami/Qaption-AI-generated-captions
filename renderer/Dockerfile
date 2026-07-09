FROM node:22-bookworm-slim

# Install system dependencies for Chromium and FFmpeg
RUN apt-get update && apt-get install -y \
    chromium \
    ffmpeg \
    fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

# Specify Chromium path for Puppeteer/Remotion
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

WORKDIR /app

# Copy dependency configuration
COPY package*.json ./

# Install project dependencies
RUN npm install

# Copy application files
COPY tsconfig*.json ./
COPY vite.config.ts ./
COPY eslint.config.js ./
COPY server.js ./
COPY src ./src
COPY public ./public

# Expose the server port (will default to 8000 if not overridden)
EXPOSE 8000

# Start server
CMD ["npm", "start"]
