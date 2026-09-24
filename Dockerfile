# syntax=docker/dockerfile:1
FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Build-time arguments to match host user UID/GID (defaulting to 1000 for standard Linux Mint/Ubuntu host)
ARG USER_NAME=minty
ARG USER_UID=1000
ARG USER_GID=1000

# 1. Install system utilities, build toolchains, Python, Node.js, and common developer dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    file \
    git \
    gnupg \
    jq \
    less \
    nano \
    nodejs \
    npm \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    sudo \
    tar \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

# 2. Configure non-root user matching the host UID/GID
# Ubuntu 24.04 noble base image creates a default 'ubuntu' user (UID 1000).
# Remove 'ubuntu' if present to avoid UID collision, then create 'minty' with the host UID/GID.
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi && \
    if getent group ${USER_GID} >/dev/null 2>&1; then \
        groupmod -n ${USER_NAME} $(getent group ${USER_GID} | cut -d: -f1); \
    else \
        groupadd --gid ${USER_GID} ${USER_NAME}; \
    fi && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 3. Configure Git globally to avoid 'dubious ownership' errors across host volume mounts
RUN git config --system --add safe.directory '*'

# 4. Prepare required directories and permissions
RUN mkdir -p /home/${USER_NAME}/workspace \
             /home/${USER_NAME}/.gemini \
             /home/${USER_NAME}/.config \
             /home/${USER_NAME}/.local/bin && \
    chown -R ${USER_UID}:${USER_GID} /home/${USER_NAME}

# 5. Switch to non-root user to install agy in user space
USER ${USER_NAME}
WORKDIR /home/${USER_NAME}/workspace

# 6. Install Google Antigravity CLI via official install script
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# 7. Environment configuration
ENV HOME="/home/${USER_NAME}"
ENV PATH="/home/${USER_NAME}/.local/bin:${PATH}"
ENV TERM="xterm-256color"

# 8. Copy and set entrypoint
USER root
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
USER ${USER_NAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["agy", "--dangerously-skip-permissions"]
