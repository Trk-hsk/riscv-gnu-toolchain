#!/usr/bin/env bash

# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425#set--e--u--x--o-pipefail
set -o pipefail

MODE=${MODE:-newlib}
TARGET=${TARGET:-rv32imafdcbpv-ilp32d}
CI_COMMIT_SHORT_SHA=${CI_COMMIT_SHORT_SHA:-$(git rev-parse --short HEAD)}
REPODIR=${REPODIR:-$(pwd)}
INDOCKER=0

if [ -f "/.dockerenv" -o -f "/run/.containerenv" ] ; then
    echo "This is a docker environment"
    INDOCKER=1
    TARGET_PREFIX=${TARGET_PREFIX:-/opt/riscv}
    BUILD_ROOT=${BUILD_ROOT:-/builds}
else
    TARGET_PREFIX=${TARGET_PREFIX:-$REPODIR/riscv}
    BUILD_ROOT=${BUILD_ROOT:-$REPODIR/builds}
fi
TOOLCHAIN_TARGZ=${TOOLCHAIN_TARGZ:-$REPODIR/nuclei_${MODE}_${TARGET}_toolchain_${CI_COMMIT_SHORT_SHA}.tar.gz}

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

function describe_repo {
    local repodir=${1}
    local repodesc=${2:-gitrepo.txt}

    if [ -d ${repodir}/.git ] ; then
        pushd ${repodir}
        git describe  --always --abbrev=10 --dirty > ${repodesc}
        git log --oneline -1 >> ${repodesc}
        git submodule >> ${repodesc}
        popd
    else
        echo "not a git repo" > ${repodesc}
    fi
}

TARGET_TUPLE=($(echo ${TARGET} | tr "-" "\n"))
TARGET_CONF="--with-arch=${TARGET_TUPLE[0]} --with-abi=${TARGET_TUPLE[1]}"

echo "Build Target Configuration : $TARGET_CONF"
BUILD_OUTDIR=$BUILD_ROOT/$(date -u +"%Y-%m-%dT%H%M%S")
BUILD_LOG=$REPODIR/build.log
TOOLCHAIN_CONFIGURE=$REPODIR/configure

mkdir -p $BUILD_OUTDIR
pushd $BUILD_OUTDIR
echo "STEP 1: Do toolchain configuration"

if [ -d $TARGET_PREFIX ] ; then
    echo "STEP 1: Remove existing prebuilt toolchain"
    rm -rf $TARGET_PREFIX
    mkdir -p $TARGET_PREFIX
else
    mkdir -p $TARGET_PREFIX
fi
REPODESC=$TARGET_PREFIX/gitrepo.txt

describe_repo "$REPODIR" "$REPODESC"
$TOOLCHAIN_CONFIGURE --prefix=$TARGET_PREFIX $TARGET_CONF

echo "STEP 2: Build toolchain"
sed -i -e 's/make_tuple = riscv$(1)-unknown-$(2)/make_tuple = riscv-nuclei-$(2)/g' Makefile
make -j 4 ${MODE} 2>&1 | tee $BUILD_LOG | grep -E "/configure|stamps"
tail -n20 $BUILD_LOG
popd

echo "STEP 3: Strip toolchain"
strip_toolchain_lin $TARGET_PREFIX

echo "STEP 4: Archive toolchain"
tar --transform "s/^opt\///" -czf $TOOLCHAIN_TARGZ $TARGET_PREFIX