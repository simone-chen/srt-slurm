#!/bin/bash
# Setup script for vllm-on-dynamo profiling recipes:
#   1. Ensure nsys CLI is on PATH (runtime images strip it).
#   2. Ensure msgpack is importable (some dynamo install paths need it
#      and the upstream vllm-openai image doesn't bundle it; matches
#      InferenceMAX's vllm-container-deps.sh).
#
# Why combined: srt-slurm only honors a single setup_script per recipe.
#
# Strategy for nsys: prefer the official 2026.2.1 .deb published on
# developer.nvidia.com (per-arch URLs for x86_64 and arm64). Fall back
# to apt-get install via the container's preconfigured cuda repo only
# if the .deb fetch fails.

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

# Per-arch official .deb URLs (Nsight Systems 2026.2.1).
case "${ARCH}" in
    amd64)
        NSYS_DEB_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2026_2/NsightSystems-linux-cli-public-2026.2.1.210-3763964.deb"
        ;;
    arm64)
        NSYS_DEB_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2026_2/nsight-systems-2026.2.1_2026.2.1.210-1_arm64.deb"
        ;;
    *)
        NSYS_DEB_URL=""
        echo "[install-nsys] no canonical .deb URL known for arch=${ARCH}; will rely on apt"
        ;;
esac

apt_install_nsys() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nsight-systems-cli
}

if [[ -n "${NSYS_DEB_URL}" ]]; then
    DEB=/tmp/nsight-systems-cli.deb
    echo "[install-nsys] downloading: ${NSYS_DEB_URL}"
    if curl -fsSL "${NSYS_DEB_URL}" -o "${DEB}"; then
        echo "[install-nsys] apt-installing ${DEB}"
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "${DEB}"; then
            command -v nsys >/dev/null 2>&1 && echo "[install-nsys] $(nsys --version 2>&1 | head -1)" && exit 0
        fi
        echo "[install-nsys] .deb install path failed; falling back to apt repo"
    else
        echo "[install-nsys] .deb download failed; falling back to apt repo"
    fi
fi

# Fallback: apt repo (gives older nsys, e.g. 2024.2.3 from cuda-13/sbsa).
echo "[install-nsys] apt-get update"
apt-get update -qq || true

# arm64 → sbsa for NVIDIA's cuda repo path
KEYRING_ARCH="${ARCH/amd64/x86_64}"
KEYRING_ARCH="${KEYRING_ARCH/arm64/sbsa}"

if ! apt_install_nsys 2>&1; then
    echo "[install-nsys] direct install failed; setting up cuda-keyring + retrying"
    DISTRO="ubuntu2404"
    KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${KEYRING_ARCH}/cuda-keyring_1.1-1_all.deb"
    echo "[install-nsys] downloading: ${KEYRING_URL}"
    curl -fsSL "${KEYRING_URL}" -o /tmp/cuda-keyring.deb
    DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades /tmp/cuda-keyring.deb
    apt-get update -qq
    apt_install_nsys
fi

if ! command -v nsys >/dev/null 2>&1; then
    echo "[install-nsys] ERROR: nsys still not on PATH after install" >&2
    exit 1
fi

echo "[install-nsys] $(nsys --version 2>&1 | head -1)"
