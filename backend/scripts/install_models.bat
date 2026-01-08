@echo off
REM Install recommended models into Ollama via ollama pull
REM Adjust model names if your Ollama registry uses different names.

REM Models (defaults)
set ASSISTANT_MODEL=mistral-7b-instruct
set CODE_MODEL=codellama-7b-instruct
set EMBED_MODEL=all-MiniLM-L6-v2

echo Pulling assistant model: %ASSISTANT_MODEL%
ollama pull %ASSISTANT_MODEL%
echo Pulling code model: %CODE_MODEL%
ollama pull %CODE_MODEL%

echo NOTE: Embeddings model is a sentence-transformers model installed via pip.
echo If you need a local embeddings server, install appropriate model or use sentence-transformers as in the backend.

echo Done pulling models. If any model name fails, run 'ollama list' and update these names.
pause
