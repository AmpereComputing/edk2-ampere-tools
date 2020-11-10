# @file
#
# Copyright (c) 2020, Ampere Computing LLC. All rights reserved.<BR>
#
# SPDX-License-Identifier: ISC
#
# EDK2 Makefile
#

# Input ATF_SLIM
ifeq ("$(shell echo $(ATF_SLIM) | cut -c1-1)", "/")
	ATF_SLIM_IMG = $(ATF_SLIM)
else
	ATF_SLIM_IMG = $(PWD)/$(ATF_SLIM)
endif

# Input BOARD_SETTING
ifeq ("$(shell echo $(BOARD_SETTING) | cut -c1-1)", "/")
	BOARD_SETTING_INPUT = $(BOARD_SETTING)
else
	BOARD_SETTING_INPUT = $(PWD)/$(BOARD_SETTING)
endif

# Default Input variables
ATF_TBB ?= 1
DEBUG ?= 0

BOARD_NAME ?= jade
BOARD_NAME_UPPER := $(shell echo $(BOARD_NAME) | tr a-z A-Z)
BOARD_NAME_UPPER_FIRST_LETTER := $(shell echo $(BOARD_NAME) | sed 's/.*/\u&/')

# Directory variables
SCRIPTS_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell dirname $(SCRIPTS_DIR))

EDK2_SRC_DIR := $(ROOT_DIR)/edk2
EDK2_PLATFORMS_SRC_DIR := $(ROOT_DIR)/edk2-platforms
EDK2_PLATFORMS_PKG_DIR := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UPPER_FIRST_LETTER)Pkg

ATF_TOOLS_DIR := $(SCRIPTS_DIR)/toolchain/atf-tools
COMPILER_DIR := $(SCRIPTS_DIR)/toolchain/ampere
IASL_DIR := $(SCRIPTS_DIR)/toolchain/iasl

export WORKSPACE := $(PWD)

# Input DEST_DIR
ifeq (, $(DEST_DIR))
	OUTPUT_BIN_DIR = $(PWD)/BUILDS/$(BOARD_NAME)_$(BUILD_IMG_TYPE)_atf$(OUTPUT_VARIANT)_$(VER).$(BUILD)
else

ifeq ("$(shell echo $(DEST_DIR) | cut -c1-1)", "/")
	OUTPUT_BIN_DIR = $(DEST_DIR)
else
	OUTPUT_BIN_DIR = $(PWD)/$(DEST_DIR)
endif

endif

# Misc variables
EDK2_GCC_TAG := GCC5
CROSS_COMPILE_PREFIX := aarch64-ampere-linux-gnu-
AARCH64_TOOLS_DIR := $(COMPILER_DIR)/bin

export PATH := $(PATH):$(IASL_DIR):$(ATF_TOOLS_DIR)

NUM_THREADS := $(shell echo $$(( $(shell getconf _NPROCESSORS_ONLN) + $(shell getconf _NPROCESSORS_ONLN))))

ATF_REPO_URL := https://github.com/ARM-software/arm-trusted-firmware.git
export ATF_TOOLS_LIST := include/tools_share \nmake_helpers \ntools/cert_create \ntools/fiptool

IASL_VER = "20200110"
IASL_NAME = acpica-unix2-$(IASL_VER)
IASL_URL = "https://acpica.org/sites/acpica/files/$(IASL_NAME).tar.gz"

COMPILER_NAME = ampere-8.3.0-20191025-dynamic-nosysroot-crosstools.tar.xz
COMPILER_URL = https://cdn.amperecomputing.com/tools/compilers/cross/8.3.0/$(COMPILER_NAME)

IASL := iasl
FIPTOOL := fiptool
CERTTOOL := cert_create
NVGENCMD := python nvparam.py

# Build variant variables
ifeq ($(DEBUG),1)
	BUILD_VARIANT = DEBUG
	OUTPUT_VARIANT = _debug
else
	BUILD_VARIANT = RELEASE
	OUTPUT_VARIANT =
endif

ifeq ($(BUILD_LINUXBOOT),1)
	LINUXBOOTPKG = Linuxboot
	BUILD_IMG_TYPE = linuxboot
else
	LINUXBOOTPKG =
	BUILD_IMG_TYPE = tianocore
endif

BUILD_VARIANT_LOWER = $(shell echo $(BUILD_VARIANT) | tr A-Z a-z)
BUILD_VARIANT_UPPER_FIRST_LETTER = $(shell echo $(BUILD_VARIANT_LOWER) | sed 's/.*/\u&/')

GIT_VER = $(shell cd $(EDK2_PLATFORMS_SRC_DIR) && git describe --tags --dirty --long | grep ampere | grep -v dirty | cut -d \- -f 1 | cut -d \v -f 2)

# Input VER
VER ?= $(shell echo $(GIT_VER) | cut -d \. -f 1,2)
ifeq ($(VER),)
	VER = 0.00
endif

# Input BUILD
BUILD ?= $(shell echo $(GIT_VER) | cut -d \. -f 3)
ifeq ($(BUILD),)
	BUILD = 100
endif

MAJOR_VER = $(shell echo $(VER) | cut -d \. -f 1 )
MINOR_VER = $(shell echo $(VER) | cut -d \. -f 2 )

# File path variables
OUTPUT_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_$(BUILD_IMG_TYPE)_atf$(OUTPUT_VARIANT)_$(VER).$(BUILD).img
OUTPUT_CAPSULE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_$(BUILD_IMG_TYPE)_atf$(OUTPUT_VARIANT)_$(VER).$(BUILD).cap
OUTPUT_FD_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_$(BUILD_IMG_TYPE)$(OUTPUT_VARIANT)_$(VER).$(BUILD).fd
OUTPUT_FD_SIGNED_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_$(BUILD_IMG_TYPE)$(OUTPUT_VARIANT)_$(VER).$(BUILD).fd.signed

OUTPUT_BST_TXT = $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_board_setting.txt
OUTPUT_BST_BIN = $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_board_setting.bin

DEFAULT_BOARD_SETTING = $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UPPER_FIRST_LETTER)Pkg/$(BOARD_NAME)_board_setting.txt

DBB_KEY := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UPPER_FIRST_LETTER)Pkg/TestKeys/Dbb_AmpereTest.priv.pem
DBU_KEY := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UPPER_FIRST_LETTER)Pkg/TestKeys/Dbu_AmpereTest.priv.pem

EDK2_ATF_SIGNED_IMAGE := $(WORKSPACE)/Build/$(BOARD_NAME_UPPER_FIRST_LETTER)/$(BOARD_NAME)_atfedk2.img.signed
EDK2_FV_DIR := $(WORKSPACE)/Build/$(BOARD_NAME_UPPER_FIRST_LETTER)/$(BUILD_VARIANT)_$(EDK2_GCC_TAG)/FV
EDK2_FD_IMAGE := $(EDK2_FV_DIR)/BL33_$(BOARD_NAME_UPPER)_UEFI.fd

# Targets
define HELP_MSG
Ampere EDK2 Tools
============================================================
Usage: make <Targets> [Options]
Options:
	ATF_SLIM=<Path>         : Path to atf.slim image
	BOARD_SETTING=<Path>    : Path to board_setting.[txt/bin]
	                          - Default: $(BOARD_NAME)_board_setting.txt
	BUILD=<Build>           : Specify image build id
	                          - Default: 100
	DEST_DIR=<Path>         : Path to output directory
	                          - Default: $(PWD)/BUILDS
	DEBUG=[0,1]             : Enable debug build
	                          - Default: 0
	VER=<Major.Minor>       : Specify image version
	                          - Default: 0.0
Target:
endef
export HELP_MSG

## help			: Print this help
.PHONY: help
help:
	@echo "$$HELP_MSG"
	@sed -ne '/@sed/!s/## /	/p' $(MAKEFILE_LIST)

## all			: Build all
.PHONY: all
all: tianocore_capsule linuxboot_img

## clean			: Clean basetool and tianocore build
.PHONY: clean
clean: tianocore_basetools_clean tianocore_clean

## linuxboot_img		: Linuxboot image
.PHONY: linuxboot_img
linuxboot_img:
	@$(MAKE) tianocore_img BUILD_LINUXBOOT=1

_check_edk2_source:
	@echo -n "Checking edk2..."
ifeq (, $(wildcard $(EDK2_SRC_DIR)))
	$(error "$(EDK2_SRC_DIR) not found.")
else
	@echo "OK"
endif

	@echo -n "Checking edk2-platforms..."
ifeq (, $(wildcard $(EDK2_PLATFORMS_SRC_DIR)))
	$(error "$(EDK2_PLATFORMS_SRC_DIR) not found.")
else
	@echo "OK"
endif

_check_tools:
	@echo -n "Checking openssl..."
ifeq (, $(shell which openssl))
	$(error "Not Found. Please install to your system!")
else
	@echo "OK"
endif

	@echo -n "Checking git..."
ifeq (, $(shell which git))
	$(error "Not Found. Please install to your system!")
else
	@echo "OK"
endif

	@echo -n "Checking cut..."
ifeq (, $(shell which cut))
	$(error "Not Found. Please install to your system!")
else
	@echo "OK"
endif

	@echo -n "Checking sed..."
ifeq (, $(shell which sed))
	$(error "Not Found. Please install to your system!")
else
	@echo "OK"
endif

_check_compiler:
	@echo -n "Checking compiler..."
ifneq ($(and $(CROSS_COMPILE),$(shell which $(CROSS_COMPILE)gcc),$(shell $(CROSS_COMPILE)gcc --version | grep Ampere | grep nosysroot)),)
	@echo "OK"
else

	$(eval CROSS_COMPILE=$(AARCH64_TOOLS_DIR)/$(CROSS_COMPILE_PREFIX))
ifeq (, $(wildcard $(AARCH64_TOOLS_DIR)/$(CROSS_COMPILE_PREFIX)gcc))		# check default toolchain directory
	@echo "Not Found"
	@echo "Downloading and setting Ampere compiler..."
	@mkdir -p $(COMPILER_DIR)
	@wget -O - -q $(COMPILER_URL) | tar xJf - -C $(COMPILER_DIR) --strip-components=1 --checkpoint=.100
else
	@echo "Use Default Compiler"
endif

endif

_check_atf_tools:
	@echo -n "Checking ATF Tools..."
ifneq (, $(and $(shell which $(CERTTOOL)),$(shell which $(FIPTOOL))))
	@echo "OK"
else

ifneq (, $(and $(wildcard $(ATF_TOOLS_DIR)/$(CERTTOOL)),$(wildcard $(ATF_TOOLS_DIR)/$(FIPTOOL))))
	@echo "OK"
else
	@echo "Not Found"
	@echo "Downloading and building atf tools..."
	@mkdir -p $(SCRIPTS_DIR)/AtfTools
	@cd $(SCRIPTS_DIR)/AtfTools && git init && git remote add origin -f $(ATF_REPO_URL) && git config core.sparseCheckout true
	@echo -e $$ATF_TOOLS_LIST > $(SCRIPTS_DIR)/AtfTools/.git/info/sparse-checkout
	@cd $(SCRIPTS_DIR)/AtfTools && git -C . checkout --track origin/master
	@cd $(SCRIPTS_DIR)/AtfTools/tools/cert_create && $(MAKE) CRTTOOL=cert_create
	@cd $(SCRIPTS_DIR)/AtfTools/tools/fiptool && $(MAKE) FIPTOOL=fiptool

	@rm -rf $(ATF_TOOLS_DIR)
	@mkdir -p $(ATF_TOOLS_DIR)
	@cp $(SCRIPTS_DIR)/AtfTools/tools/cert_create/cert_create $(ATF_TOOLS_DIR)/$(CERTTOOL)
	@cp $(SCRIPTS_DIR)/AtfTools/tools/fiptool/fiptool $(ATF_TOOLS_DIR)/$(FIPTOOL)
	@rm -rf $(SCRIPTS_DIR)/AtfTools
endif

endif

_check_iasl:
	@echo -n "Checking iasl..."
ifneq (, $(and $(shell which $(IASL)),$(shell $(IASL) -v | grep version | grep 20200110)))
	@echo "OK"
else

ifneq (, $(wildcard $(IASL_DIR)/$(IASL)))
	@echo "OK"
else
	@echo "Not Found"
	@echo "Downloading and building iasl..."
	@rm -fr $(IASL_DIR)
	@mkdir -p $(IASL_DIR)
	@wget -O - -q $(IASL_URL) | tar xzf - -C $(SCRIPTS_DIR)
	@$(MAKE) -C $(SCRIPTS_DIR)/$(IASL_NAME) -j $(NUM_THREADS)
	@cp ${SCRIPTS_DIR}/${IASL_NAME}/generate/unix/bin/iasl $(IASL_DIR)/$(IASL)
	@rm -rf $(SCRIPTS_DIR)/$(IASL_NAME)
endif

endif

_check_atf_slim:
	@echo -n "Checking ATF_SLIM..."
ifeq ("$(suffix $(wildcard $(ATF_SLIM_IMG)))", ".slim")
	@echo "OK"
else
	$(error "ATF Slim is invalid")
endif

_check_board_setting:
	@echo -n "Checking BOARD_SETTING..."
	@mkdir -p $(OUTPUT_BIN_DIR)
ifeq ("$(suffix $(wildcard $(BOARD_SETTING_INPUT)))",".bin")
	@cp $(BOARD_SETTING_INPUT) $(OUTPUT_BST_BIN)
	@echo "OK"
else
ifeq ("$(suffix $(wildcard $(BOARD_SETTING_INPUT)))",".txt")
	@cp $(BOARD_SETTING_INPUT) $(OUTPUT_BST_TXT)
else
	@cp $(DEFAULT_BOARD_SETTING) $(OUTPUT_BST_TXT)
endif
	@echo "Generate board setting..."
	$(NVGENCMD) -f $(OUTPUT_BST_TXT) -o $(OUTPUT_BST_BIN)
	@rm -r $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_board_setting.bin.padded
endif

_tianocore_prepare: _check_edk2_source _check_tools _check_iasl _check_compiler
ifeq (, $(wildcard $(EDK2_SRC_DIR)/BaseTools/Source/C/bin))
	@echo "Build Tianocore Basetools..."
	$(MAKE) -C $(EDK2_SRC_DIR)/BaseTools
endif
	$(eval export PACKAGES_PATH = $(EDK2_SRC_DIR):$(EDK2_PLATFORMS_SRC_DIR))
	$(eval export $(EDK2_GCC_TAG)_AARCH64_PREFIX = $(CROSS_COMPILE))

_tianocore_sign_fd: _check_atf_tools
	@echo "Creating certitficate for $(OUTPUT_FD_IMAGE)"
	@$(CERTTOOL) -n --ntfw-nvctr 0 --key-alg rsa --nt-fw-key $(DBB_KEY) --nt-fw-cert $(OUTPUT_FD_IMAGE).crt --nt-fw $(OUTPUT_FD_IMAGE)
	@$(FIPTOOL) create --nt-fw-cert $(OUTPUT_FD_IMAGE).crt --nt-fw $(OUTPUT_FD_IMAGE) $(OUTPUT_FD_SIGNED_IMAGE)
	@rm $(OUTPUT_FD_IMAGE).crt

## tianocore_fd		: Tianocore FD image
.PHONY: tianocore_fd
tianocore_fd: _tianocore_prepare
	@echo "Build Tianocore $(BUILD_VARIANT_UPPER_FIRST_LETTER) FD..."
	. $(EDK2_SRC_DIR)/edksetup.sh && build -a AARCH64 -t $(EDK2_GCC_TAG) -b $(BUILD_VARIANT) -n $(NUM_THREADS) \
		-D FIRMWARE_VER="$(MAJOR_VER).$(MINOR_VER).$(BUILD) Build $(shell date '+%Y%m%d')" \
		-D MAJOR_VER=$(MAJOR_VER) \
		-D MINOR_VER=$(MINOR_VER) \
		-D SECURE_BOOT_ENABLE \
		-p Platform/Ampere/$(BOARD_NAME_UPPER_FIRST_LETTER)Pkg/$(BOARD_NAME_UPPER_FIRST_LETTER)$(LINUXBOOTPKG).dsc

	@mkdir -p $(OUTPUT_BIN_DIR)
	@cp -f $(EDK2_FD_IMAGE) $(OUTPUT_FD_IMAGE)

## tianocore_img		: Tianocore Integrated image
.PHONY: tianocore_img
tianocore_img: _check_atf_slim _check_board_setting tianocore_fd
	@echo "Build Tianocore $(BUILD_VARIANT_UPPER_FIRST_LETTER) Image.."
	@dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > $(OUTPUT_IMAGE)
	@dd bs=1 conv=notrunc if=$(ATF_SLIM_IMG) of=$(OUTPUT_IMAGE)
	@dd bs=1 seek=2031616 conv=notrunc if=$(OUTPUT_BST_BIN) of=$(OUTPUT_IMAGE)
ifeq ($(ATF_TBB),1)
	@$(MAKE) _tianocore_sign_fd
	@dd bs=1024 seek=2048 if=$(OUTPUT_FD_SIGNED_IMAGE) of=$(OUTPUT_IMAGE)
	@rm $(OUTPUT_FD_SIGNED_IMAGE)
else
	dd bs=1024 seek=2048 if=$(OUTPUT_FD_IMAGE) of=$(OUTPUT_IMAGE)
endif

## tianocore_capsule	: Tianocore Capsule image
.PHONY: tianocore_capsule
tianocore_capsule: tianocore_img
	@echo "Build Tianocore $(BUILD_VARIANT_UPPER_FIRST_LETTER) Capsule..."
	@echo "Sign Tianocore Image"
	@openssl dgst -sha256 -sign $(DBU_KEY) -out $(OUTPUT_IMAGE).sig $(OUTPUT_IMAGE)
	@cat $(OUTPUT_IMAGE).sig $(OUTPUT_IMAGE) > $(OUTPUT_IMAGE).signed
	@cp -f $(OUTPUT_IMAGE).signed $(EDK2_ATF_SIGNED_IMAGE)

	@echo "Build Capsule Image"
	. $(EDK2_SRC_DIR)/edksetup.sh && build -a AARCH64 -t $(EDK2_GCC_TAG) -b $(BUILD_VARIANT) \
		-p Platform/Ampere/$(BOARD_NAME_UPPER_FIRST_LETTER)Pkg/$(BOARD_NAME_UPPER_FIRST_LETTER)Capsule.dsc
	@cp -f $(EDK2_FV_DIR)/JADEFIRMWAREUPDATECAPSULEFMPPKCS7.Cap $(OUTPUT_CAPSULE)
	@rm $(OUTPUT_IMAGE).sig $(OUTPUT_IMAGE).signed

.PHONY: tianocore_basetools_clean
tianocore_basetools_clean:
	@echo "Tianocore clean BaseTools..."
	$(MAKE) -C $(EDK2_SRC_DIR)/BaseTools clean

.PHONY: tianocore_clean
tianocore_clean:
	@echo "Tianocore clean..."
	@rm -rf $(WORKSPACE)/Build

# end of makefile
