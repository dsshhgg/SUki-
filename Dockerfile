FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    make flex bison bc libssl-dev clang lld \
    gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf \
    git curl python3 cpio kmod && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /src
CMD ["make", "O=out", "raphael_user_defconfig"]
