import os
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance
from .embeddings import embed

QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
client = QdrantClient(url=QDRANT_URL)

def recreate_templates_collection():
    try:
        client.recreate_collection(collection_name="templates", vector_size=384, distance=Distance.COSINE)
    except Exception as e:
        print("Collection recreate error:", e)

def upsert_template(id, text, payload):
    vec = embed(text)
    client.upsert(collection_name="templates", points=[{"id": id, "vector": vec, "payload": payload}])

def search_templates(query, top_k=4):
    vec = embed(query)
    res = client.search(collection_name="templates", query_vector=vec, limit=top_k)
    return res
