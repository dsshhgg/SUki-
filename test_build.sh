#!/bin/bash
set -e
export GIT_SSL_NO_VERIFY=true

KERNEL_DIR="$HOME/kernel_raphael"
REPO_URL="https://github.com/raphael-ubports/kernel_xiaomi_raphael_stock"
BRANCH="raphael-p-oss"

# Clang + LLD tools
export PATH="$PATH:/mingw64/bin"
export HOSTCC=gcc
export CC="ccache clang"
export LD=ld.lld
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu
export CROSS_COMPILE=aarch64-linux-gnu-
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip

echo "=== Step 1: Clone kernel ==="
if [ ! -d "$KERNEL_DIR" ]; then
    git clone --depth=1 --single-branch --branch "$BRANCH" "$REPO_URL" "$KERNEL_DIR"
fi
cd "$KERNEL_DIR"
echo "Kernel version:"
head -5 Makefile

echo ""
echo "=== Step 2: Fix compat ==="
for f in scripts/dtc/dtc-lexer.lex.c_shipped scripts/dtc/dtc-lexer.l; do
    [ -f "$f" ] && sed -i 's/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/' "$f"
done
sed -i 's|^REAL_CC|#REAL_CC|' Makefile
sed -i 's|^CC.*scripts/gcc-wrapper.py|CC = clang|' Makefile
grep -q '^PERL' Makefile && sed -i 's|^PERL.*|PERL = perl|' Makefile

echo ""
echo "=== Step 3: Configure ==="
make O=out raphael_user_defconfig
cd out
echo "CONFIG_DEBUG_INFO=n" >> .config
make olddefconfig
cd "$KERNEL_DIR"

echo ""
echo "=== Step 4: Build ==="
set -o pipefail
make O=out Image -j$(nproc) 2>&1 | tee out/build.log

if [ -f out/arch/arm64/boot/Image ]; then
    echo ""
    echo "SUCCESS! Vanilla kernel compiles."
    ls -la out/arch/arm64/boot/Image*
else
    echo ""
    echo "BUILD FAILED"
    grep -i "error:" out/build.log | tail -20 || true
    exit 1
fi
