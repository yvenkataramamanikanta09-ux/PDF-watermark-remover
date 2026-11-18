#!/bin/sh
set -e
# Run database initialization (create tables) before starting the API
python -c "from backend.app.database import init_db; init_db()"
# Start FastAPI with uvicorn
exec uvicorn app.main:app --host 0.0.0.0 --port 8000