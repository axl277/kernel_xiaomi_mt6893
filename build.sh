#!/bin/bash
#
# Compile script for Axlkernel with ReSukiSU & SUSFS
#

# Date/Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Device
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Axlkernel-${DEVICE}-${DATE}.zip"

echo -e "Building for: $DEVICE\n"

# Ensure the toolchain is available
TC_DIR="$HOME/toolchains/proton-clang"
CURRENT_DIR=$(pwd)
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$HOME/toolchains"
    cd "$HOME/toolchains"
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 proton-clang
    cd "$CURRENT_DIR"
fi
export PATH="$TC_DIR/bin:$PATH"

# Process options
CLEAN_BUILD=false
for arg in "$@"; do
    case $arg in
        -c) CLEAN_BUILD=true ;;
    esac
done

[ "$CLEAN_BUILD" = true ] && rm -rf out

# ===================================================
# [ OTOMATISASI RESUKISU & SUSFS ]
# ===================================================
echo -e "\n[+] Mengunduh dan Menyiapkan ReSukiSU..."
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash

echo -e "\n[+] Menyiapkan SUSFS untuk Kernel 4.14..."
rm -rf susfs4ksu
git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git

mkdir -p fs/
mkdir -p include/linux/

# Salin file asli dari repository
cp -rf susfs4ksu/kernel_patches/fs/* fs/
cp -rf susfs4ksu/kernel_patches/include/linux/* include/linux/

echo "[+] Memastikan file header SUSFS lengkap..."
# Jika susfs_def.h hilang dari cabang 4.14, ambil langsung dari Android 14
if [ ! -f "include/linux/susfs_def.h" ]; then
    curl -LSs -o include/linux/susfs_def.h "https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android14-5.15/kernel_patches/include/linux/susfs_def.h"
fi

# Jika masih kosong, buat secara manual agar tidak fatal
if [ ! -s "include/linux/susfs_def.h" ] || ! grep -q "SYSCALL_FAMILY" include/linux/susfs_def.h; then
    cat << 'EOF' > include/linux/susfs_def.h
#ifndef _SUSFS_DEF_H
#define _SUSFS_DEF_H
#define SYSCALL_FAMILY_ALL_ENOENT 1
#endif
EOF
fi

# Injeksi deklarasi ke susfs.h jika file dari 4.14 tidak mendefinisikannya
if ! grep -q "susfs_sus_path_by_filename" include/linux/susfs.h 2>/dev/null; then
    cat << 'EOF' >> include/linux/susfs.h

#ifndef SYSCALL_FAMILY_ALL_ENOENT
#define SYSCALL_FAMILY_ALL_ENOENT 1
struct filename;
extern int susfs_sus_path_by_filename(struct filename *fname, int *error, int syscall_family);
#endif
EOF
fi

echo "Applying SUSFS Kernel patches..."
patch -p1 < susfs4ksu/kernel_patches/50_add_susfs_in_kernel-4.14.patch || true
patch -p1 < susfs4ksu/kernel_patches/51_add_susfs_in_fs-4.14.patch || true
patch -p1 --dir=KernelSU < susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch || true

echo -e "\n[+] Memasukkan Konfigurasi ke $DEFCONFIG..."
sed -i '/CONFIG_KSU/d' "arch/arm64/configs/$DEFCONFIG"

cat <<EOF >> "arch/arm64/configs/$DEFCONFIG"

# ReSukiSU & SUSFS Configurations
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y
EOF
# ===================================================

# Compilation process
mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG

echo -e "\nStarting compilation...\n"
if make -j$(nproc --all) O=out ARCH=arm64 CC="ccache clang" LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- Image.gz; then
    echo -e "\nKernel compiled successfully! Zipping up...\n"
    git clone -q --depth=1 https://github.com/axl277/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    rm -rf *zip out/arch/arm64/boot
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder)
    rm -rf AnyKernel3
    echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo "Zip: $ZIPNAME"
else
    echo -e "\nCompilation failed!"
fi