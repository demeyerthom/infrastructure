# Ollama with qwen3.5:27b model pre-installed
FROM ollama/ollama:0.17.7

# Expose the Ollama API port
EXPOSE 11434

# Pre-pull the qwen3.5:27b model during build
# We need to start ollama serve in the background, pull the model, then stop it
RUN ollama serve & \
    sleep 5 && \
    ollama pull qwen3.5:27b && \
    pkill ollama

# Default command to start ollama serve
CMD ["serve"]

