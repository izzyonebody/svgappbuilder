from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

from .routes.generate import router as generate_router
from .routes.search import router as search_router

app = FastAPI(title="SVG App Builder Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(generate_router, prefix="/api/generate")
app.include_router(search_router, prefix="/api/search")

@app.get("/")
def read_root():
    return {"status": "ok"}
