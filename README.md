Local SVG App Builder (Starter Repo)
====================================

Overview
--------
Electron + React front-end with Konva-based SVG canvas, Python FastAPI backend that calls Ollama locally for LLM/code generation, Qdrant vector DB in Docker for RAG/templates, and scripts to pull recommended models into Ollama on first run.

Files of interest:
- bootstrapper_first_run.ps1  : First-run helper that starts Docker services, pulls models (if confirmed), installs Python deps, seeds Qdrant, and can create Desktop / Start Menu shortcuts.
- start_dev.ps1              : Helper that launches backend and frontend dev servers in new PowerShell windows.
- backend/scripts/install_models.bat / .sh : model pull helpers for Ollama.

To run the bootstrapper (after creating the repo):
powershell -ExecutionPolicy Bypass -File .\bootstrapper_first_run.ps1

