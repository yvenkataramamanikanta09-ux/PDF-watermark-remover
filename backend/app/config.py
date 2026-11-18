import os
from pydantic import BaseSettings, Field

class Settings(BaseSettings):
    # Database URL e.g. postgresql+psycopg2://user:password@db:5432/pdfwm
    DATABASE_URL: str = Field(default="sqlite+aiosqlite:///./test.db", env="DATABASE_URL")
    # Temporary directory for uploaded PDFs and processed outputs
    TMP_DIR: str = Field(default="tmp", env="TMP_DIR")
    # Maximum upload size in bytes (e.g., 20 MB)
    MAX_UPLOAD_SIZE: int = Field(default=20 * 1024 * 1024, env="MAX_UPLOAD_SIZE")
    # Maximum number of pages allowed
    MAX_PAGES: int = Field(default=500, env="MAX_PAGES")
    # Job expiration in seconds (e.g., 1 hour)
    JOB_TTL_SECONDS: int = Field(default=3600, env="JOB_TTL_SECONDS")

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
