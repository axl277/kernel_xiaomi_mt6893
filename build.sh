#!/bin/bash
#
# Compile script for Axlkernel
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
INCLUDE_KSU=false
for arg in "$@"; do
    case $arg in
        -c) CLEAN_BUILD=true ;;
        -k) INCLUDE_KSU=true ;; # Argumen untuk memicu instalasi ReSukiSU & KPM
    esac
done

[ "$CLEAN_BUILD" = true ] && rm -rf out

# ==========================================
# Integrasi ReSukiSU & KPM Backport
# ==========================================
if [ "$INCLUDE_KSU" = true ]; then
    echo -e "\n[+] Mengunduh dan memasang ReSukiSU..."
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash

    echo -e "\n[+] Mengonfigurasi Defconfig untuk KSU dan KPM..."
    DEFCONFIG_PATH="arch/arm64/configs/$DEFCONFIG"
    
    # Menambahkan config KSU dan KPM ke bagian bawah defconfig
    {
        echo ""
        echo "# ReSukiSU & KPM Configuration"
        echo "CONFIG_KSU=y"
        echo "CONFIG_KSU_MANUAL_HOOK=y"
        echo "CONFIG_KPM=y"
        echo "CONFIG_KALLSYMS=y"
        echo "CONFIG_KALLSYMS_ALL=y"
    } >> "$DEFCONFIG_PATH"

    echo -e "\n[+] Menerapkan backport set_memory.h untuk KPM..."

    # 1. Buat arch/arm64/include/asm/set_memory.h
    mkdir -p arch/arm64/include/asm
    cat << 'EOF' > arch/arm64/include/asm/set_memory.h
#ifndef _ASM_ARM64_SET_MEMORY_H
#define _ASM_ARM64_SET_MEMORY_H

int set_memory_ro(unsigned long addr, int numpages);
int set_memory_rw(unsigned long addr, int numpages);
int set_memory_x(unsigned long addr, int numpages);
int set_memory_nx(unsigned long addr, int numpages);

#endif
EOF

    # 2. Buat include/linux/set_memory.h
    mkdir -p include/linux
    cat << 'EOF' > include/linux/set_memory.h
#ifndef _LINUX_SET_MEMORY_H_
#define _LINUX_SET_MEMORY_H_

#include <asm/set_memory.h>

#endif
EOF

    # 3. Export symbol di arch/arm64/mm/pageattr.c agar bisa diakses KPM
    PAGEATTR="arch/arm64/mm/pageattr.c"
    if [ -f "$PAGEATTR" ]; then
        if grep -q "EXPORT_SYMBOL_GPL(set_memory_ro);" "$PAGEATTR"; then
            echo "[-] pageattr.c sudah di-patch sebelumnya, melewati..."
        else
            # Tambahkan include set_memory dan module.h di bagian atas file
            sed -i '1i #include <linux/module.h>\n#include <asm/set_memory.h>\n' "$PAGEATTR"
            
            # Injeksi EXPORT_SYMBOL_GPL untuk masing-masing fungsi
            sed -i '/int set_memory_ro(unsigned long addr, int numpages)/,/^}/ s/^}/}\nEXPORT_SYMBOL_GPL(set_memory_ro);/' "$PAGEATTR"
            sed -i '/int set_memory_rw(unsigned long addr, int numpages)/,/^}/ s/^}/}\nEXPORT_SYMBOL_GPL(set_memory_rw);/' "$PAGEATTR"
            sed -i '/int set_memory_x(unsigned long addr, int numpages)/,/^}/ s/^}/}\nEXPORT_SYMBOL_GPL(set_memory_x);/' "$PAGEATTR"
            sed -i '/int set_memory_nx(unsigned long addr, int numpages)/,/^}/ s/^}/}\nEXPORT_SYMBOL_GPL(set_memory_nx);/' "$PAGEATTR"
            echo "[+] Berhasil menambahkan EXPORT_SYMBOL_GPL di pageattr.c"
        fi
    else
        echo "[!] PERINGATAN: File $PAGEATTR tidak ditemukan. Pastikan path kernel-mu standar."
    fi
    echo "[+] Selesai menerapkan KPM Backport!"
fi
# ==========================================

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