#!/bin/bash

#
# edk2-build.sh: evolution of uefi-build.sh for edk2-platforms
#
# Copyright (c) 2012-2019, Linaro Ltd. All rights reserved.
# Copyright (c) 2020, Ampere Computing LLC. All rights reserved.
#
# SPDX-License-Identifier: ISC
#

unset MAKEFLAGS  # BaseTools not safe to build parallel, prevent env overrides

TOOLS_DIR="`dirname $0`"
TOOLS_DIR="`readlink -f \"$TOOLS_DIR\"`"
export TOOLS_DIR
export PATH=$TOOLS_DIR/toolchain/iasl:$TOOLS_DIR/toolchain/atf-tools:$TOOLS_DIR/toolchain/ampere/bin:$PATH
export AMPERE_CROSS_COMPILE=aarch64-ampere-linux-gnu-

. "$TOOLS_DIR"/common-functions
PLATFORM_CONFIG="-c $TOOLS_DIR/edk2-platforms.config"
ARCH=
VERBOSE=0                  # Override with -v
STRICT=0                   # Override with --strict
ATF_DIR=
ATF_IMAGE=
LINUXBOOT=0
LINUXBOOT_FMT=
TOS_DIR=
TOOLCHAIN="gcc"            # Override with -T
WORKSPACE=
EDK2_DIR=
PLATFORMS_DIR=
MAINBOARDS_DIR=
BOARD_SETTING=
CLEAN=0
NON_OSI_DIR=
IMPORT_OPENSSL=FALSE
OPENSSL_CONFIGURED=FALSE
VER=
BUILD=
BUILD_DATE="`date +%Y%m%d`"
DEST_DIR=

# Number of threads to use for build
export NUM_THREADS=$((`getconf _NPROCESSORS_ONLN` + `getconf _NPROCESSORS_ONLN`))

function get_platform_version
{
    if [ -d "${PLATFORMS_DIR}/.git" ]; then
        PLATFORM_VER="`cd ${PLATFORMS_DIR} && git describe --tags --dirty --long | grep ampere | grep -v dirty | cut -d \- -f 1 | cut -d \v -f 2`"
        # cd ${WORKSPACE}
        if [ X"$PLATFORM_VER" != X"" ]; then
            echo $PLATFORM_VER
            return 0
        fi
    fi
    PLATFORM_VER="0.00.100"
    # default version 0.00.100
    echo $PLATFORM_VER
}

function build_tianocore_atf
{
    WS_BOARD="$WORKSPACE/Build/${board}"
    PLATFORM_LOWER="${board,,}"
    BUILD_TYPE="_${target,,}"
    if [ X"$target" != X"DEBUG" ]; then
        BUILD_TYPE=
    fi
    if [ $LINUXBOOT -eq 1 ]; then
        LINUXBOOT_FMT="_linuxboot"
    fi
    if [ X"$DEST_DIR" == X"" ]; then
        DEST_DIR="BUILDS/${PLATFORM_LOWER}_tianocore_atf${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}"
    fi
    mkdir -p ${DEST_DIR}
    UEFI_BIN="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o uefi_bin`"
    cp -a $WS_BOARD/${target}_${PLATFORM_TOOLCHAIN}/FV/${UEFI_BIN}  $DEST_DIR/${PLATFORM_LOWER}_tianocore${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.fd
    if [ X"$ATF_IMAGE" != X"" ]; then
        PLATFORM_PATH=${PLATFORMS_DIR}/"`dirname $PLATFORM_DSC`"
        if [ X"$BOARD_SETTING" == X"" ]; then
            BOARD_SETTING=$PLATFORM_PATH/${PLATFORM_LOWER}_board_setting.txt
        fi
        cert_create -n --ntfw-nvctr 0 --key-alg rsa --nt-fw-key $PLATFORM_PATH/TestKeys/Dbb_AmpereTest.priv.pem --nt-fw-cert $DEST_DIR/${PLATFORM_LOWER}_tianocore${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.fd.crt --nt-fw $DEST_DIR/${PLATFORM_LOWER}_tianocore${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.fd
        fiptool create --nt-fw-cert $DEST_DIR/${PLATFORM_LOWER}_tianocore${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.fd.crt --nt-fw $DEST_DIR/${PLATFORM_LOWER}_tianocore${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.fd $DEST_DIR/${PLATFORM_LOWER}_tianocore${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.fip.signed
        if [ "${BOARD_SETTING##*.}" = "txt" ]; then
            cp -a $BOARD_SETTING $DEST_DIR/${PLATFORM_LOWER}_board_setting.txt
            python $TOOLS_DIR/nvparam.py -f $DEST_DIR/${PLATFORM_LOWER}_board_setting.txt -o $DEST_DIR/${PLATFORM_LOWER}_board_setting.bin
        fi
        if [ "${BOARD_SETTING##*.}" = "bin" ]; then
            cp -a $BOARD_SETTING $DEST_DIR/${PLATFORM_LOWER}_board_setting.bin
        fi
        dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > $DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.img
        dd bs=1 conv=notrunc if=${ATF_IMAGE} of=$DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.img
        dd bs=1 seek=2031616 conv=notrunc if=$DEST_DIR/${PLATFORM_LOWER}_board_setting.bin of=$DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.img
        dd bs=1024 seek=2048 if=$DEST_DIR/${PLATFORM_LOWER}_tianocore${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.fip.signed of=$DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${LINUXBOOT_FMT}${BUILD_TYPE}_${VER}.${BUILD}.img
        if [ $LINUXBOOT -eq 0 ]; then
            CAPSULE_DSC="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o capsule_dsc`"
            openssl dgst -sha256 -sign  $PLATFORM_PATH/TestKeys/Dbu_AmpereTest.priv.pem -out $DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${BUILD_TYPE}_${VER}.${BUILD}.img.sig $DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${BUILD_TYPE}_${VER}.${BUILD}.img
            cat $DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${BUILD_TYPE}_${VER}.${BUILD}.img.sig $DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${BUILD_TYPE}_${VER}.${BUILD}.img > $WS_BOARD/${target}_${PLATFORM_TOOLCHAIN}/${PLATFORM_LOWER}_tianocore_atf.img.signed
            # support 1.01 tag
            ln -sf $WS_BOARD/${target}_${PLATFORM_TOOLCHAIN}/${PLATFORM_LOWER}_tianocore_atf.img.signed $WS_BOARD/${PLATFORM_LOWER}_atfedk2.img.signed
            build -n $NUM_THREADS -a "$PLATFORM_ARCH" -t ${PLATFORM_TOOLCHAIN} -p "$CAPSULE_DSC" -b "$target" ${PLATFORM_BUILDFLAGS} -D FIRMWARE_VER="${VER}.${BUILD} Build ${BUILD_DATE}" \
                -D UEFI_ATF_IMAGE=$WS_BOARD/${target}_${PLATFORM_TOOLCHAIN}/${PLATFORM_LOWER}_tianocore_atf.img.signed
            cp $WS_BOARD/${target}_${PLATFORM_TOOLCHAIN}/FV/JADEFIRMWAREUPDATECAPSULEFMPPKCS7.Cap $DEST_DIR/${PLATFORM_LOWER}_tianocore_atf${BUILD_TYPE}_${VER}.${BUILD}.cap
        fi
        rm -fr $DEST_DIR/*.img.signed $DEST_DIR/*.img.sig $DEST_DIR/*.bin.padded $DEST_DIR/*.fd.crt $DEST_DIR/*.fip.signed
    fi
    echo "Results: `readlink -f $DEST_DIR`"
    if which tree >/dev/null 2>&1; then
        tree -h $DEST_DIR
    else
        ls -l $DEST_DIR
    fi
}

function do_build
{
    PLATFORM_ARCH=`echo $board | cut -s -d: -f2`
    if [ -n "$PLATFORM_ARCH" ]; then
        board=`echo $board | cut -d: -f1`
    else
        PLATFORM_ARCH="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o arch`"
    fi
    PLATFORM_NAME="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o longname` ($PLATFORM_ARCH)"
    if [ -z "$PLATFORM_ARCH" ]; then
        echo "Unknown target architecture - aborting!" >&2
        return 1
    fi
    PLATFORM_VER=`get_platform_version`
    MAJOR_VER="`echo ${PLATFORM_VER} | cut -d \. -f 1`"
    MINOR_VER="`echo ${PLATFORM_VER} | cut -d \. -f 2`"
    if [ -z "$VER" ]; then
        VER=${MAJOR_VER}.${MINOR_VER}
    else
        MAJOR_VER="`echo ${VER} | cut -d \. -f 1`"
        MINOR_VER="`echo ${VER} | cut -d \. -f 2`"
    fi
    if [ -z "$BUILD" ]; then
        BUILD="`echo ${PLATFORM_VER} | cut -d \. -f 3`"
        if [ -z "$BUILD" ]; then
            BUILD=100
        fi
    fi
    if [[ "${EXTRA_OPTIONS[@]}" != *"MAJOR_VER"* ]]; then
        EXTRA_OPTIONS=( ${EXTRA_OPTIONS[@]} "-D" MAJOR_VER=$MAJOR_VER )
    fi
    if [[ "${EXTRA_OPTIONS[@]}" != *"MINOR_VER"* ]]; then
        EXTRA_OPTIONS=( ${EXTRA_OPTIONS[@]} "-D" MINOR_VER=$MINOR_VER )
    fi
    PLATFORM_PREBUILD_CMDS="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o prebuild_cmds`"
    PLATFORM_BUILDFLAGS="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o buildflags`"
    PLATFORM_BUILDFLAGS="$PLATFORM_BUILDFLAGS ${EXTRA_OPTIONS[@]}"
    PLATFORM_BUILDCMD="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o buildcmd`"
    PLATFORM_DSC="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o dsc`"
    if [ $LINUXBOOT -eq 1 ]; then
        PLATFORM_DSC="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o linuxboot_dsc`"
        if [ ! -e "${PLATFORMS_DIR}/${PLATFORM_DSC}" ]; then
            TMP_DSC="`dirname $PLATFORM_DSC`"/${board}Linuxboot.dsc
            if [ -e "${PLATFORMS_DIR}/${TMP_DSC}" ]; then
                PLATFORM_DSC=${TMP_DSC}
            fi
        fi
    fi
    PLATFORM_PACKAGES_PATH=""
    COMPONENT_INF="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o inf`"

    TEMP_PACKAGES_PATH="$GLOBAL_PACKAGES_PATH:`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o packages_path`"
    IFS=:
    for path in "$TEMP_PACKAGES_PATH"; do
        case "$path" in
            /*)
                PLATFORM_PACKAGES_PATH="$PLATFORM_PACKAGES_PATH:$path"
            ;;
            *)
                PLATFORM_PACKAGES_PATH="$PLATFORM_PACKAGES_PATH:$PWD/$path"
            ;;
            esac
    done
    unset IFS

    if [ $VERBOSE -eq 1 ]; then
        echo "Setting build parallellism to $NUM_THREADS processes"
        echo "PLATFORM_NAME=$PLATFORM_NAME"
        echo "PLATFORM_VER=$PLATFORM_VER"
        echo "PLATFORM_PREBUILD_CMDS=$PLATFORM_PREBUILD_CMDS"
        echo "PLATFORM_BUILDFLAGS=$PLATFORM_BUILDFLAGS"
        echo "PLATFORM_BUILDCMD=$PLATFORM_BUILDCMD"
        echo "PLATFORM_DSC=$PLATFORM_DSC"
        echo "PLATFORM_ARCH=$PLATFORM_ARCH"
        echo "PLATFORM_PACKAGES_PATH=$PLATFORM_PACKAGES_PATH"
    fi

    set_cross_compile
    CROSS_COMPILE="$TEMP_CROSS_COMPILE"

    echo "Building $PLATFORM_NAME - $PLATFORM_ARCH"
    echo "CROSS_COMPILE=\"$TEMP_CROSS_COMPILE\""
    echo "$board"_BUILDFLAGS="'$PLATFORM_BUILDFLAGS'"

    if [ "$TARGETS" == "" ]; then
        TARGETS=( RELEASE )
    fi

    case $TOOLCHAIN in
        "gcc")
            PLATFORM_TOOLCHAIN=`get_gcc_version "$CROSS_COMPILE"gcc`
            ;;
        "clang")
            PLATFORM_TOOLCHAIN=`get_clang_version clang`
            ;;
        *)
            # Use command-line specified profile directly
            PLATFORM_TOOLCHAIN=$TOOLCHAIN
            ;;
    esac
    echo "PLATFORM_TOOLCHAIN is ${PLATFORM_TOOLCHAIN}"

    export ${PLATFORM_TOOLCHAIN}_${PLATFORM_ARCH}_PREFIX=$CROSS_COMPILE
    if [ $TOOLCHAIN != "clang" ]; then
        export ${PLATFORM_TOOLCHAIN}_BIN=$CROSS_COMPILE
    fi
    echo "Toolchain prefix: ${PLATFORM_TOOLCHAIN}_${PLATFORM_ARCH}_PREFIX=$CROSS_COMPILE"
    export PACKAGES_PATH="$PLATFORM_PACKAGES_PATH"
    if [ $LINUXBOOT -eq 1 ]; then
        if [ -e ${LINUXBOOT_BIN} ]; then
            cp -f ${LINUXBOOT_BIN} ${PLATFORMS_DIR}/Platform/Ampere/LinuxBootPkg/AArch64/flashkernel
        fi
    fi
    for target in "${TARGETS[@]}" ; do
        if [ X"$PLATFORM_PREBUILD_CMDS" != X"" ]; then
            echo "Run pre-build commands:"
            if [ $VERBOSE -eq 1 ]; then
                echo "  ${PLATFORM_PREBUILD_CMDS}"
            fi
            eval ${PLATFORM_PREBUILD_CMDS}
        fi

        if [ -n "$COMPONENT_INF" ]; then
            # Build a standalone component
            if [ $VERBOSE -eq 1 ]; then
                echo "build -n $NUM_THREADS -a \"$PLATFORM_ARCH\" -t ${PLATFORM_TOOLCHAIN} -p \"$PLATFORM_DSC\"" \
                    "-m \"$COMPONENT_INF\" -b "$target" ${PLATFORM_BUILDFLAGS}"
            fi
            build -n $NUM_THREADS -a "$PLATFORM_ARCH" -t ${PLATFORM_TOOLCHAIN} -p "$PLATFORM_DSC" \
                -m "$COMPONENT_INF" -b "$target" ${PLATFORM_BUILDFLAGS}
        else
            # Build a platform
            if [ $VERBOSE -eq 1 ]; then
                echo "build -n $NUM_THREADS -a \"$PLATFORM_ARCH\" -t ${PLATFORM_TOOLCHAIN} -p \"$PLATFORM_DSC\"" \
                    "-b "$target" ${PLATFORM_BUILDFLAGS}"
            fi
            if [[ "${EXTRA_OPTIONS[@]}" != *"FIRMWARE_VER"* ]]; then
                build -n $NUM_THREADS -a "$PLATFORM_ARCH" -t ${PLATFORM_TOOLCHAIN} -p "$PLATFORM_DSC" \
                    -b "$target" ${PLATFORM_BUILDFLAGS} -D FIRMWARE_VER="${VER}.${BUILD} Build ${BUILD_DATE}"
            else
                build -n $NUM_THREADS -a "$PLATFORM_ARCH" -t ${PLATFORM_TOOLCHAIN} -p "$PLATFORM_DSC" \
                    -b "$target" ${PLATFORM_BUILDFLAGS}
            fi
        fi
        RESULT=$?
        if [ $RESULT -eq 0 ]; then
            build_tianocore_atf
        fi

        if [ $STRICT -eq 1 -a $RESULT -ne 0 ]; then
           echo "$PLATFORM_NAME:$target failed to build!"
           exit 1
        fi
        result_log $RESULT "$PLATFORM_NAME $target"
    done
    unset PACKAGES_PATH
}

function clean_all
{
    if [ $CLEAN -eq 1 ]; then
        echo "Cleaning Tianocore..."
        rm -fr $WORKSPACE/Build
        echo "Tianocore clean BaseTools..."
        make -C ${EDK2_DIR}/BaseTools clean
    fi
}

function configure_paths
{
    WORKSPACE="$PWD"

    # Check to see if we are in a UEFI repository
    # refuse to continue if we aren't
    if [ ! -d "$EDK2_DIR"/BaseTools ]
    then
        if [ -d "$PWD"/edk2/BaseTools ]; then
            EDK2_DIR="$PWD"/edk2
        else
            if [ X"$WORKSPACE" = X"$TOOLS_DIR" ]; then
                if [ -d "$PWD"/../edk2/BaseTools ]; then
                    EDK2_DIR="`readlink -f $PWD/../edk2`"
                elif [ -d "$TOOLS_DIR"/../edk2/BaseTools ]; then
                    EDK2_DIR="`readlink -f $TOOLS_DIR/../edk2`"
                else
                    EDK2_DIR=
                fi
            else
                EDK2_DIR=
            fi
            if [ X"$EDK2_DIR" = X"" ]; then
                echo "ERROR: can't locate the edk2 directory" >&2
                echo "       please specify -e/--edk2-dir" >&2
                exit 1
            fi
        fi
    fi

    GLOBAL_PACKAGES_PATH="$EDK2_DIR"

    # locate edk2-platforms
    if [ -z "$PLATFORMS_DIR" -a -d "$PWD"/edk2-platforms ]; then
        PLATFORMS_DIR="$PWD"/edk2-platforms
    fi
    if [ -z "$PLATFORMS_DIR" -a X"$WORKSPACE" = X"$TOOLS_DIR" ]; then
        if [ -d "$PWD"/../edk2-platforms ]; then
            PLATFORMS_DIR="`readlink -f $PWD/../edk2-platforms`"
        elif [ -d "$TOOLS_DIR"/../edk2-platforms ]; then
            PLATFORMS_DIR="`readlink -f $TOOLS_DIR/../edk2-platforms`"
        fi
    fi
    if [ -z "$PLATFORMS_DIR" ]; then
        echo "ERROR: can't locate the edk2-platform directory" >&2
        echo "       please specify -p/--platforms-dir" >&2
        exit 1
    fi
    if [ -n "$PLATFORMS_DIR" ]; then
        GLOBAL_PACKAGES_PATH="$GLOBAL_PACKAGES_PATH:$PLATFORMS_DIR"
    fi

    # locate edk2-non-osi
    if [ -z "$NON_OSI_DIR" -a -d "$PWD"/edk2-non-osi ]; then
        NON_OSI_DIR="$PWD"/edk2-non-osi
    fi
    if [ -z "$NON_OSI_DIR" -a -d "$PWD"/../edk2-non-osi ]; then
        NON_OSI_DIR="`readlink -f $PWD/../edk2-non-osi`"
    fi
    if [ -n "$NON_OSI_DIR" ]; then
        GLOBAL_PACKAGES_PATH="$GLOBAL_PACKAGES_PATH:$NON_OSI_DIR"
    fi

    # locate arm-trusted-firmware
    if [ -z "$ATF_DIR" -a -d "$PWD"/arm-trusted-firmware ]; then
        ATF_DIR="$PWD"/arm-trusted-firmware
    fi

    export WORKSPACE
}


function prepare_build
{
    get_build_arch
    export ARCH=$BUILD_ARCH

    export ARCH
    cd $EDK2_DIR
    PACKAGES_PATH=$GLOBAL_PACKAGES_PATH . edksetup.sh --reconfig
    if [ $? -ne 0 ]; then
        echo "Sourcing edksetup.sh failed!" >&2
        exit 1
    fi
    if [ $VERBOSE -eq 1 ]; then
        echo "Building BaseTools"
    fi
    make -C BaseTools -j $NUM_THREADS
    RET=$?
    cd $WORKSPACE
    if [ $RET -ne 0 ]; then
        echo " !!! BaseTools failed to build !!! " >&2
        exit 1
    fi

    if [ "$IMPORT_OPENSSL" = "TRUE" ]; then
        cd $EDK2_DIR
        import_openssl
        if [ $? -ne 0 ]; then
            echo "Importing OpenSSL failed - aborting!" >&2
            echo "  specify --no-openssl to attempt build anyway." >&2
            exit 1
        fi
        cd $WORKSPACE
    fi
}

function check_tools
{
    PLATFORM_ARCH=`echo $board | cut -s -d: -f2`
    if [ -n "$PLATFORM_ARCH" ]; then
        board=`echo $board | cut -d: -f1`
    else
        PLATFORM_ARCH="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o arch`"
    fi
    echo $builds
    echo "PATH: $PATH"
    if [[ ! " ${builds[@]} " =~ " Jade " ]]; then
        echo "No Ampere Platforms, skip check tools."
        return 0
    fi
    echo "Checking Ampere Toolchain..."
    get_build_arch
    echo "Target: $PLATFORM_ARCH"
    echo "Build: $BUILD_ARCH"
    if [ "$PLATFORM_ARCH" = "$BUILD_ARCH" ]; then
        CROSS_COMPILE=
    elif [ -z "$CROSS_COMPILE" ]; then
        CROSS_COMPILE=${AMPERE_CROSS_COMPILE}
    fi
    if [ "$CROSS_COMPILE" = "$AMPERE_CROSS_COMPILE" ]; then
        check_ampere_toolchain ${TOOLS_DIR} "$CROSS_COMPILE"gcc
    fi
    RET=$?
    if [ $RET -ne 0 ]; then
        exit 1
    fi
    if [ "$PLATFORM_ARCH" != "$BUILD_ARCH" ]; then
        export GCC5_AARCH64_PREFIX="`${CROSS_COMPILE}gcc -dumpmachine`"
    fi
    echo "Checking iasl..."
    check_iasl_tool ${TOOLS_DIR}
    RET=$?
    if [ $RET -ne 0 ]; then
        exit 1
    fi
    echo "Checking atf-tools..."
    check_atf_tool ${TOOLS_DIR}
    RET=$?
    if [ $RET -ne 0 ]; then
        exit 1
    fi
}

function usage
{
    echo "usage:"
    echo -n "edk2-build.sh [-b DEBUG | RELEASE] [--atf-image <Ampere_ATF_Image>] [--board-setting <board_setting.txt/.bin>] [ all "
    for board in "${boards[@]}" ; do
        echo -n "| $board "
    done
    echo "]"
    printf "%8s\tbuild %s\n" "all" "all supported platforms"
    for board in "${boards[@]}" ; do
        PLATFORM_NAME="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG -p $board get -o longname`"
        printf "%8s\tbuild %s\n" "$board" "${PLATFORM_NAME}"
    done
}



#
# Since we do a command line validation on whether specified platforms exist or
# not, do a first pass of command line to see if there is an explicit config
# file there to read valid platforms from.
#
commandline=( "$@" )
i=0
for arg;
do
    if [ $arg == "-c" ]; then
        FILE_ARG=${commandline[i + 1]}
        if [ ! -f "$FILE_ARG" ]; then
            echo "ERROR: configuration file '$FILE_ARG' not found" >&2
            exit 1
        fi
        case "$FILE_ARG" in
            /*)
                PLATFORM_CONFIG="-c $FILE_ARG"
            ;;
            *)
                PLATFORM_CONFIG="-c `readlink -f \"$FILE_ARG\"`"
            ;;
        esac
        echo "Platform config file: '$FILE_ARG'"
    fi
    i=$(($i + 1))
done

export PLATFORM_CONFIG

builds=()
boards=()
boardlist="`$TOOLS_DIR/parse-platforms.py $PLATFORM_CONFIG shortlist`"
for board in $boardlist; do
    boards=(${boards[@]} $board)
done

NUM_TARGETS=0

while [ "$1" != "" ]; do
    case $1 in
        -1)     # Disable build parallellism
            NUM_THREADS=1
            ;;
        -c)     # Already parsed above - skip this + option
            shift
            ;;
        -b | --build-target)
            shift
            echo "Adding Build target: $1"
            TARGETS=(${TARGETS[@]} $1)
            ;;
        -D)     # Pass through as -D option to 'build'
            shift
            echo "Adding Macro: -D $1"
            EXTRA_OPTIONS=(${EXTRA_OPTIONS[@]} "-D" $1)
            ;;
        -e | --edk2-dir)
            shift
            export EDK2_DIR="`readlink -f $1`"
            ;;
        -h | --help)
            usage
            exit
            ;;
        --import-openssl)
            IMPORT_OPENSSL=TRUE
            ;;
        -n | --non-osi-dir)
            shift
            NON_OSI_DIR="`readlink -f $1`"
            ;;
        -p | --platforms-dir)
            shift
            PLATFORMS_DIR="`readlink -f $1`"
            ;;
        --board-setting)
            shift
            BOARD_SETTING="`readlink -f $1`"
            ;;
        --strict) # Exit if any platform/target fails to build
            STRICT=1
            ;;
        --linuxboot)
            LINUXBOOT=1
            ;;
        --linuxboot-bin) # linux binary from https://github.com/linuxboot/mainboards.git
            shift
            LINUXBOOT=1
            LINUXBOOT_BIN="`readlink -f $1`"
            if [ ! -e "${LINUXBOOT_BIN}" ]; then
                echo "ERROR: LinuxBoot file '$LINUXBOOT_BIN' not found" >&2
                exit 1
            fi
            ;;
        --ver) # MANOR_VER. MAJOR_VER: 1.01
            shift
            VER=$1
            ;;
        --build) # BuildID: YYYYMMDD
            shift
            BUILD=$1
            ;;
        --dest-dir)
            shift
            DEST_DIR="`readlink -f $1`"
            ;;
        --atf-image) # ampere atf image
            shift
            ATF_IMAGE="`readlink -f $1`"
            if [ ! -e "${ATF_IMAGE}" ]; then
                echo "ERROR: ATF SLIM file '$ATF_IMAGE' not found" >&2
                exit 1
            fi
            ;;
        -T)     # Set specific toolchain tag, or clang/gcc for autoselection
            shift
            echo "Setting toolchain tag to '$1'"
            TOOLCHAIN="$1"
            ;;
        -v)
            VERBOSE=1
            ;;
        --clean) # Enable CLEAN before compile: clean BaseTools and rm WORKSPACE/Build
            CLEAN=1
            ;;
        all)    # Add all targets in configuration file to list
            builds=(${boards[@]})
            NUM_TARGETS=$(($NUM_TARGETS + 1))
            ;;
        *)      # Try to match target in configuration file, add to list
            MATCH=0
            for board in "${boards[@]}" ; do
                if [ "`echo $1 | cut -d: -f1`" == $board ]; then
                    MATCH=1
                    builds=(${builds[@]} "$1")
                    break
                fi
            done
            if [ $MATCH -eq 0 ]; then
                echo "unknown arg $1"
                usage
                exit 1
            fi
            NUM_TARGETS=$(($NUM_TARGETS + 1))
            ;;
    esac
    shift
done

if [ $NUM_TARGETS -le  0 ]; then
    echo "No targets specified - exiting!" >&2
    exit 0
fi

export VERBOSE

configure_paths

check_tools

clean_all

prepare_build

for board in "${builds[@]}" ; do
    do_build
done

result_print
