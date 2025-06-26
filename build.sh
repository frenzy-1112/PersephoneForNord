#!/bin/bash

# Script For Building Android arm64 Kernel using GCC

# Function to show informational messages
msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
    exit 1
}

# Colors
green='\033[01;32m'
default='\033[0m'

# Basic Config
KERNEL_DIR=$PWD
DEVICE="avicii"
DEFCONFIG=persephone_defconfig
COMPILER=gcc
INCREMENTAL=0
BUILD_DTBO=1
SILENCE=0
VERSION="X2"
ZIPNAME="Persephone-$VERSION"
DATE=$(TZ=Asia/Kolkata date +"%Y%m%d-%T")

# Toolchain paths (expected to be pre-cloned in CI)
GCC64_DIR="$KERNEL_DIR/gcc"
GCC32_DIR="$KERNEL_DIR/gcc32"

# Clone toolchains (only if not cloned)
clone() {
    msg "|| Cloning GCC toolchains ||"
    [ ! -d "$GCC64_DIR" ] && git clone --depth=1 https://github.com/sohamxda7/llvm-stable -b gcc64 "$GCC64_DIR"
    [ ! -d "$GCC32_DIR" ] && git clone --depth=1 https://github.com/sohamxda7/llvm-stable -b gcc32 "$GCC32_DIR"
}

# Export paths and env
exports() {
    export ARCH=arm64
    export SUBARCH=arm64
    export KBUILD_BUILD_USER="prashant"
    export KBUILD_BUILD_HOST="prashant"
    export PATH=$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH
    export KBUILD_COMPILER_STRING=$("$GCC64_DIR"/bin/aarch64-elf-gcc --version | head -n 1)
    export PROCS=$(nproc --all)
}

# Build kernel
build_kernel() {
    [ "$INCREMENTAL" -eq 0 ] && {
        msg "|| Cleaning sources ||"
        rm -rf out && rm -rf AnyKernel3/Image && rm -rf AnyKernel3/*.zip
    }

    msg "|| Starting defconfig ||"
    make O=out "$DEFCONFIG"

    BUILD_START=$(date +%s)

    MAKE+=(
        CROSS_COMPILE=aarch64-elf-
        CROSS_COMPILE_ARM32=arm-eabi-
        AR=aarch64-elf-ar
        OBJDUMP=aarch64-elf-objdump
        STRIP=aarch64-elf-strip
    )

    [ "$SILENCE" -eq 1 ] && MAKE+=( -s )

    msg "|| Starting compilation ||"
    make -j"$PROCS" O=out "${MAKE[@]}"

    if [ -f "$KERNEL_DIR/out/arch/arm64/boot/Image" ]; then
        msg "|| Kernel compiled successfully ||"
        [ "$BUILD_DTBO" -eq 1 ] && build_dtbo
        gen_zip
    else
        err "Compilation failed!"
    fi

    BUILD_END=$(date +%s)
    DIFF=$((BUILD_END - BUILD_START))
    echo -e "$green Build completed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds.$default"
}

# Build dtbo
build_dtbo() {
    msg "|| Building DTBO ||"
    python2 scripts/ufdt/libufdt/utils/src/mkdtboimg.py create \
        out/arch/arm64/boot/dtbo.img --page_size=4096 \
        out/arch/arm64/boot/dts/vendor/qcom/avicii-overlay.dtbo
}

# Package flashable zip
gen_zip() {
    msg "|| Packing flashable zip ||"
    cp out/arch/arm64/boot/Image AnyKernel3/
    [ -f out/arch/arm64/boot/dtbo.img ] && cp out/arch/arm64/boot/dtbo.img AnyKernel3/
    cd AnyKernel3 || exit 1
    zip -r9 "${ZIPNAME}-A11-${DEVICE}-${DATE}.zip" * -x .git README.md
    cd ..
}

# Run steps
clone
exports
build_kernel
