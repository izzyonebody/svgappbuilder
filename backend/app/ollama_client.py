import os
import requests

OLLAMA_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api/generate")

def generate_with_ollama(model: str, prompt: str, max_tokens: int = 512, temperature: float = 0.2):
    payload = {
        "model": model,
        "prompt": prompt,
        "max_tokens": max_tokens,
        "temperature": temperature
    }
    resp = requests.post(OLLAMA_URL, json=payload, timeout=300)
    resp.raise_for_status()
    return resp.json()
