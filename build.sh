#!/bin/bash
#
# Compile script for Axlkernel with ReSukiSU and KPM Support
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

# ==========================================
# ReSukiSU & KPM Setup
# ==========================================
echo -e "\n[+] Setting up ReSukiSU..."
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash

# --- KPM FIX UNTUK KERNEL 4.14 ---
echo "[+] Menambal super_access.c untuk kompatibilitas Kernel 4.14..."
SUPER_ACCESS="drivers/kernelsu/kpm/super_access.c"
if [ -f "$SUPER_ACCESS" ]; then
    # Menghapus semua baris yang mencoba mengakses array pids[]
    sed -i '/pids\[/d' "$SUPER_ACCESS"
    echo "[+] Berhasil menambal KPM super_access.c!"
fi
# ---------------------------------

echo "[+] Patching $DEFCONFIG for ReSukiSU (Non-SUSFS) & KPM Support..."
DEFCONFIG_PATH="arch/arm64/configs/$DEFCONFIG"

# Bersihkan config lama jika ada agar tidak dobel
sed -i '/CONFIG_KSU/d' "$DEFCONFIG_PATH"
sed -i '/CONFIG_KPM/d' "$DEFCONFIG_PATH"

# Tambahkan Config ReSukiSU & KPM
cat <<EOF >> "$DEFCONFIG_PATH"

# ReSukiSU
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y

# KPM Support (Wajib untuk Kernel Non-GKI)
CONFIG_KPM=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y

# Kprobes (Dibutuhkan oleh sistem ReSukiSU)
CONFIG_MODULES=y
CONFIG_KPROBES=y
CONFIG_HAVE_KPROBES=y
CONFIG_KPROBE_EVENTS=y
EOF

# --- Mulai KPM Backport (Membuat header set_memory.h) ---
echo -e "\n[+] Menerapkan backport header set_memory.h untuk KPM..."
mkdir -p arch/arm64/include/asm

# Mengisi header asm/set_memory.h dengan deklarasi tambahan
cat << 'EOF' > arch/arm64/include/asm/set_memory.h
#ifndef _ASM_ARM64_SET_MEMORY_H
#define _ASM_ARM64_SET_MEMORY_H

int set_memory_ro(unsigned long addr, int numpages);
int set_memory_rw(unsigned long addr, int numpages);
int set_memory_x(unsigned long addr, int numpages);
int set_memory_nx(unsigned long addr, int numpages);

/* Backport untuk KPM di Kernel lawas (menghindari undeclared identifier di vmalloc) */
static inline int set_direct_map_invalid_noflush(struct page *page)
{
    return 0;
}

static inline int set_direct_map_default_noflush(struct page *page)
{
    return 0;
}

#endif
EOF

mkdir -p include/linux
cat << 'EOF' > include/linux/set_memory.h
#ifndef _LINUX_SET_MEMORY_H_
#define _LINUX_SET_MEMORY_H_

#include <asm/set_memory.h>

#endif
EOF

echo "[+] EXPORT_SYMBOL_GPL untuk pageattr.c sudah dilakukan secara manual di source code."
echo "[+] Header set_memory.h berhasil dibuat dan diperbarui!"
# --- Selesai KPM Backport ---
# ==========================================


# ==========================================
# Compilation process
# ==========================================
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
    exit 1
fi