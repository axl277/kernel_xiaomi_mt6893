#!/bin/bash
# 
# Axlkernel Build Script with Auto-Patch ReSukiSU
# Target: Poco X3 GT (chopin)
#

SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Axlkernel-ReSukiSU-${DEVICE}-${DATE}.zip"

echo -e "Starting Build for $DEVICE...\n"

# 1. Setup Toolchain
TC_DIR="$HOME/toolchains/proton-clang"
if [ ! -d "$TC_DIR" ]; then
    echo "Cloning Toolchain..."
    mkdir -p "$HOME/toolchains"
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 "$TC_DIR"
fi
export PATH="$TC_DIR/bin:$PATH"

# 2. ReSukiSU Source Integration
if [ ! -d "drivers/kernelsu" ]; then
    echo "Downloading ReSukiSU Source..."
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
    
    # Register to Kconfig/Makefile
    echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
fi

# 3. AUTO-PATCHING HOOKS (The "Magic" Part)
echo "Applying Auto-Patching to Kernel Files..."

# Patch fs/exec.c (do_execveat_common)
if ! grep -q "ksu_handle_execveat" fs/exec.c; then
    sed -i '/static int do_execveat_common(int fd, struct filename \*filename,/,/{/ s/{/{\n#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_execveat(\&fd, \&filename, \&argv, \&envp, \&flags);\n#endif/' fs/exec.c
    echo "-> fs/exec.c patched."
fi

# Patch fs/open.c (do_faccessat)
if ! grep -q "ksu_handle_faccessat" fs/open.c; then
    sed -i '/long do_faccessat(int dfd, const char __user \*filename, int mode)/,/{/ s/{/{\n#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\n#endif/' fs/open.c
    echo "-> fs/open.c patched."
fi

# Patch fs/stat.c (vfs_fstatat)
if ! grep -q "ksu_handle_stat" fs/stat.c; then
    sed -i '/int vfs_fstatat(int dfd, const char __user \*filename, struct kstat \*stat,/,/{/ s/{/{\n#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_stat(\&dfd, \&filename, \&flags);\n#endif/' fs/stat.c
    echo "-> fs/stat.c patched."
fi

# 4. Compilation
echo -e "\nStarting Compilation...\n"
mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG

# Note: Pastikan CONFIG_KSU=y & CONFIG_KSU_MANUAL_HOOK=y sudah ada di defconfig manualmu
if make -j$(nproc --all) O=out ARCH=arm64 \
    CC="clang" \
    LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    Image.gz; then

    echo -e "\nSuccess! Packing with AnyKernel3...\n"
    git clone -q --depth=1 https://github.com/rio004/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    rm -rf *zip
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder)
    rm -rf AnyKernel3
    echo "Build Completed: $ZIPNAME"
else
    echo -e "\nBuild Failed! Check logs above."
    exit 1
fi
