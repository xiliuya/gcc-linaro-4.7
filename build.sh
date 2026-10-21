#!/usr/bin/env bash
set -euo pipefail

# 默认参数（支持通过命令行覆盖）
HOST="aarch64-linux-gnu"
TARGET="arm-linux-gnueabi"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host=*)
            HOST="${1#*=}"
            shift
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --target=*)
            TARGET="${1#*=}"
            shift
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --host=<host>        Specify host (default: aarch64-linux-gnu)"
            echo "  --target=<target>    Specify target (default: arm-linux-gnueabi)"
            echo "  -h, --help           Display this help message"
            exit 0
            ;;
        *)
            echo "Error: Unknown parameter: $1" >&2
            exit 1
            ;;
    esac
done

WORK_DIR="$(pwd)"
BUILD_DIR="build_${TARGET}"
SYSROOT_DIR="/usr/${TARGET}"
LOCAL_SYSROOT="$WORK_DIR/install/${TARGET}"

echo "=========================================="
echo " Host:           $HOST"
echo " Target:         $TARGET"
echo " Source Sysroot: $SYSROOT_DIR"
echo " Local Sysroot:  $LOCAL_SYSROOT"
echo " Install Path:   $WORK_DIR/install"
echo "=========================================="

# 创建安装目录
mkdir -p "$WORK_DIR/install"

# 1. 复制系统的 target sysroot 到 install 目录
if [ -d "$SYSROOT_DIR" ]; then
    echo "Copying sysroot from $SYSROOT_DIR to $LOCAL_SYSROOT..."
    mkdir -p "$LOCAL_SYSROOT"
    cp -a "$SYSROOT_DIR/." "$LOCAL_SYSROOT/"
    sed -i 's|/usr/'"${TARGET}"'/lib/||g' "$LOCAL_SYSROOT/lib/libc.so"
else
    echo "Error: Source sysroot directory $SYSROOT_DIR does not exist!" >&2
    exit 1
fi

# 2. 下载并编译 binutils-2.24
BINUTILS_VERSION="2.24"
BINUTILS_TAR="binutils-${BINUTILS_VERSION}.tar.bz2"
BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/$BINUTILS_TAR"

echo "Checking / Downloading Binutils ${BINUTILS_VERSION}..."
if [ ! -f "$BINUTILS_TAR" ]; then
    if command -v wget &> /dev/null; then
        wget "$BINUTILS_URL"
    elif command -v curl &> /dev/null; then
        curl -O "$BINUTILS_URL"
    else
        echo "Error: Neither wget nor curl is available to download binutils." >&2
        exit 1
    fi
fi

if [ ! -d "binutils-${BINUTILS_VERSION}" ]; then
    echo "Extracting binutils..."
    tar -xjf "$BINUTILS_TAR"
fi

echo "Building and installing Binutils..."
mkdir -p "build_binutils"
cd "build_binutils"
../binutils-${BINUTILS_VERSION}/configure \
    --prefix="$WORK_DIR/install" \
    --host="$HOST" \
    --target="$TARGET" \
    --with-sysroot='${prefix}/'${TARGET} \
    --disable-nls \
    --disable-werror

make -j"$(nproc)"
make install
cd ..

# 将新编译好的 binutils 路径加入环境变量，确保 GCC 编译时能找到对应的汇编器/链接器
export PATH="$WORK_DIR/install/bin:$PATH"

# 3. 编译与安装 GCC
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 动态组装 configure 参数
# 注意：通过使用 '$${prefix}' 配合 --with-sysroot 和 --with-build-sysroot，
# 可以让 GCC 在构建时使用本地绝对路径（$LOCAL_SYSROOT），而在安装后变成可重定向的相对路径。
CONFIGURE_ARGS=(
    --prefix="$WORK_DIR/install"
    --host="$HOST"
    --target="$TARGET"
    --enable-languages=c,c++
    --enable-multilib
    --enable-static
    --disable-shared
    --with-sysroot='${prefix}/'${TARGET} \
    --with-build-sysroot="$LOCAL_SYSROOT" \
    --with-native-system-header-dir=/include
    --with-arch=armv7-a        # 默认基础架构设为 armv7-a
    --with-tune=cortex-a9      # 针对常见 ARM 核心调优
    --disable-libquadmath
    --disable-libssp
    --disable-libmudflap
    --disable-libgomp
    --disable-libitm
    --disable-libatomic
    --disable-libstdcxx-pch
    --disable-libffi
    --disable-libjava
    --disable-libobjc
)

# 如果是 hardfloat 目标（gnueabihf），按需加上 --with-float=hard
if [[ "$TARGET" == *gnueabihf* ]]; then
    CONFIGURE_ARGS+=(--with-float=hard)
fi

# 运行 configure
../configure "${CONFIGURE_ARGS[@]}"

# 编译与安装
make -j"$(nproc)"
make install || exit 1

echo "Build and installation of Binutils and GCC for $TARGET completed successfully!"
