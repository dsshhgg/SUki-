#!/bin/bash
set -e
DOCKER="C:\Users\Administrator\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe"
KERNEL_DIR="C:\msys64\home\Administrator\kernel_raphael"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building Docker image ==="
"$DOCKER" build -t kernel-builder "$SCRIPT_DIR"

echo ""
echo "=== Building kernel ==="
"$DOCKER" run --rm \
    -v "$KERNEL_DIR:/src" \
    -w /src \
    kernel-builder \
    bash -c '
set -e
export ARCH=arm64
export CC="ccache clang" 
export LD=ld.lld
export CLANG_TRIPLE=aarch64-linux-gnu
export CROSS_COMPILE=aarch64-linux-gnu-
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip

echo "=== Fix compat ==="
for f in scripts/dtc/dtc-lexer.lex.c_shipped scripts/dtc/dtc-lexer.l; do
    [ -f "$f" ] && sed -i "s/^YYLTYPE yylloc;/extern YYLTYPE yylloc;/" "$f"
done
sed -i "s|^REAL_CC|#REAL_CC|" Makefile
sed -i "s|^CC.*scripts/gcc-wrapper.py|CC = clang|" Makefile
grep -q "^PERL" Makefile && sed -i "s|^PERL.*|PERL = perl|" Makefile

echo "=== Integrate ReSukiSU ==="
if [ ! -d "KernelSU" ]; then
    git clone --depth=1 https://github.com/ReSukiSU/ReSukiSU KernelSU 2>/dev/null || true
fi

if [ -d "KernelSU/kernel" ]; then
    ln -sf "$(realpath --relative-to=drivers KernelSU/kernel)" drivers/kernelsu 2>/dev/null || \
    ln -sf "$(pwd)/KernelSU/kernel" drivers/kernelsu
    grep -q "kernelsu" drivers/Makefile || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> drivers/Makefile
    grep -q "kernelsu" drivers/Kconfig || sed -i "/^endmenu/i source \"drivers/kernelsu/Kconfig\"" drivers/Kconfig
    sed -i "s|MODULE_IMPORT_NS|//MODULE_IMPORT_NS|g" drivers/kernelsu/ksu.c 2>/dev/null || true
    sed -i "1s/^/#define fallthrough do {} while (0)\n/" drivers/kernelsu/allowlist.c 2>/dev/null || true
    echo "[+] ReSukiSU integrated"
fi

echo "=== Apply hooks ==="
if [ -f hooks.py ]; then
    python3 hooks.py
else
    echo "[!] hooks.py not found, skipping"
fi

echo "=== Configure ==="
make O=out raphael_user_defconfig
cd out
echo "CONFIG_DEBUG_INFO=n" >> .config
grep -q "CONFIG_KSU" .config || echo "CONFIG_KSU=y" >> .config
grep -q "CONFIG_KSU_MANUAL_HOOK" .config || echo "CONFIG_KSU_MANUAL_HOOK=y" >> .config
grep -q "CONFIG_OVERLAY_FS" .config || echo "CONFIG_OVERLAY_FS=y" >> .config
grep -q "CONFIG_KALLSYMS_ALL" .config || echo "CONFIG_KALLSYMS_ALL=y" >> .config
grep -q "CONFIG_KALLSYMS=y" .config || echo "CONFIG_KALLSYMS=y" >> .config
make olddefconfig
echo "=== KSU config ==="
grep -iE "ksu|kallsyms|overlay" .config || true
cd ..

echo "=== Build ==="
set -o pipefail
make O=out Image -j$(nproc) LD=ld.lld 2>&1 | tee out/build.log

if [ -f out/arch/arm64/boot/Image ]; then
    echo ""
    echo "SUCCESS!"
    ls -la out/arch/arm64/boot/Image*
    strings out/arch/arm64/boot/Image | grep -ic "kernelsu\|ksu_" | xargs echo "KSU symbols:"
    cp out/arch/arm64/boot/Image /src/Image
    gzip -f -9 /src/Image
    ls -la /src/Image.gz
else
    echo ""
    echo "BUILD FAILED"
    grep -i "error:" out/build.log | tail -20
    exit 1
fi
'
