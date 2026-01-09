import os
from sentence_transformers import SentenceTransformer
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance

QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
client = QdrantClient(url=QDRANT_URL)

model = SentenceTransformer("all-MiniLM-L6-v2")

def recreate_templates_collection():
    client.recreate_collection(collection_name="templates", vector_size=384, distance=Distance.COSINE)
    print("Recreated collection \"templates\".")

def upsert_template(id, text, payload):
    vec = model.encode(text).tolist()
    client.upsert(collection_name="templates", points=[{"id": id, "vector": vec, "payload": payload}])
    print("Inserted:", id)

if __name__ == "__main__":
    recreate_templates_collection()
    upsert_template("landing-1", "Landing page with hero, CTA button, and three feature cards", {"type":"template","name":"Landing Page 1"})
    upsert_template("dashboard-1", "Admin dashboard with sidebar, statistics cards, and a table", {"type":"template","name":"Admin Dashboard 1"})
    print("Seeded templates.")
