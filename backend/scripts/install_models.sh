#!/usr/bin/env bash
ASSISTANT_MODEL="mistral-7b-instruct"
CODE_MODEL="codellama-7b-instruct"

echo "Pulling assistant model: ${ASSISTANT_MODEL}"
ollama pull "${ASSISTANT_MODEL}"
echo "Pulling code model: ${CODE_MODEL}"
ollama pull "${CODE_MODEL}"

echo "Done. If a model name fails, run 'ollama list' and adjust the script."
