#!/bin/bash
# Setup script for vllm-on-dynamo profiling recipes:
#   1. Ensure nsys CLI is on PATH (runtime images strip it).
#   2. Ensure msgpack is importable (some dynamo install paths need it
#      and the upstream vllm-openai image doesn't bundle it; matches
#      InferenceMAX's vllm-container-deps.sh).
#
# Why combined: srt-slurm only honors a single setup_script per recipe.
#
# Strategy for nsys: rely on the container's pre-configured NVIDIA apt
# repo (cuda-base images ship /etc/apt/sources.list.d/cuda*.list).
# `apt-get install nsight-systems-cli` resolves to the right
# architecture (aarch64 on lyris/ptyche, x86_64 on bia/eos)
# automatically. If the cuda repo isn't configured, falls back to
# installing cuda-keyring first.

set -e

# --- msgpack -------------------------------------------------------
if ! python3 -c "import msgpack" >/dev/null 2>&1; then
    echo "[setup] pip install msgpack"
    pip install --no-cache-dir msgpack
else
    echo "[setup] msgpack already importable; skipping"
fi

# --- nsys ----------------------------------------------------------

if command -v nsys >/dev/null 2>&1; then
    echo "[install-nsys] already on PATH at $(command -v nsys); skipping"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
echo "[install-nsys] container arch: ${ARCH}"

apt_install_nsys() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nsight-systems-cli
}

echo "[install-nsys] apt-get update"
apt-get update -qq || true   # transient mirror flakes shouldn't kill the install

if ! apt_install_nsys 2>&1; then
    echo "[install-nsys] direct install failed; setting up cuda-keyring + retrying"
    # Ubuntu 24.04 keyring path; adjust if the container uses a different distro
    DISTRO="ubuntu2404"
    KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${ARCH/amd64/x86_64}/cuda-keyring_1.1-1_all.deb"
    echo "[install-nsys] downloading: ${KEYRING_URL}"
    curl -fsSL "$KEYRING_URL" -o /tmp/cuda-keyring.deb
    DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/cuda-keyring.deb
    apt-get update -qq
    apt_install_nsys
fi

if ! command -v nsys >/dev/null 2>&1; then
    echo "[install-nsys] ERROR: nsys still not on PATH after install" >&2
    exit 1
fi

echo "[install-nsys] $(nsys --version 2>&1 | head -1)"
