import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from .config import settings

# Use the DATABASE_URL from settings; defaults to a SQLite file in the project root.
engine = create_engine(settings.DATABASE_URL, connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

import asyncio

def init_db():
    """Create all tables if they do not exist.
    Called on FastAPI startup.
    """
    Base.metadata.create_all(bind=engine)
