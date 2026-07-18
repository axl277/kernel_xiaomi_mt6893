#!/bin/bash
#
# Compile script for Axlkernel with ReSukiSU and KPM Support (GOD MODE)
#

# Date/Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Device
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Artic-Core-Resukisu-KPatch-${DEVICE}-${DATE}.zip"

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
# ReSukiSU Setup & Bypass
# ==========================================
echo -e "\n[+] Setting up ReSukiSU..."
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash

echo "[+] Menambal KPM untuk kompatibilitas Kernel 4.14..."
SUPER_ACCESS="drivers/kernelsu/kpm/super_access.c"
if [ -f "$SUPER_ACCESS" ]; then
    sed -i '/pids\[/d' "$SUPER_ACCESS"
fi

# [TRIK ULTIMATE]: Paksa Makefile SukiSU untuk mengcompile KPM asli, bukan Stub!
KSU_MAKEFILE="drivers/kernelsu/Makefile"
if [ -f "$KSU_MAKEFILE" ]; then
    # Ubah syarat kompilasi KPM agar selalu mengikuti status KSU (yang pasti nyala)
    sed -i 's/CONFIG_KPM/CONFIG_KSU/g' "$KSU_MAKEFILE"
    # Suntikkan variabel KPM langsung ke compiler
    sed -i '1i ccflags-y += -DCONFIG_KPM=1' "$KSU_MAKEFILE"
    echo "[+] Berhasil mem-bypass Makefile ReSukiSU agar KPM tidak jadi cangkang kosong!"
fi
# ---------------------------------

echo "[+] Patching $DEFCONFIG for ReSukiSU (Non-SUSFS) & KPM Support..."
DEFCONFIG_PATH="arch/arm64/configs/$DEFCONFIG"

sed -i '/CONFIG_KSU/d' "$DEFCONFIG_PATH"
sed -i '/CONFIG_KPM/d' "$DEFCONFIG_PATH"

cat <<EOF >> "$DEFCONFIG_PATH"
# ReSukiSU
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y

# Kprobes
CONFIG_MODULES=y
CONFIG_KPROBES=y
CONFIG_HAVE_KPROBES=y
CONFIG_KPROBE_EVENTS=y

# KPM & Ftrace
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_EXPERT=y
CONFIG_DEBUG_KERNEL=y
CONFIG_FTRACE=y
CONFIG_DYNAMIC_FTRACE=y
CONFIG_FUNCTION_TRACER=y
CONFIG_HAVE_DYNAMIC_FTRACE=y
EOF

# --- KPM Backport (Membuat header set_memory.h) ---
mkdir -p arch/arm64/include/asm
cat << 'EOF' > arch/arm64/include/asm/set_memory.h
#ifndef _ASM_ARM64_SET_MEMORY_H
#define _ASM_ARM64_SET_MEMORY_H
int set_memory_ro(unsigned long addr, int numpages);
int set_memory_rw(unsigned long addr, int numpages);
int set_memory_x(unsigned long addr, int numpages);
int set_memory_nx(unsigned long addr, int numpages);
static inline int set_direct_map_invalid_noflush(struct page *page) { return 0; }
static inline int set_direct_map_default_noflush(struct page *page) { return 0; }
#endif
EOF

mkdir -p include/linux
cat << 'EOF' > include/linux/set_memory.h
#ifndef _LINUX_SET_MEMORY_H_
#define _LINUX_SET_MEMORY_H_
#include <asm/set_memory.h>
#endif
EOF
# --- Selesai KPM Backport ---


# ==========================================
# Compilation process
# ==========================================
mkdir -p out

# FIX BUG BAWAAN KERNEL XIAOMI PADA FTRACE
TRACE_PERF="kernel/trace/trace_event_perf.c"
if [ -f "$TRACE_PERF" ]; then
    sed -i '432d' "$TRACE_PERF"
fi

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
