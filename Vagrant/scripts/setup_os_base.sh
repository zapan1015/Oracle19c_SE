#!/usr/bin/env bash
# ==============================================================================
# Script: setup_os_base.sh
# Purpose: Oracle Linux 9 Minimal Headless Base Configuration (Chapter 1 & 2)
# ==============================================================================
set -euo pipefail

echo "=================================================================="
echo ">> [1/4] Checking Oracle Linux 9 Kernel and Architecture (Chapter 1)"
echo "=================================================================="
uname -r
cat /etc/oracle-release || true

# Chapter 1.2: Check UEK R7 and io_uring availability
echo "Checking io_uring support..."
if grep -q "io_uring" /boot/config-$(uname -r) 2>/dev/null || grep -q "CONFIG_IO_URING=y" /boot/config-$(uname -r) 2>/dev/null; then
    echo ">> CONFIG_IO_URING is enabled in kernel config."
else
    echo ">> Warning: Check kernel io_uring configuration."
fi

echo "=================================================================="
echo ">> [2/4] Configuring System Timezone & Basic Utilities"
echo "=================================================================="
timedatectl set-timezone Asia/Seoul || true
timedatectl status || true

# Ensure dnf utilities are available
dnf install -y tar bzip2 gzip unzip lsof bc bind-utils lvm2 xfsprogs >/dev/null 2>&1 || true

echo "=================================================================="
echo ">> [3/4] Sizing & Configuring Swap Space (Chapter 2 Section 2.2)"
echo "=================================================================="
# Chapter 2 Table 2-3: For 2GB < RAM <= 16GB, Swap = 1.0 * RAM (~6GB)
CURRENT_SWAP_MB=$(free -m | awk '/Swap:/ {print $2}')
TARGET_SWAP_MB=6144

if [ "${CURRENT_SWAP_MB}" -lt "${TARGET_SWAP_MB}" ]; then
    NEEDED_MB=$((TARGET_SWAP_MB - CURRENT_SWAP_MB))
    echo "Current Swap: ${CURRENT_SWAP_MB}MB. Adding ${NEEDED_MB}MB swap file (/swapfile_extra)..."
    if [ ! -f /swapfile_extra ]; then
        dd if=/dev/zero of=/swapfile_extra bs=1M count=${NEEDED_MB} status=progress
        chmod 600 /swapfile_extra
        mkswap /swapfile_extra
        swapon /swapfile_extra
        echo "/swapfile_extra none swap sw 0 0" >> /etc/fstab
        echo ">> Extra swap activated successfully."
    fi
else
    echo ">> Current Swap (${CURRENT_SWAP_MB}MB) already satisfies Chapter 2 requirements."
fi

echo "=================================================================="
echo ">> [4/4] Base System Verification"
echo "=================================================================="
echo "CPU Cores: $(nproc)"
echo "Physical RAM:"
free -m
echo "Swap Space:"
swapon --show

echo ">> Base Oracle Linux 9 environment is ready for Chapter 1 & 2 testing!"
