# Ollama with Gemma3 model pre-installed
FROM ollama/ollama:0.15.1

# Expose the Ollama API port
EXPOSE 11434

# Pre-pull the gemma3 model during build
# We need to start ollama serve in the background, pull the model, then stop it
RUN ollama serve & \
    sleep 5 && \
    ollama pull gemma3 && \
    pkill ollama

# Default command to start ollama serve
CMD ["serve"]

