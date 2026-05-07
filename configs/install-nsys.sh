#!/bin/bash
# Install the Nsight Systems CLI inside the worker container.
#
# Why: the dynamo-vllm-runtime image (and other "runtime" tags) ships
# without nsys, so any recipe with `profiling.type: nsys` fails with
# "nsys: command not found" when srt-slurm wraps the worker. This
# bridges that gap by downloading the public CLI .deb and installing
# it via apt at worker startup. ~30 s the first time per launch; the
# install is lost when the container exits.

set -e

if command -v nsys >/dev/null 2>&1; then
    echo "[install-nsys] already on PATH at $(command -v nsys); skipping"
    exit 0
fi

NSYS_DEB_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2026_2/NsightSystems-linux-cli-public-2026.2.1.210-3763964.deb"
DEB=/tmp/nsight-systems-cli.deb

echo "[install-nsys] downloading: ${NSYS_DEB_URL}"
curl -fsSL "$NSYS_DEB_URL" -o "$DEB"

echo "[install-nsys] apt-installing $DEB"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$DEB"

if ! command -v nsys >/dev/null 2>&1; then
    echo "[install-nsys] ERROR: nsys still not on PATH after install" >&2
    exit 1
fi

echo "[install-nsys] $(nsys --version 2>&1 | head -1)"
