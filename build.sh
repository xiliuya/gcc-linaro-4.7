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
            echo "  --host=<host>       Specify host (default: aarch64-linux-gnu)"
            echo "  --target=<target>   Specify target (default: arm-linux-gnueabi)"
            echo "  -h, --help          Display this help message"
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

echo "=========================================="
echo " Host:          $HOST"
echo " Target:        $TARGET"
echo " Sysroot:       $SYSROOT_DIR"
echo " Install Path:  $WORK_DIR/install"
echo "=========================================="

# 创建构建目录
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 动态组装 configure 参数
CONFIGURE_ARGS=(
    --prefix="$WORK_DIR/install"
    --host="$HOST"
    --target="$TARGET"
    --enable-languages=c
    --disable-multilib
    --enable-static
    --disable-shared
    --with-sysroot="$SYSROOT_DIR"
    --with-build-sysroot="$SYSROOT_DIR"
    --with-native-system-header-dir=/include
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
make install

echo "Build and installation for $TARGET completed successfully!"
