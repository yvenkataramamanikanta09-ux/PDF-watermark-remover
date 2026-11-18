FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Install system dependencies (if any needed for PyMuPDF, but we use pre-built wheels)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the backend source code
COPY backend/ ./

# Copy the processing engine code
COPY processing_engine/ ./processing_engine/

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose the FastAPI port
EXPOSE 8000

# Command to run the API with migrations
CMD ["/entrypoint.sh"]
