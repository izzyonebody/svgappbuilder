from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from ..ollama_client import generate_with_ollama

router = APIRouter()

class GenRequest(BaseModel):
    model: str
    prompt: str
    max_tokens: Optional[int] = 512
    temperature: Optional[float] = 0.2

@router.post("/")
def generate(req: GenRequest):
    try:
        out = generate_with_ollama(req.model, req.prompt, max_tokens=req.max_tokens, temperature=req.temperature)
        return out
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
