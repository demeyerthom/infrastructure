# Ollama with gpt-oss:20b and glm-ocr:latest models pre-installed
FROM ollama/ollama:0.17.7

# Expose the Ollama API port
EXPOSE 11434

# Pre-pull the gpt-oss:20b and glm-ocr:latest models during build
# We need to start ollama serve in the background, pull the models, then stop it
RUN ollama serve & \
    sleep 5 && \
    ollama pull gpt-oss:20b && \
    ollama pull glm-ocr:latest && \
    pkill ollama

# Default command to start ollama serve
CMD ["serve"]

