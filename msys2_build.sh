#!/bin/bash
set -e

# Build Linux ARM64 kernel on MSYS2/Windows
# Requires: pacman -S make flex bison bc gcc diffutils git python openssl-devel ccache mingw-w64-x86_64-clang mingw-w64-x86_64-lld mingw-w64-x86_64-llvm

KERNEL_DIR="$HOME/kernel_raphael"
export GIT_SSL_NO_VERIFY=true

# PATH: /usr/bin first (for MSYS2 gcc), then /mingw64/bin (for clang/lld)
export PATH="/usr/bin:/mingw64/bin:/bin:/opt/bin:$PATH"

# Host compiler (for building kernel's host tools like fixdep, scripts)
export HOSTCC=/usr/bin/gcc
export HOSTCXX=/usr/bin/g++

# Target cross-compiler tools (Clang/LLVM)
export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip
export READELF=llvm-readelf

# Target config
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu
# IMPORTANT: empty CROSS_COMPILE prevents Makefile from looking for aarch64-linux-gnu-gcc
export CROSS_COMPILE=

echo "=== Kernel: $(head -1 $KERNEL_DIR/Makefile 2>/dev/null || echo 'NOT FOUND') ==="
cd "$KERNEL_DIR"

echo ""
echo "=== Step 1: Fix Makefile compat ==="
# Remove gcc-wrapper.py dependency
sed -i 's|^CC.*scripts/gcc-wrapper.py|CC = clang|' Makefile 2>/dev/null || true
# Remove REAL_CC
sed -i 's|^REAL_CC|#REAL_CC|' Makefile 2>/dev/null || true
# Fix lexer
for f in scripts/dtc/dtc-lexer.lex.c_shipped scripts/dtc/dtc-lexer.l; do
    [ -f "$f" ] && sed -i 's/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/' "$f" 2>/dev/null || true
done
# PERL
grep -q '^PERL' Makefile && sed -i 's|^PERL.*|PERL = perl|' Makefile

# Fix ln -> cp for Windows
sed -i 's|$(Q)ln -fsn $(srctree) source|$(Q)true # ln skipped|' Makefile

echo "CC = $(grep '^CC' Makefile | head -1)"
echo "HOSTCC = $(grep '^HOSTCC' Makefile | head -1)"

echo ""
echo "=== Step 2: Clean ==="
rm -rf out

echo ""
echo "=== Step 3: Config ==="
make O=out ARCH=arm64 raphael_user_defconfig
cd out

# Disable module signing and debug info (faster build)
sed -i 's/CONFIG_MODULE_SIG=.*/CONFIG_MODULE_SIG=n/' .config 2>/dev/null || true
sed -i 's/CONFIG_DEBUG_INFO=.*/CONFIG_DEBUG_INFO=n/' .config 2>/dev/null || true
grep -q "CONFIG_MODULE_SIG" .config || echo "CONFIG_MODULE_SIG=n" >> .config
grep -q "CONFIG_DEBUG_INFO" .config || echo "CONFIG_DEBUG_INFO=n" >> .config

make O=out olddefconfig 2>&1 | tail -5 || {
    echo "olddefconfig failed, trying oldconfig with defaults..."
    yes "" | make O=out oldconfig 2>/dev/null || true
}

echo "=== Config done ==="
cd ..

echo ""
echo "=== Step 4: Build ($(nproc) jobs) ==="
make O=out Image -j$(nproc) 2>&1 | tee out/build.log
BUILD_RESULT=${PIPESTATUS[0]}

if [ "$BUILD_RESULT" -eq 0 ] && [ -f out/arch/arm64/boot/Image ]; then
    echo ""
    echo "========================================="
    echo " BUILD SUCCESS"
    echo "========================================="
    ls -la out/arch/arm64/boot/Image*
    cp out/arch/arm64/boot/Image Image
    gzip -f -9 Image
    ls -la Image.gz
    echo ""
    echo "Output: $KERNEL_DIR/Image.gz"
else
    echo ""
    echo "========================================="
    echo " BUILD FAILED (exit: $BUILD_RESULT)"
    echo "========================================="
    grep -i "error:" out/build.log | tail -30 || true
    exit 1
fi
