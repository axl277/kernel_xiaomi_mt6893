#!/bin/bash
# 
# Axlkernel Build Script - Poco X3 GT (chopin)
# Full Integrated: Proton Clang + ReSukiSU + Auto-Patch Hooks
#

# 1. VARIABLE & DATE
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Axlkernel-ReSukiSU-${DEVICE}-${DATE}.zip"

echo -e "Building for: $DEVICE\n"

# 2. SETUP TOOLCHAIN (Proton Clang 15)
# Menghapus folder toolchain lama jika ada error sebelumnya agar clean
TC_DIR="$HOME/toolchains/proton-clang"
if [ ! -d "$TC_DIR" ]; then
    echo "Cloning Proton Clang 15..."
    mkdir -p "$HOME/toolchains"
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 "$TC_DIR"
fi

# Export Path & Compiler String
export PATH="$TC_DIR/bin:$PATH"
export KBUILD_COMPILER_STRING="$(clang --version | head -n 1)"

# 3. RESUKISU SOURCE INTEGRATION
# Mendownload source ReSukiSU jika belum ada
if [ ! -d "drivers/kernelsu" ]; then
    echo "Downloading ReSukiSU Source..."
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
    echo "ReSukiSU Source downloaded."
fi

# 4. AUTO-PATCHING HOOKS (Manual Hook Integration)
echo "Checking and Patching Manual Hooks..."

# Patch fs/exec.c (Untuk handle do_execveat_common)
if ! grep -q "ksu_handle_execveat" fs/exec.c; then
    sed -i '/static int do_execveat_common(int fd, struct filename \*filename,/,/{/ s/{/{\n#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_execveat(\&fd, \&filename, \&argv, \&envp, \&flags);\n#endif/' fs/exec.c
    echo "-> fs/exec.c patched."
fi

# Patch fs/open.c (Untuk handle do_faccessat)
if ! grep -q "ksu_handle_faccessat" fs/open.c; then
    sed -i '/long do_faccessat(int dfd, const char __user \*filename, int mode)/,/{/ s/{/{\n#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\n#endif/' fs/open.c
    echo "-> fs/open.c patched."
fi

# Patch fs/stat.c (Untuk handle vfs_fstatat)
if ! grep -q "ksu_handle_stat" fs/stat.c; then
    sed -i '/int vfs_fstatat(int dfd, const char __user \*filename, struct kstat \*stat,/,/{/ s/{/{\n#ifdef CONFIG_KSU_MANUAL_HOOK\n\tksu_handle_stat(\&dfd, \&filename, \&flags);\n#endif/' fs/stat.c
    echo "-> fs/stat.c patched."
fi

# 5. PRE-COMPILATION CLEANUP
echo -e "\nCleaning up build directory...\n"
mkdir -p out
make O=out ARCH=arm64 clean
make O=out ARCH=arm64 mrproper

# 6. START COMPILATION
echo -e "\nStarting Compilation with Proton Clang...\n"

# Load Defconfig (Pastikan CONFIG_KSU=y sudah ada di file defconfig manual kamu)
make O=out ARCH=arm64 $DEFCONFIG

# Build Process
make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 \
    LLVM_IAS=1 \
    Image.gz

# 7. ZIPPING WITH ANYKERNEL3
if [ -f "out/arch/arm64/boot/Image.gz" ]; then
    echo -e "\nKernel compiled successfully! Packing...\n"
    
    # Clone AnyKernel3
    git clone -q --depth=1 https://github.com/rio004/AnyKernel3 AnyKernel3
    
    # Copy Image.gz ke AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    
    # Hapus zip lama jika ada
    rm -rf *.zip
    
    # Membuat Zip Kernel
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder)
    
    # Bersihkan folder AnyKernel3 setelah zip jadi
    rm -rf AnyKernel3
    
    echo -e "\n====================================="
    echo "Build Completed in $((SECONDS / 60)) minute(s)!"
    echo "Zip Name: $ZIPNAME"
    echo "====================================="
else
    echo -e "\nERROR: Compilation Failed! Image.gz not found."
    exit 1
fi
