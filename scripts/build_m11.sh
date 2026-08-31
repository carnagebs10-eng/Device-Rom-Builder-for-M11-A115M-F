#!/usr/bin/env bash
# scripts/build_m11.sh - High-Reliability Automated Firmware Unpacker & M11 Zip Packager

set -eo pipefail

OUTPUT_NAME="${1:-CustomROM_M11}"
INCLUDE_MAGISK="${2:-false}"
GSI_NAME="${3:-GSI_System}"

WORK_DIR="workspace"
DOWNLOADS_DIR="${WORK_DIR}/downloads"
UNPACK_DIR="${WORK_DIR}/unpacked"
BUILD_DIR="${WORK_DIR}/build"
OUTPUT_DIR="${WORK_DIR}/output"

trap 'echo "Error encountered on line $LINENO. Exiting build process."; exit 1' ERR

echo "=========================================="
echo " Starting M11 Build Pipeline"
echo " ROM Output Target: ${OUTPUT_NAME}"
echo " GSI Identifier:    ${GSI_NAME}"
echo " Magisk Root Option: ${INCLUDE_MAGISK}"
echo "=========================================="

echo "=== 1. Workspace Cleanup & Structuring ==="
rm -rf "${BUILD_DIR}" "${UNPACK_DIR}"
mkdir -p "${UNPACK_DIR}"
mkdir -p "${BUILD_DIR}/META-INF/addons/extra"
mkdir -p "${BUILD_DIR}/META-INF/com/google/android/magisk"
mkdir -p "${BUILD_DIR}/META-INF/zbin/configs"
mkdir -p "${OUTPUT_DIR}"

echo "=== 2. Locate & Extract Firmware Archives ==="
cd "${DOWNLOADS_DIR}"

AP_ARCHIVE=$(ls AP*.tar* 2>/dev/null | head -n 1 || echo "")
if [ -n "$AP_ARCHIVE" ]; then
    echo "Extracting nested AP file: ${AP_ARCHIVE}"
    tar -xf "$AP_ARCHIVE" boot.img.lz4 super.img.lz4 2>/dev/null || tar -xf "$AP_ARCHIVE" boot.img super.img 2>/dev/null || true
fi

if [ -f boot.img.lz4 ]; then
    lz4 -df boot.img.lz4 boot.img
fi

if [ ! -f boot.img ]; then
    echo "Error: boot.img not found in stock firmware inputs!"
    exit 1
fi

if [ -f super.img.lz4 ]; then
    lz4 -df super.img.lz4 super.raw.img
elif [ -f super.img ]; then
    mv super.img super.raw.img
elif [ ! -f super.raw.img ]; then
    echo "Error: super.img / super.img.lz4 missing from stock archive!"
    exit 1
fi
cd ../..

cp "${DOWNLOADS_DIR}/boot.img" "${BUILD_DIR}/boot"

echo "=== 3. Processing Dynamic Super Partition ==="
if simg2img "${DOWNLOADS_DIR}/super.raw.img" "${WORK_DIR}/super.img" 2>/dev/null; then
    echo "Sparse image successfully converted to raw."
else
    echo "Image is already raw or conversion skipped. Moving directly."
    mv "${DOWNLOADS_DIR}/super.raw.img" "${WORK_DIR}/super.img"
fi

echo "Unpacking dynamic sub-partitions..."
if command -v lpunpack &> /dev/null; then
    lpunpack "${WORK_DIR}/super.img" "${UNPACK_DIR}/"
elif [ -f "./tools/extra/superunpack" ]; then
    chmod +x ./tools/extra/superunpack
    ./tools/extra/superunpack "${WORK_DIR}/super.img" "${UNPACK_DIR}/"
else
    echo "Error: Neither system lpunpack nor ./tools/extra/superunpack executable found!"
    exit 1
fi

for partition in system.img vendor.img product.img; do
    if [ ! -f "${UNPACK_DIR}/${partition}" ]; then
        echo "Error: Unpacked sub-partition ${partition} missing!"
        exit 1
    fi
done

echo "=== 4. System GSI Replacement ==="
GSI_FILE=$(ls "${DOWNLOADS_DIR}"/base_gsi.img "${DOWNLOADS_DIR}"/*.img 2>/dev/null | grep -v "super" | grep -v "boot" | head -n 1 || echo "")

if [ -z "$GSI_FILE" ] || [ ! -f "$GSI_FILE" ]; then
    echo "Error: Target GSI image file not found in download directory!"
    exit 1
fi

echo "Replacing system.img with: ${GSI_FILE}"
cp -f "$GSI_FILE" "${UNPACK_DIR}/system.img"

echo "=== 5. Re-assembling Dynamic Partition Metadata ==="
SYSTEM_SIZE=$(stat -c%s "${UNPACK_DIR}/system.img")
VENDOR_SIZE=$(stat -c%s "${UNPACK_DIR}/vendor.img")
PRODUCT_SIZE=$(stat -c%s "${UNPACK_DIR}/product.img")

ODM_CMD=""
if [ -f "${UNPACK_DIR}/odm.img" ]; then
    ODM_SIZE=$(stat -c%s "${UNPACK_DIR}/odm.img")
    ODM_CMD="--partition odm:readonly:${ODM_SIZE}:main --image odm=${UNPACK_DIR}/odm.img"
fi

if command -v lpmake &> /dev/null; then
    lpmake --metadata-size 65536 \
           --super-name super \
           --metadata-slots 2 \
           --device super:3221225472 \
           --group main:3217031168 \
           --partition system:readonly:${SYSTEM_SIZE}:main \
           --image system="${UNPACK_DIR}/system.img" \
           --partition vendor:readonly:${VENDOR_SIZE}:main \
           --image vendor="${UNPACK_DIR}/vendor.img" \
           --partition product:readonly:${PRODUCT_SIZE}:main \
           --image product="${UNPACK_DIR}/product.img" \
           $ODM_CMD \
           --sparse \
           --output "${BUILD_DIR}/super.new.img"
elif [ -f "./tools/extra/superrepack" ]; then
    chmod +x ./tools/extra/superrepack
    ./tools/extra/superrepack "${UNPACK_DIR}" "${BUILD_DIR}/super.new.img"
else
    echo "Error: Neither lpmake nor ./tools/extra/superrepack available to build super.new.img!"
    exit 1
fi

if [ ! -s "${BUILD_DIR}/super.new.img" ]; then
    echo "Error: Generated super.new.img is invalid or empty!"
    exit 1
fi

echo "=== 6. Assembling Recovery META-INF Structure ==="
touch "${BUILD_DIR}/META-INF/addons/info"
echo "ROM Name: ${OUTPUT_NAME}" > "${BUILD_DIR}/META-INF/addons/info"
echo "GSI Name: ${GSI_NAME}" >> "${BUILD_DIR}/META-INF/addons/info"

[ -d "tools/extra" ] && cp -r tools/extra/* "${BUILD_DIR}/META-INF/addons/extra/" 2>/dev/null || true
[ -d "tools/android" ] && cp -r tools/android/* "${BUILD_DIR}/META-INF/com/google/android/" 2>/dev/null || true
[ -d "tools/zbin" ] && cp -r tools/zbin/* "${BUILD_DIR}/META-INF/zbin/" 2>/dev/null || true

if [ "$INCLUDE_MAGISK" = "true" ]; then
    echo "Magisk v30.7 Enabled: Injecting binaries into META-INF..."
    if [ -d "tools/magisk" ] && [ "$(ls -A tools/magisk)" ]; then
        cp -r tools/magisk/* "${BUILD_DIR}/META-INF/com/google/android/magisk/" 2>/dev/null || true
    else
        touch "${BUILD_DIR}/META-INF/com/google/android/magisk/magisk.apk"
    fi
else
    echo "Magisk Disabled: Cleared Magisk folder."
    rm -rf "${BUILD_DIR}/META-INF/com/google/android/magisk"
fi

echo "=== 7. Building Final Recovery Flashable Archive ==="
cd "${BUILD_DIR}"
zip -r9 -q "../../${OUTPUT_DIR}/${OUTPUT_NAME}.zip" ./*
cd ../..

if [ -f "${OUTPUT_DIR}/${OUTPUT_NAME}.zip" ]; then
    echo "=========================================="
    echo " SUCCESS! Flashable ZIP Built Successfully"
    echo " Path: ${OUTPUT_DIR}/${OUTPUT_NAME}.zip"
    echo " Size: $(du -h "${OUTPUT_DIR}/${OUTPUT_NAME}.zip" | cut -f1)"
    echo "=========================================="
else
    echo "Error: Failed to produce output ZIP archive!"
    exit 1
fi
