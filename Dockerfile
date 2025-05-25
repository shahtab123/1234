# Stage 1: Base image with common dependencies
FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04 AS base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    libgl1 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli
RUN pip install comfy-cli

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --version 0.3.30 --cuda-version 12.6 --nvidia

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install runpod
RUN pip install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Restore the snapshot to install custom nodes
RUN /restore_snapshot.sh

# Start container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base as downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE=flux1-dev

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories
RUN mkdir -p models/checkpoints models/vae models/unet models/clip models/loras

# Download flux1-dev model and its components
RUN wget --header="Authorization: Bearer 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" -O models/unet/flux1-dev.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors && \
    wget -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
    wget -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
    wget --header="Authorization: Bearer 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" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors && \
    wget -O models/loras/Ivory_Stranger_Flux_LoRA_v1.0.safetensors https://huggingface.co/shahtab/IvoryStranger/resolve/main/Ivory%20Stranger%20-%20Flux%20LoRA%20%20_v1.0.safetensors && \
    wget -O models/loras/flux_topless_v1.safetensors https://huggingface.co/shahtab/FluxTopless/resolve/main/flux_topless_v1.safetensors && \
    wget -O models/loras/aidmaNSFWunlock-FLUX-V0.2.safetensors https://huggingface.co/shahtab/FLUXNSFWunlock/resolve/main/aidmaNSFWunlock-FLUX-V0.2.safetensors && \
    wget -O models/loras/FC_Flux_Perfect_Busts.safetensors https://huggingface.co/shahtab/FluxPonyPerfectFull/resolve/main/FC%20Flux%20Perfect%20Busts.safetensors && \
    wget -O models/loras/flux_uncensored_nsfw_v2.safetensors https://huggingface.co/imagepipeline/flux_uncensored_nsfw_v2/resolve/main/lora.safetensors
    
# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start container
CMD ["/start.sh"]
