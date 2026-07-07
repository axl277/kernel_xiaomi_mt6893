#!/bin/bash
set -e

SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="ArticCore-KernelSUNext-OSS-${DATE}.zip"

echo -e "📱 Building for: $DEVICE\n"

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
INCLUDE_ROOT=true

for arg in "$@"; do
    case $arg in
        -c) CLEAN_BUILD=true ;;
    esac
done

[ "$CLEAN_BUILD" = true ] && rm -rf out

# ===== KernelSU Next Setup =====
if [ "$INCLUDE_ROOT" = true ]; then
    echo -e "\n🔧 Setting up KernelSU Next...\n"
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy
    echo -e "✅ Integrated KernelSU Next.\n"
fi
# ==================================

mkdir -p out
echo -e "⚙️ Generating defconfig..."
make O=out ARCH=arm64 $DEFCONFIG

echo -e "\n🚀 Starting compilation...\n"
if make -j$(nproc --all) O=out ARCH=arm64 CC="ccache clang" LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- Image.gz; then
    echo -e "\n📦 Packaging...\n"
    AK3="AnyKernel3"
    if [ ! -d "$AK3" ]; then
        git clone -q --depth=1 https://github.com/axl277/AnyKernel3 "$AK3"
    fi
    cp out/arch/arm64/boot/Image.gz "$AK3/"
    rm -rf *.zip
    (cd "$AK3" && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder)
    rm -rf "$AK3"
    echo -e "\n✅ Completed in $((SECONDS / 60))m $((SECONDS % 60))s!"
    echo -e "📄 Zip: $ZIPNAME\n"
else
    echo -e "\n❌ Compilation failed!\n"
    exit 1
fi
