#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export GIT_SSL_NO_VERIFY=true

# === CONFIG ===
KERNEL_DIR="$HOME/kernel_raphael"
OUT_DIR="$KERNEL_DIR/out"
REPO_URL="https://github.com/raphael-ubports/kernel_xiaomi_raphael_stock"
BRANCH="raphael-p-oss"

# === TOOLS ===
# Clang + LLD from MSYS2 (mingw-w64-x86_64-llvm)
export CC=clang
export LD=ld.lld
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu
# Use llvm tools instead of aarch64-linux-gnu- prefixed GNU tools
export CROSS_COMPILE=aarch64-linux-gnu-
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export READELF=llvm-readelf

echo "=== Step 1: Clone kernel source ==="
if [ ! -d "$KERNEL_DIR" ]; then
    git clone --depth=1 --single-branch --branch "$BRANCH" "$REPO_URL" "$KERNEL_DIR"
else
    echo "Kernel source already exists at $KERNEL_DIR"
fi

cd "$KERNEL_DIR"
echo "Kernel version:"
head -5 Makefile

echo ""
echo "=== Step 2: Fix compatibility ==="
for f in scripts/dtc/dtc-lexer.lex.c_shipped scripts/dtc/dtc-lexer.l; do
    [ -f "$f" ] && sed -i 's/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/' "$f"
done
sed -i 's|^REAL_CC|#REAL_CC|' Makefile
sed -i 's|^CC.*scripts/gcc-wrapper.py|CC = clang|' Makefile
grep -q '^PERL' Makefile && sed -i 's|^PERL.*|PERL = perl|' Makefile
grep "^CC" Makefile | head -3 || true

echo ""
echo "=== Step 3: Integrate ReSukiSU ==="
if [ ! -d "KernelSU" ]; then
    git clone --depth=1 https://github.com/ReSukiSU/ReSukiSU KernelSU
fi

DRIVER_DIR="drivers"
ln -sf "$(realpath --relative-to="$DRIVER_DIR" "$(pwd)/KernelSU/kernel")" "$DRIVER_DIR/kernelsu"

grep -q "kernelsu" "$DRIVER_DIR/Makefile" || \
    printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_DIR/Makefile"

grep -q "kernelsu" "$DRIVER_DIR/Kconfig" || \
    sed -i '/^endmenu/i\source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"

sed -i 's|MODULE_IMPORT_NS|//MODULE_IMPORT_NS|g' "$DRIVER_DIR/kernelsu/ksu.c" 2>/dev/null || true
sed -i '1s/^/#define fallthrough do {} while (0)\n/' "$DRIVER_DIR/kernelsu/allowlist.c" 2>/dev/null || true

echo ""
echo "=== Step 4: Apply manual hooks ==="
cp "$SCRIPT_DIR/hooks.py" hooks.py
python hooks.py

echo ""
echo "=== Step 5: Configure kernel ==="
make O=out raphael_user_defconfig
cd out
sed -i 's/.*CONFIG_KSU.*/CONFIG_KSU=y/' .config 2>/dev/null || echo "CONFIG_KSU=y" >> .config
grep -q "CONFIG_KSU_MANUAL_HOOK" .config || echo "CONFIG_KSU_MANUAL_HOOK=y" >> .config
grep -q "CONFIG_OVERLAY_FS" .config || echo "CONFIG_OVERLAY_FS=y" >> .config
grep -q "CONFIG_KALLSYMS_ALL" .config || echo "CONFIG_KALLSYMS_ALL=y" >> .config
grep -q "CONFIG_KALLSYMS=y" .config || echo "CONFIG_KALLSYMS=y" >> .config
make olddefconfig
echo "=== KSU config ==="
grep -iE "ksu|kallsyms|overlay" .config

echo ""
echo "=== Step 6: Build kernel ==="
cd "$KERNEL_DIR"
set -o pipefail
make O=out Image -j$(nproc) 2>&1 | tee out/build.log
echo "===== RESULT ====="
if [ -f out/arch/arm64/boot/Image ]; then
    echo "BUILD SUCCESS"
    ls -la out/arch/arm64/boot/Image*
else
    echo "BUILD FAILED"
    grep -i "error:" out/build.log | tail -30 || true
    tail -50 out/build.log
    exit 1
fi

echo ""
echo "=== Step 7: Verify KSU symbols ==="
strings out/arch/arm64/boot/Image | grep -i "kernelsu\|ksu_" | head -20 || echo "NO KSU SYMBOLS!"
KSU_COUNT=$(strings out/arch/arm64/boot/Image | grep -ic "kernelsu\|ksu_" || true)
echo "KSU symbols found: $KSU_COUNT"

echo ""
echo "=== Step 8: Compress ==="
cp out/arch/arm64/boot/Image Image
gzip -f -9 Image
ls -la Image.gz
echo ""
echo "DONE: Image.gz ready at $KERNEL_DIR/Image.gz"
