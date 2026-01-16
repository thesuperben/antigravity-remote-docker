# =============================================================================
# Antigravity Remote Docker
# A GPU-accelerated container for running Google Antigravity remotely via noVNC
# =============================================================================

FROM nvidia/cuda:12.3.1-runtime-ubuntu22.04

LABEL maintainer="raphl"
LABEL description="Google Antigravity with noVNC remote access and GPU support"

# =============================================================================
# Environment Configuration
# =============================================================================
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    # Display settings
    DISPLAY=:1 \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    DISPLAY_DEPTH=24 \
    # VNC settings
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    SSH_PORT=22 \
    VNC_PASSWORD=antigravity \
    # User settings
    USER=antigravity \
    UID=1000 \
    GID=1000 \
    HOME=/home/antigravity \
    # Antigravity settings
    ANTIGRAVITY_AUTO_UPDATE=true

# =============================================================================
# System Dependencies & Development Tools
# =============================================================================
# Change this date to force a cache rebuild when new package versions are out
ENV REFRESHED_AT=2026-01-16

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    ca-certificates \
    curl \
    wget \
    gnupg \
    sudo \
    locales \
    tzdata \
    dbus-x11 \
    # Networking & SSH
    openssh-server \
    net-tools \
    # X11 and desktop
    xvfb \
    x11vnc \
    tigervnc-standalone-server \
    tigervnc-common \
    tigervnc-tools \
    xfce4 \
    xfce4-goodies \
    xfce4-terminal \
    # Fonts and theming
    fonts-dejavu \
    fonts-liberation \
    fonts-noto \
    gtk2-engines-pixbuf \
    adwaita-icon-theme \
    # Audio & Clipboard
    pulseaudio \
    xclip \
    xsel \
    # Process management
    supervisor \
    unattended-upgrades \
    apt-transport-https \
    # Utilities
    nano \
    vim \
    htop \
    procps \
    wmctrl \
    xdotool \
    # --- Development Tools ---
    git \
    build-essential \
    docker.io \
    nodejs \
    npm \
    python3 \
    python3-pip \
    python3-venv \
    python3-numpy \
    python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# SSH Configuration
# =============================================================================
RUN mkdir /var/run/sshd \
    && echo 'root:antigravity' | chpasswd \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    # Fix for some SSH connection issues in containers
    && sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

# =============================================================================
# Install Google Chrome
# =============================================================================
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Locale Configuration
# =============================================================================
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# =============================================================================
# Install noVNC and websockify
# =============================================================================
RUN mkdir -p /opt/novnc \
    && curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz | tar -xz -C /opt/novnc --strip-components=1 \
    && mkdir -p /opt/websockify \
    && curl -fsSL https://github.com/novnc/websockify/archive/refs/tags/v0.11.0.tar.gz | tar -xz -C /opt/websockify --strip-components=1 \
    && ln -sf /opt/websockify /opt/novnc/utils/websockify

# Custom index.html for auto-connect
RUN echo '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=vnc.html?autoconnect=true&resize=remote&lang=en"></head><body>Redirecting...</body></html>' > /opt/novnc/index.html

# =============================================================================
# Add Antigravity Repository and Install
# =============================================================================
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
    gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
    tee /etc/apt/sources.list.d/antigravity.list > /dev/null \
    && apt-get update \
    && apt-get install -y antigravity \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Create User & Configure Permissions
# =============================================================================
RUN groupadd -g ${GID} ${USER} \
    # Create the Docker group if it doesn't exist (handling potential GID conflicts)
    && groupadd -f docker \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USER} \
    && chmod 0440 /etc/sudoers.d/${USER} \
    # Add user to the Docker group so they can run 'docker ps'
    && usermod -aG docker ${USER} \
    # Set the user password for SSH access
    && echo "${USER}:antigravity" | chpasswd

# =============================================================================
# Configure VNC and Desktop
# =============================================================================
RUN mkdir -p /home/${USER}/.vnc /home/${USER}/.config /home/${USER}/.local/share/keyrings \
    && chown -R ${USER}:${USER} /home/${USER}

# =============================================================================
# Copy Configuration Files
# =============================================================================
# Note: Ensure you have added sshd setup to your supervisord.conf locally!
COPY --chown=${USER}:${USER} config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY --chown=${USER}:${USER} scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# =============================================================================
# Configure Auto-Updates for Antigravity
# =============================================================================
RUN echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades \
    && echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades \
    && echo 'Unattended-Upgrade::Allowed-Origins { "antigravity-auto-updater-dev:antigravity-debian"; };' > /etc/apt/apt.conf.d/50unattended-upgrades

# =============================================================================
# Exposed Ports
# =============================================================================
# VNC: 5901, noVNC: 6080, SSH: 22
EXPOSE ${VNC_PORT} ${NOVNC_PORT} ${SSH_PORT}

# =============================================================================
# Copy Configuration Defaults
# =============================================================================
RUN mkdir -p /opt/defaults
COPY config/xfce4-panel.xml /opt/defaults/xfce4-panel.xml

# =============================================================================
# Volumes
# =============================================================================
# Keyrings added to volumes for persistence of Google Login
VOLUME ["/home/${USER}/workspace", "/home/${USER}/.config", "/home/${USER}/.local/share/keyrings"]

# =============================================================================
# Health Check
# =============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${NOVNC_PORT}/ || exit 1

# =============================================================================
# Entrypoint
# =============================================================================
USER root
WORKDIR /home/${USER}

ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
CMD ["supervisord"]
