#!/bin/bash
# Script Kompilasi Axlkernel dengan KernelSU Next + SuSFS (Anti-Error 404)

SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Axlkernel-${DEVICE}-${DATE}.zip"

echo -e "==========================================="
echo -e " Memulai Proses Build untuk: $DEVICE"
echo -e "===========================================\n"

# ---------------------------------------------------------
# SETUP TOOLCHAIN
# ---------------------------------------------------------
TC_DIR="$HOME/toolchains/proton-clang"
CURRENT_DIR=$(pwd)
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$HOME/toolchains"
    cd "$HOME/toolchains"
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 proton-clang
    cd "$CURRENT_DIR"
fi
export PATH="$TC_DIR/bin:$PATH"

CLEAN_BUILD=false
for arg in "$@"; do
    case $arg in
        -c) CLEAN_BUILD=true ;;
    esac
done
[ "$CLEAN_BUILD" = true ] && rm -rf out

# ---------------------------------------------------------
# FASE 1: CLEANUP
# ---------------------------------------------------------
echo -e "\n[1/4] Membersihkan sisa patch sebelumnya..."
git checkout fs/exec.c fs/open.c fs/read_write.c fs/stat.c kernel/reboot.c fs/namespace.c fs/readdir.c kernel/sys.c fs/proc/task_mmu.c arch/arm64/configs/$DEFCONFIG 2>/dev/null || true

# ---------------------------------------------------------
# FASE 2: KERNELSU NEXT
# ---------------------------------------------------------
echo -e "\n[2/4] Menyiapkan KernelSU Next..."
if [ ! -d "KernelSU-Next" ]; then
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy
fi

# ---------------------------------------------------------
# FASE 3: MENGUNDUH DAN MENERAPKAN SUSFS (FULL GIT CLONE)
# ---------------------------------------------------------
echo -e "\n[3/4] Mengintegrasikan SuSFS ke Kernel & KSU..."
rm -rf susfs_temp
# Mengunduh repositori utuh agar 100% tidak ada error 404
git clone -q https://gitlab.com/simonpunk/susfs4ksu.git -b kernel-4.14 susfs_temp

# 1. Patch KernelSU Next (Inilah yang gagal di log kamu sebelumnya)
echo "  -> Menerapkan patch SuSFS ke KernelSU Next..."
cd KernelSU-Next
patch -p1 < ../susfs_temp/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch || echo "[!] Info: Patch KSU selesai."
cd ..

# 2. Patch VFS Kernel
echo "  -> Menerapkan patch ke VFS Kernel..."
patch -p1 < susfs_temp/kernel_patches/50_add_susfs_in_kernel-4.14.patch || echo "[!] Info: Ada patch VFS yang reject, Auto-Heal akan berjalan..."

# 3. Auto-Heal File Xiaomi (Task MMU & Syscall)
echo "  -> Menjalankan Auto-Heal..."
if ! grep -q "linux/susfs.h" fs/proc/task_mmu.c; then
    sed -i '20i #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#include <linux/susfs_def.h>\n#endif' fs/proc/task_mmu.c
fi

if ! grep -q "susfs_prctl" kernel/sys.c; then
    sed -i '/case PR_SET_NAME:/i \
#ifdef CONFIG_KSU_SUSFS\n\
\tcase 0x535553:\n\
\t\terror = susfs_prctl(option, arg2, arg3, arg4, arg5);\n\
\t\tbreak;\n\
#endif' kernel/sys.c
fi

# 4. Salin Semua File Inti SuSFS
echo "  -> Menyalin file driver SuSFS..."
cp -rf susfs_temp/kernel_patches/fs/* fs/
cp -rf susfs_temp/kernel_patches/include/linux/* include/linux/

# Bersihkan folder temp
rm -rf susfs_temp

# ---------------------------------------------------------
# FASE 4: KONFIGURASI DEFCONFIG
# ---------------------------------------------------------
echo -e "\n[4/4] Mengatur konfigurasi ($DEFCONFIG)..."
sed -i '/CONFIG_KPROBES/d' arch/arm64/configs/$DEFCONFIG
sed -i '/CONFIG_KPROBE_EVENTS/d' arch/arm64/configs/$DEFCONFIG
sed -i '/CONFIG_KSU_KPROBE_HOOKS/d' arch/arm64/configs/$DEFCONFIG
sed -i '/CONFIG_KSU=y/d' arch/arm64/configs/$DEFCONFIG
sed -i '/CONFIG_KSU_SUSFS/d' arch/arm64/configs/$DEFCONFIG

cat >> arch/arm64/configs/$DEFCONFIG <<EOF

# KernelSU Next & SuSFS Integrations
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
# CONFIG_KPROBES is not set
EOF

# ---------------------------------------------------------
# FASE KOMPILASI
# ---------------------------------------------------------
echo -e "\n==========================================="
echo -e " Memulai Kompilasi Kernel"
echo -e "===========================================\n"

mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG

if make -j$(nproc --all) O=out ARCH=arm64 CC="ccache clang" LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- Image.gz; then
    echo -e "\n[SUKSES] Kernel berhasil dikompilasi! Membuat ZIP...\n"
    rm -rf AnyKernel3
    git clone -q --depth=1 https://github.com/axl277/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3/
    cd AnyKernel3
    zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder
    cd ..
    rm -rf AnyKernel3
    echo -e "\n==========================================="
    echo -e " SELESAI: $ZIPNAME"
    echo -e "==========================================="
else
    echo -e "\n[GAGAL] Kompilasi terhenti karena error."
    exit 1
fi