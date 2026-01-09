from fastapi import APIRouter
from pydantic import BaseModel
from ..qdrant_client import QdrantClient
from ..embeddings import embed

router = APIRouter()

class SearchRequest(BaseModel):
    query: str
    top_k: int = 4

@router.post("/")
def search(req: SearchRequest):
    client = QdrantClient(url="http://localhost:6333")
    vec = embed(req.query)
    hits = client.search(collection_name="templates", query_vector=vec, limit=req.top_k)
    results = []
    for h in hits:
        results.append({"id": h.id, "payload": h.payload, "score": h.score})
    return {"results": results}
