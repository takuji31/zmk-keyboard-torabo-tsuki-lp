#!/usr/bin/env bash
set -euo pipefail

DOCKER_IMAGE="zmkfirmware/zmk-build-arm:stable"
WORKSPACE="/workspace"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIRMWARE_DIR="${PROJECT_DIR}/firmware"

cat <<'SCRIPT' > "${PROJECT_DIR}/.build_inner.sh"
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/workspace"
BUILD_BASE="${WORKSPACE}/.build"
export HOME="/tmp/build-home"

# Set up HOME for non-root user (git config, cmake cache, etc.)
mkdir -p "${HOME}"

# Allow git operations on mounted volume
git config --global --add safe.directory '*'

# Use a separate directory for west workspace (same approach as CI)
# This prevents west from overwriting repo files (e.g. zephyr/module.yml)
mkdir -p "${BUILD_BASE}"

# Copy config to the build directory
mkdir -p "${BUILD_BASE}/config"
cp -R "${WORKSPACE}/config/"* "${BUILD_BASE}/config/"

cd "${BUILD_BASE}"

# Initialize west workspace (skip if already initialized)
if [ ! -d .west ]; then
  echo "==> Initializing west workspace..."
  west init -l config/
fi

echo "==> Updating west modules..."
west update

echo "==> Registering Zephyr CMake package..."
west zephyr-export

# Extra modules: register the repo root so ZMK can find boards/shields and snippets
EXTRA_MODULES="-DZMK_EXTRA_MODULES=${WORKSPACE}"

# --- Build targets ---

echo "==> Building: torabo_tsuki_lp_left (peripheral)"
west build -s zmk/app -b bmp_boost -d build/left -S studio-rpc-usb-uart -- \
  -DSHIELD=torabo_tsuki_lp_left \
  -DZMK_CONFIG="${BUILD_BASE}/config" \
  ${EXTRA_MODULES}

echo "==> Building: torabo_tsuki_lp_right (central)"
west build -s zmk/app -b bmp_boost -d build/right -S studio-rpc-usb-uart -- \
  -DSHIELD=torabo_tsuki_lp_right \
  -DZMK_CONFIG="${BUILD_BASE}/config" \
  -DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y \
  ${EXTRA_MODULES}

echo "==> Building: settings_reset"
west build -s zmk/app -b bmp_boost -d build/settings_reset -- \
  -DSHIELD=settings_reset \
  -DZMK_CONFIG="${BUILD_BASE}/config" \
  ${EXTRA_MODULES}

# --- Collect firmware ---

echo "==> Collecting firmware..."
mkdir -p "${WORKSPACE}/firmware"
cp build/left/zephyr/zmk.uf2          "${WORKSPACE}/firmware/torabo_tsuki_lp_left_peripheral.uf2"
cp build/right/zephyr/zmk.uf2         "${WORKSPACE}/firmware/torabo_tsuki_lp_right_central.uf2"
cp build/settings_reset/zephyr/zmk.uf2 "${WORKSPACE}/firmware/settings_reset.uf2"

echo "==> Build complete! Firmware files:"
ls -lh "${WORKSPACE}/firmware/"*.uf2
SCRIPT

chmod +x "${PROJECT_DIR}/.build_inner.sh"

echo "==> Pulling Docker image: ${DOCKER_IMAGE}"
docker pull "${DOCKER_IMAGE}"

echo "==> Starting build in Docker container..."
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "${PROJECT_DIR}:${WORKSPACE}" \
  -w "${WORKSPACE}" \
  "${DOCKER_IMAGE}" \
  bash .build_inner.sh

# Clean up inner script
rm -f "${PROJECT_DIR}/.build_inner.sh"

echo "==> Done! Firmware files are in: ${FIRMWARE_DIR}/"
