from sentence_transformers import SentenceTransformer

_model = None

def get_model(name="all-MiniLM-L6-v2"):
    global _model
    if _model is None:
        _model = SentenceTransformer(name)
    return _model

def embed(text):
    model = get_model()
    return model.encode(text).tolist()
