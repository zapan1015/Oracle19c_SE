#!/usr/bin/env bash
# ==============================================================================
# Script: verify_ch1_ch2.sh
# Purpose: Comprehensive Verification of Chapter 1 & Chapter 2 Specifications
# ==============================================================================
set -euo pipefail

echo "=================================================================="
echo " [VERIFICATION REPORT] Oracle Linux 9 & SE2 Lab Environment"
echo "=================================================================="

echo ""
echo "--- [1] CHAPTER 01 Architecture & Kernel Checks ---"
echo "* Operating System: $(cat /etc/oracle-release)"
echo "* Active Kernel:    $(uname -r)"

if uname -r | grep -q "uek"; then
    echo "  [PASS] Unbreakable Enterprise Kernel (UEK) is active."
else
    echo "  [INFO] Running Red Hat Compatible Kernel (RHCK)."
fi

echo "* CPU Sizing (SE2 <= 2 sockets, <= 16 threads):"
echo "  - Total vCPUs / Logical Processors: $(nproc)"
echo "  - Sockets: $(lscpu | awk -F: '/Socket\(s\):/ {print $2}' | xargs)"
echo "  - Cores per socket: $(lscpu | awk -F: '/Core\(s\) per socket:/ {print $2}' | xargs)"

echo "* Non-GUI (Headless) Mode Check:"
RUNLEVEL=$(systemctl get-default)
echo "  - Default Target: ${RUNLEVEL}"
if [ "${RUNLEVEL}" = "multi-user.target" ]; then
    echo "  [PASS] System is running in Headless / Minimal mode (multi-user.target)."
fi

echo ""
echo "--- [2] CHAPTER 02 Memory & Swap Checks ---"
TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
SWAP_TOTAL_MB=$(free -m | awk '/Swap:/ {print $2}')
echo "* Total Physical RAM: ${TOTAL_RAM_MB} MB"
echo "* Total Swap Space:   ${SWAP_TOTAL_MB} MB"

echo "* Memory Allocation Principle (20% OS, 80% DB):"
OS_RESERVE_MB=$((TOTAL_RAM_MB * 20 / 100))
DB_AVAIL_MB=$((TOTAL_RAM_MB * 80 / 100))
echo "  - OS Reserve (~20%): ${OS_RESERVE_MB} MB"
echo "  - Max DB Memory (~80%): ${DB_AVAIL_MB} MB"

if [ "${DB_AVAIL_MB}" -gt 4096 ]; then
    echo "  [NOTE] DB Memory (${DB_AVAIL_MB} MB) > 4096 MB: ASMM (SGA+PGA) & HugePages Required (AMM is prohibited)."
else
    echo "  [NOTE] DB Memory (${DB_AVAIL_MB} MB) <= 4096 MB: AMM or ASMM allowed."
fi

echo ""
echo "--- [3] CHAPTER 02 Storage & OFA Mount Points Checks ---"
df -hT /u01 /u02/oradata /u03/oraredo1 /u04/oraredo2 /u05/fast_recovery_area 2>/dev/null || {
    echo "  [INFO] Dedicated mount points not mounted yet."
    echo "  Run '/vagrant/scripts/setup_storage_ch2.sh' inside VM to configure LVM & mounts."
}

echo ""
echo "=================================================================="
echo " Verification check completed."
echo "=================================================================="
