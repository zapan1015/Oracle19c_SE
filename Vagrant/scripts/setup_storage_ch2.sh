#!/usr/bin/env bash
# ==============================================================================
# Script: setup_storage_ch2.sh
# Purpose: Execute Chapter 2 Section 2.3.4 Storage Layout and LVM Setup
# Targets: /u01, /u02/oradata, /u03/oraredo1, /u04/oraredo2, /u05/fast_recovery_area
# ==============================================================================
set -euo pipefail

echo "=================================================================="
echo ">> [Chapter 2.3.4] Initializing Storage Mount Points and LVM"
echo "=================================================================="

# 1. Create mount point directories
mkdir -p /u01 /u02/oradata /u03/oraredo1 /u04/oraredo2 /u05/fast_recovery_area

# Detect secondary disks attached by Vagrant
# /dev/sdb: 30GB (u01)
# /dev/sdc: 20GB (u02)
# /dev/sdd: 5GB  (u03)
# /dev/sde: 5GB  (u04)
# /dev/sdf: 20GB (u05)
DISKS=("/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde" "/dev/sdf")

echo "Checking secondary disk devices..."
lsblk

# Check if disks exist
for d in "${DISKS[@]}"; do
    if [ ! -b "$d" ]; then
        echo "Error: Device $d not found. Please ensure secondary disks are configured."
        exit 1
    fi
done

# 2. Initialize Physical Volumes (PV)
echo ">> Initializing Physical Volumes..."
pvcreate -f "${DISKS[@]}"

# 3. Create Volume Groups (VG)
echo ">> Creating Volume Groups..."
vgcreate -f vg_ora_app   /dev/sdb
vgcreate -f vg_ora_data  /dev/sdc
vgcreate -f vg_ora_redo1 /dev/sdd
vgcreate -f vg_ora_redo2 /dev/sde
vgcreate -f vg_ora_fra   /dev/sdf

# 4. Create Logical Volumes (LV) utilizing 100% of each VG
echo ">> Creating Logical Volumes..."
lvcreate -l 100%FREE -n lv_u01     vg_ora_app
lvcreate -l 100%FREE -n lv_oradata vg_ora_data
lvcreate -l 100%FREE -n lv_redo1   vg_ora_redo1
lvcreate -l 100%FREE -n lv_redo2   vg_ora_redo2
lvcreate -l 100%FREE -n lv_fra     vg_ora_fra

# 5. Format filesystems with XFS
echo ">> Formatting Logical Volumes with XFS..."
mkfs.xfs -f /dev/vg_ora_app/lv_u01
mkfs.xfs -f /dev/vg_ora_data/lv_oradata
mkfs.xfs -f /dev/vg_ora_redo1/lv_redo1
mkfs.xfs -f /dev/vg_ora_redo2/lv_redo2
mkfs.xfs -f /dev/vg_ora_fra/lv_fra

# 6. Configure /etc/fstab with noatime,nodiratime options (Chapter 2 Section 2.3.4)
echo ">> Configuring /etc/fstab..."
grep -v "/dev/mapper/vg_ora" /etc/fstab > /tmp/fstab.tmp || true
cat << 'EOF' >> /tmp/fstab.tmp
/dev/mapper/vg_ora_app-lv_u01     /u01                    xfs  defaults                    0 0
/dev/mapper/vg_ora_data-lv_oradata /u02/oradata           xfs  defaults,noatime,nodiratime 0 0
/dev/mapper/vg_ora_redo1-lv_redo1 /u03/oraredo1           xfs  defaults,noatime,nodiratime 0 0
/dev/mapper/vg_ora_redo2-lv_redo2 /u04/oraredo2           xfs  defaults,noatime,nodiratime 0 0
/dev/mapper/vg_ora_fra-lv_fra     /u05/fast_recovery_area xfs  defaults,noatime,nodiratime 0 0
EOF
cp /tmp/fstab.tmp /etc/fstab

# 7. Mount and verify
systemctl daemon-reload
mount -a

echo "=================================================================="
echo ">> [Verification] Storage Mount Layout (Chapter 2 Section 2.3)"
echo "=================================================================="
df -hT /u01 /u02/oradata /u03/oraredo1 /u04/oraredo2 /u05/fast_recovery_area
lsblk
echo ">> Storage setup for Chapter 2 completed successfully!"
