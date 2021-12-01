#!/usr/bin/env bash

# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425#set--e--u--x--o-pipefail
set -o pipefail

MODE=${MODE:-newlib}
TARGET=${TARGET:-rv32imafdcbpv-ilp32d}
TARGET_PREFIX=${TARGET_PREFIX:-/opt/riscv}
CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA:-$(git rev-parse --short HEAD)}

echo "Build Nuclei GNU Toolchain for ${MODE} - ${TARGET}"

function strip_toolchain_lin() {
    local tooldir=$1

    pushd $tooldir
    echo "Stripping toolchain in $tooldir"
    ostype=$(uname)
    if [ "$ostype" = "Darwin" ] ; then
       STRIP_CMD="strip"
    else
       STRIP_CMD="strip -s"
    fi
    set +e
    for file in `find libexec bin -type f`
    do
        $STRIP_CMD $file
    done
    popd
    set -e
}

TARGET_TUPLE=($(echo ${TARGET} | tr "-" "\n"))
TARGET_CONF="--with-arch=${TARGET_TUPLE[0]} --with-abi=${TARGET_TUPLE[1]}"

echo "Build Target Configuration : $TARGET_CONF"
BUILD_OUTDIR=/build/$(date -u +"%Y-%m-%dT%H%M%S")
# BUILD_OUTDIR=$(pwd)
BUILD_LOG=$(pwd)/build.log
TOOLCHAIN_CONFIGURE=$(pwd)/configure

mkdir -p $BUILD_OUTDIR
pushd $BUILD_OUTDIR
echo "STEP 1: Do toolchain configuration"

if [ -d $TARGET_PREFIX ] ; then
    echo "STEP 1: Remove existing prebuilt toolchain"
    rm -rf $TARGET_PREFIX
    mkdir -p $TARGET_PREFIX
fi

$TOOLCHAIN_CONFIGURE --prefix=$TARGET_PREFIX $TARGET_CONF

echo "STEP 2: Build toolchain"
sed -i -e 's/make_tuple = riscv$(1)-unknown-$(2)/make_tuple = riscv-nuclei-$(2)/g' Makefile
make -j 4 ${MODE} > $BUILD_LOG 2>&1
tail -n20 $BUILD_LOG
popd

echo "STEP 3: Strip toolchain"
strip_toolchain_lin $TARGET_PREFIX

echo "STEP 4: Archive toolchain"
TOOLCHAIN_TARGZ=nuclei_${MODE}_${TARGET}_toolchain_${CI_COMMIT_SHORT_SHA}.tar.gz
tar --transform "s/^opt\///" -czf $TOOLCHAIN_TARGZ $TARGET_PREFIX