curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hf.co/google/gemma-3-4b-it-qat-q4_0-gguf",
    "stream": false,
    "keep_alive": -1,
    "prompt": "кто круче - Зенит или Спартак?",
    "options": {
      "temperature": 0.3,
      "num_ctx": 16384,
      "num_predict": 1024
    }
  }'
