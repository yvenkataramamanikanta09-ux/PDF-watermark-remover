"""FastAPI entry point for PDF Watermark Remover backend.
It provides endpoints for:
* uploading a PDF (temporary storage)
* inspecting a PDF for removable watermark objects
* creating a removal job and polling its status
* downloading the processed PDF
"""

import os
import uuid
import shutil
from fastapi import FastAPI, UploadFile, File, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse
from pydantic import BaseModel
from pathlib import Path

from . import config
from .database import init_db, SessionLocal
from .models import Job, JobStatus, create_job, get_job, update_job_status
from .processing.engine import inspect as engine_inspect, run as engine_run

app = FastAPI(title="PDF Watermark Remover API")

# Ensure temporary directory exists
Path(config.settings.TMP_DIR).mkdir(parents=True, exist_ok=True)

@app.on_event("startup")
def startup_event():
    init_db()

class UploadResponse(BaseModel):
    job_id: str
    filename: str
    size: int

@app.post("/upload", response_model=UploadResponse)
async def upload_pdf(file: UploadFile = File(...)):
    # Basic validation
    if not file.filename.lower().endswith('.pdf'):
        raise HTTPException(status_code=400, detail="Only PDF files are accepted")
    contents = await file.read()
    if len(contents) > config.settings.MAX_UPLOAD_SIZE:
        raise HTTPException(status_code=413, detail="File too large")
    # Save to temporary location
    job_id = str(uuid.uuid4())
    job_dir = Path(config.settings.TMP_DIR) / job_id
    job_dir.mkdir(parents=True, exist_ok=True)
    src_path = job_dir / "original.pdf"
    with open(src_path, "wb") as f:
        f.write(contents)
    # Register job in DB
    db = SessionLocal()
    db_job = create_job(db, job_id=job_id, filename=file.filename, size=len(contents), ttl_seconds=config.settings.JOB_TTL_SECONDS)
    db.close()
    return UploadResponse(job_id=job_id, filename=file.filename, size=len(contents))

class InspectResponse(BaseModel):
    can_remove: bool
    reason: str | None = None
    page_count: int
    rotation: dict[int, int]

@app.get("/inspect/{job_id}", response_model=InspectResponse)
async def inspect_pdf(job_id: str):
    db = SessionLocal()
    job = get_job(db, job_id)
    db.close()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    pdf_path = Path(config.settings.TMP_DIR) / job_id / "original.pdf"
    if not pdf_path.is_file():
        raise HTTPException(status_code=404, detail="PDF file missing")
    can_remove, reason, page_count, rotation = engine_inspect(pdf_path)
    return InspectResponse(can_remove=can_remove, reason=None if can_remove else reason, page_count=page_count, rotation=rotation)

class ProcessResponse(BaseModel):
    job_id: str
    status: JobStatus

@app.post("/process/{job_id}", response_model=ProcessResponse)
async def start_processing(job_id: str, background_tasks: BackgroundTasks):
    db = SessionLocal()
    job = get_job(db, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.status != JobStatus.PENDING:
        raise HTTPException(status_code=400, detail="Job already started or finished")
    background_tasks.add_task(engine_run, job_id)
    update_job_status(db, job_id, JobStatus.RUNNING)
    db.close()
    return ProcessResponse(job_id=job_id, status=JobStatus.RUNNING)

@app.get("/status/{job_id}")
async def job_status(job_id: str):
    db = SessionLocal()
    job = get_job(db, job_id)
    db.close()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return {"job_id": job_id, "status": job.status, "detail": job.detail}

@app.get("/result/{job_id}")
async def get_result(job_id: str):
    db = SessionLocal()
    job = get_job(db, job_id)
    db.close()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.status != JobStatus.SUCCESS:
        raise HTTPException(status_code=400, detail="Result not ready")
    result_path = Path(config.settings.TMP_DIR) / job_id / "processed.pdf"
    if not result_path.is_file():
        raise HTTPException(status_code=404, detail="Processed file missing")
    return FileResponse(str(result_path), media_type="application/pdf", filename="processed.pdf")

@app.get("/health")
async def health():
    return {"status": "ok"}

