#!/bin/bash

# @file
#
# Copyright (c) 2020, Ampere Computing LLC. All rights reserved.<BR>
#
# SPDX-License-Identifier: ISC
#
# LinuxBoot Binary Build
#
TOOLS_DIR="`dirname $0`"
TOOLS_DIR="`readlink -f \"$TOOLS_DIR\"`"
export TOOLS_DIR

. "$TOOLS_DIR"/common-functions

PLATFORM_LOWER="jade"

check_golang
export GOPATH=${TOOLS_DIR}/toolchain/gosource
mkdir -p ${GOPATH}
export PATH=${GOPATH}/bin:${TOOLS_DIR}/toolchain/go/bin:$PATH

MAINBOARDS_DIR="`readlink -f $PWD/mainboards`"
if [ ! -d "$MAINBOARDS_DIR" ]; then
    git clone --branch master https://github.com/linuxboot/mainboards.git
fi
check_lzma_tool ${TOOLS_DIR}
RESULT=$?
if [ $RESULT -ne 0 ]; then
    exit 1
fi
echo "Clean up LinuxBoot binaries..."
rm -rf ${MAINBOARDS_DIR}/mainboards/ampere/${PLATFORM_LOWER}/{flashkernel,flashinitramfs.*}
if [ -d ${MAINBOARDS_DIR}/mainboards/ampere/${PLATFORM_LOWER}/linux ]; then
    $(MAKE) -C ${MAINBOARDS_DIR}/mainboards/ampere/${PLATFORM_LOWER}/linux && distclean
fi
make -C $MAINBOARDS_DIR/ampere/${PLATFORM_LOWER} fetch flashkernel ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE}
RESULT=$?
if [ $RESULT -ne 0 ]; then
    echo "ERROR: compile LinuxBoot binaries issue" >&2
    exit 1
fi
echo "Results: $MAINBOARDS_DIR/ampere/${PLATFORM_LOWER}/flashkernel"
ls -l $MAINBOARDS_DIR/ampere/${PLATFORM_LOWER}/flashkernel