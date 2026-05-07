#!/bin/bash
# Install the Nsight Systems CLI inside the worker container.
#
# Why: the dynamo-vllm-runtime image (and other "runtime" tags) ships
# without nsys, so any recipe with `profiling.type: nsys` fails with
# "nsys: command not found" when srt-slurm wraps the worker.
#
# Strategy: rely on the container's pre-configured NVIDIA apt repo
# (the runtime image is built FROM nvcr.io/nvidia/cuda:13.x-runtime,
# which ships with /etc/apt/sources.list.d/cuda*.list pointing at
# developer.download.nvidia.com). `apt-get install nsight-systems-cli`
# resolves to the right architecture (aarch64 on lyris/ptyche, x86_64
# on bia/eos) automatically.
#
# Fallback: if the cuda repo isn't configured (container variant
# without it), install cuda-keyring first to set it up.

set -e

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
