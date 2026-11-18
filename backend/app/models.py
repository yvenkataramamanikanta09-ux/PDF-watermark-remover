import enum
from datetime import datetime, timedelta
from sqlalchemy import Column, String, Integer, Enum, DateTime, Text
from .database import Base

class JobStatus(str, enum.Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    SUCCESS = "SUCCESS"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"

class Job(Base):
    __tablename__ = "jobs"

    id = Column(String, primary_key=True, index=True)  # UUID string
    filename = Column(String, nullable=False)
    size = Column(Integer, nullable=False)
    status = Column(Enum(JobStatus), default=JobStatus.PENDING, nullable=False)
    detail = Column(Text, nullable=True)  # optional error or info message
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

# Helper CRUD functions

def create_job(db_session, *, job_id: str, filename: str, size: int, ttl_seconds: int):
    expires = datetime.utcnow() + timedelta(seconds=ttl_seconds)
    job = Job(
        id=job_id,
        filename=filename,
        size=size,
        status=JobStatus.PENDING,
        expires_at=expires,
    )
    db_session.add(job)
    db_session.commit()
    db_session.refresh(job)
    return job

def get_job(db_session, job_id: str):
    return db_session.query(Job).filter(Job.id == job_id).first()

def update_job_status(db_session, job_id: str, new_status: JobStatus, detail: str | None = None):
    job = get_job(db_session, job_id)
    if not job:
        return None
    job.status = new_status
    if detail is not None:
        job.detail = detail
    db_session.commit()
    db_session.refresh(job)
    return job
