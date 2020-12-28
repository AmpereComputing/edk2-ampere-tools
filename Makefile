# @file
#
# Copyright (c) 2020, Ampere Computing LLC. All rights reserved.<BR>
#
# SPDX-License-Identifier: ISC
#
# EDK2 Makefile
#
SHELL := /bin/bash

# Default Input variables
ATF_TBB ?= 1

BOARD_NAME ?= jade
BOARD_NAME_UPPER := $(shell echo $(BOARD_NAME) | tr a-z A-Z)
# Board name upper first letter
BOARD_NAME_UFL := $(shell echo $(BOARD_NAME) | sed 's/.*/\u&/')

# Directory variables
CUR_DIR := $(PWD)
SCRIPTS_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell dirname $(SCRIPTS_DIR))

EDK2_SRC_DIR := $(ROOT_DIR)/edk2
EDK2_NON_OSI_SRC_DIR := $(ROOT_DIR)/edk2-non-osi
EDK2_PLATFORMS_SRC_DIR := $(ROOT_DIR)/edk2-platforms
EDK2_PLATFORMS_PKG_DIR := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UFL)Pkg
REQUIRE_EDK2_SRC := $(EDK2_SRC_DIR) $(EDK2_PLATFORMS_SRC_DIR)$(if $(wildcard $(EDK2_NON_OSI_SRC_DIR)), $(EDK2_NON_OSI_SRC_DIR),)

ATF_TOOLS_DIR := $(SCRIPTS_DIR)/toolchain/atf-tools
COMPILER_DIR := $(SCRIPTS_DIR)/toolchain/ampere
IASL_DIR := $(SCRIPTS_DIR)/toolchain/iasl
AARCH64_TOOLS_DIR := $(COMPILER_DIR)/bin
export PATH := $(IASL_DIR):$(ATF_TOOLS_DIR):$(PATH)

# Compiler variables
EDK2_GCC_TAG := GCC5
AMPERE_COMPILER_PREFIX := aarch64-ampere-linux-gnu-
ifeq ($(or $(shell $(CROSS_COMPILE)gcc -dumpmachine 2>/dev/null | grep -v ampere | grep aarch64), \
           $(shell $(CROSS_COMPILE)gcc --version 2>/dev/null| grep Ampere | grep dynamic-nosysroot)),)
	COMPILER := $(AARCH64_TOOLS_DIR)/$(AMPERE_COMPILER_PREFIX)
else
	COMPILER := $(CROSS_COMPILE)
endif

NUM_THREADS := $(shell echo $$(( $(shell getconf _NPROCESSORS_ONLN) + $(shell getconf _NPROCESSORS_ONLN))))

# Tools variables
IASL := iasl
FIPTOOL := fiptool
CERTTOOL := cert_create
NVGENCMD := python $(SCRIPTS_DIR)/nvparam.py
EXECUTABLES := openssl git cut sed awk wget tar bison gcc g++

# Build variant variables
BUILD_VARIANT := $(if $(shell echo $(DEBUG) | grep -w 1),DEBUG,RELEASE)
BUILD_VARIANT_LOWER := $(shell echo $(BUILD_VARIANT) | tr A-Z a-z)
# Build variant upper first letter
BUILD_VARIANT_UFL := $(shell echo $(BUILD_VARIANT_LOWER) | sed 's/.*/\u&/')

GIT_VER := $(shell cd $(EDK2_PLATFORMS_SRC_DIR) 2>/dev/null && \
			git describe --tags --dirty --long --always | grep ampere | grep -v dirty | cut -d \- -f 1 | cut -d \v -f 2)
# Input VER
VER ?= $(shell echo $(GIT_VER) | cut -d \. -f 1,2)
VER := $(if $(VER),$(VER),0.00)

# Input BUILD
BUILD ?= $(shell echo $(GIT_VER) | cut -d \. -f 3)
BUILD := $(if $(BUILD),$(BUILD),100)

# File path variables
LINUXBOOT_FMT := $(if $(shell echo $(BUILD_LINUXBOOT) | grep -w 1),_linuxboot,)
OUTPUT_VARIANT := $(if $(shell echo $(DEBUG) | grep -w 1),_debug,)
OUTPUT_BIN_DIR := $(if $(DEST_DIR),$(DEST_DIR),$(CUR_DIR)/BUILDS/$(BOARD_NAME)_tianocore_atf$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD))

OUTPUT_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_tianocore_atf$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD).img
OUTPUT_RAW_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_tianocore_atf$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD).img.raw
OUTPUT_FD_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_tianocore$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD).fd
OUTPUT_FD_SIGNED_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_tianocore$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD).fd.signed
OUTPUT_BST_BIN := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_board_setting.bin

BOARD_SETTING ?= $(EDK2_PLATFORMS_PKG_DIR)/$(BOARD_NAME)_board_setting.txt

ATF_MAJOR = $(shell grep -aPo AMPC31.\{0,14\} $(ATF_SLIM) | tr -d '\0' | cut -c7 )
ATF_MINOR = $(shell grep -aPo AMPC31.\{0,14\} $(ATF_SLIM) | tr -d '\0' | cut -c8-9 )
ATF_BUILD = $(shell grep -aPo AMPC31.\{0,14\} $(ATF_SLIM) | tr -d '\0' | cut -c10-17 )
ATF_VER = $(ATF_MAJOR)$(ATF_MINOR)

# Targets
define HELP_MSG
Ampere EDK2 Tools
============================================================
Usage: make <Targets> [Options]
Options:
	ATF_SLIM=<Path>         : Path to atf.slim image
	LINUXBOOT_BIN=<Path>    : Path to linuxboot binary (flashkernel)
	BOARD_SETTING=<Path>    : Path to board_setting.[txt/bin]
	                          - Default: $(BOARD_NAME)_board_setting.txt
	BUILD=<Build>           : Specify image build id
	                          - Default: 100
	DEST_DIR=<Path>         : Path to output directory
	                          - Default: $(CUR_DIR)/BUILDS
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
clean:
	@echo "Tianocore clean BaseTools..."
	$(MAKE) -C $(EDK2_SRC_DIR)/BaseTools clean

	@echo "Tianocore clean $(CUR_DIR)/Build..."
	@rm -fr $(CUR_DIR)/Build

## linuxboot_img		: Linuxboot image
.PHONY: linuxboot_img
linuxboot_img: _check_linuxboot_bin
	@$(MAKE) -C $(SCRIPTS_DIR) tianocore_img BUILD_LINUXBOOT=1 CUR_DIR=$(CUR_DIR)

_check_source:
	@echo "Checking source...OK"
	$(foreach iter,$(REQUIRE_EDK2_SRC),\
		$(if $(wildcard $(iter)),,$(error "$(iter) not found")))

_check_tools:
	@echo "Checking tools...OK"
	$(foreach iter,$(EXECUTABLES),\
		$(if $(shell which $(iter) 2>/dev/null),,$(error "No $(iter) in PATH")))

_check_compiler:
	@echo -n "Checking compiler..."
	$(eval COMPILER_NAME := ampere-8.3.0-20191025-dynamic-nosysroot-crosstools.tar.xz)
	$(eval COMPILER_URL := https://cdn.amperecomputing.com/tools/compilers/cross/8.3.0/$(COMPILER_NAME))
ifeq ($(or $(shell echo $(COMPILER)gcc | grep -v $(AARCH64_TOOLS_DIR)), \
		   $(wildcard $(AARCH64_TOOLS_DIR)/$(AMPERE_COMPILER_PREFIX)gcc)),)
	@echo -e "Not Found\nDownloading and setting Ampere compiler..."
	@rm -rf $(COMPILER_DIR) && mkdir -p $(COMPILER_DIR)
	@wget -O - -q $(COMPILER_URL) | tar xJf - -C $(COMPILER_DIR) --strip-components=1 --checkpoint=.100
else
	@echo "$(shell $(COMPILER)gcc -dumpmachine) $(shell $(COMPILER)gcc -dumpversion)"
endif

_check_atf_tools:
	@echo -n "Checking ATF Tools..."
	$(eval ATF_REPO_URL := https://github.com/ARM-software/arm-trusted-firmware.git)
	$(eval export ATF_TOOLS_LIST := include/tools_share \nmake_helpers \ntools/cert_create \ntools/fiptool)
ifneq ($(or $(and $(shell which $(CERTTOOL) 2>/dev/null),$(shell which $(FIPTOOL) 2>/dev/null)),  \
		    $(and $(wildcard $(ATF_TOOLS_DIR)/$(CERTTOOL)),$(wildcard $(ATF_TOOLS_DIR)/$(FIPTOOL)))),)
	@echo "OK"
else
	@echo -e "Not Found\nDownloading and building atf tools..."
	@rm -rf $(SCRIPTS_DIR)/AtfTools && mkdir -p $(SCRIPTS_DIR)/AtfTools
	@rm -rf $(ATF_TOOLS_DIR) && mkdir -p $(ATF_TOOLS_DIR)
	@cd $(SCRIPTS_DIR)/AtfTools && git init && git remote add origin -f $(ATF_REPO_URL) && git config core.sparseCheckout true
	@echo -e $$ATF_TOOLS_LIST > $(SCRIPTS_DIR)/AtfTools/.git/info/sparse-checkout
	@cd $(SCRIPTS_DIR)/AtfTools && git -C . checkout --track origin/master
	@cd $(SCRIPTS_DIR)/AtfTools/tools/cert_create && $(MAKE) CRTTOOL=cert_create
	@cd $(SCRIPTS_DIR)/AtfTools/tools/fiptool && $(MAKE) FIPTOOL=fiptool
	@cp $(SCRIPTS_DIR)/AtfTools/tools/cert_create/cert_create $(ATF_TOOLS_DIR)/$(CERTTOOL)
	@cp $(SCRIPTS_DIR)/AtfTools/tools/fiptool/fiptool $(ATF_TOOLS_DIR)/$(FIPTOOL)
	@rm -fr $(SCRIPTS_DIR)/AtfTools
endif

_check_iasl:
	@echo -n "Checking iasl..."
	$(eval IASL_NAME := acpica-unix2-20200110)
	$(eval IASL_URL := "https://acpica.org/sites/acpica/files/$(IASL_NAME).tar.gz")
ifneq ($(or $(and $(shell which $(IASL) 2>/dev/null),$(shell $(IASL) -v | grep version | grep 20200110)), \
		    $(wildcard $(IASL_DIR)/$(IASL))),)
	@echo "OK"
else
	@echo -e "Not Found\nDownloading and building iasl..."
	@rm -rf $(IASL_DIR) && mkdir -p $(IASL_DIR)
	@wget -O - -q $(IASL_URL) | tar xzf - -C $(SCRIPTS_DIR) --checkpoint=.100
	@$(MAKE) -C $(SCRIPTS_DIR)/$(IASL_NAME) -j $(NUM_THREADS) HOST=_CYGWIN
	@cp ${SCRIPTS_DIR}/${IASL_NAME}/generate/unix/bin/iasl $(IASL_DIR)/$(IASL)
	@rm -fr $(SCRIPTS_DIR)/$(IASL_NAME)
endif

_check_atf_slim:
	@echo "Checking ATF_SLIM...OK"
ifneq ("$(suffix $(wildcard $(ATF_SLIM)))", ".slim")
	$(error "ATF_SLIM invalid")
endif

_check_linuxboot_bin:
	@echo "Checking LINUXBOOT_BIN...OK"
ifeq ($(wildcard $(LINUXBOOT_BIN)),)
	$(error "LINUXBOOT_BIN invalid")
endif

_check_board_setting:
	@echo "Checking BOARD_SETTING...OK"
	$(eval OUTPUT_BST_TXT := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_board_setting.txt)
	@mkdir -p $(OUTPUT_BIN_DIR)

ifeq ("$(suffix $(wildcard $(BOARD_SETTING)))",".bin")
	@cp $(BOARD_SETTING) $(OUTPUT_BST_BIN)
else

ifeq ("$(suffix $(wildcard $(BOARD_SETTING)))",".txt")
	@cp $(BOARD_SETTING) $(OUTPUT_BST_TXT)
	@$(NVGENCMD) -f $(OUTPUT_BST_TXT) -o $(OUTPUT_BST_BIN)
	@rm -r $(OUTPUT_BST_BIN).padded
else
	$(error "BOARD_SETTING invalid")
endif

endif

_tianocore_prepare: _check_source _check_tools _check_compiler _check_iasl
	$(if $(wildcard $(EDK2_SRC_DIR)/BaseTools/Source/C/bin),,$(MAKE) -C $(EDK2_SRC_DIR)/BaseTools -j $(NUM_THREADS))
	$(eval export WORKSPACE := $(CUR_DIR))
	$(eval export PACKAGES_PATH := $(shell echo $(REQUIRE_EDK2_SRC) | sed 's/ /:/g'))
	$(eval export $(EDK2_GCC_TAG)_AARCH64_PREFIX := $(COMPILER))
	$(eval EDK2_FV_DIR := $(WORKSPACE)/Build/$(BOARD_NAME_UFL)/$(BUILD_VARIANT)_$(EDK2_GCC_TAG)/FV)

_tianocore_sign_fd: _check_atf_tools
	@echo "Creating certitficate for $(OUTPUT_FD_IMAGE)"
	$(eval DBB_KEY := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UFL)Pkg/TestKeys/Dbb_AmpereTest.priv.pem)
	@$(CERTTOOL) -n --ntfw-nvctr 0 --key-alg rsa --nt-fw-key $(DBB_KEY) --nt-fw-cert $(OUTPUT_FD_IMAGE).crt --nt-fw $(OUTPUT_FD_IMAGE)
	@$(FIPTOOL) create --nt-fw-cert $(OUTPUT_FD_IMAGE).crt --nt-fw $(OUTPUT_FD_IMAGE) $(OUTPUT_FD_SIGNED_IMAGE)
	@rm -fr $(OUTPUT_FD_IMAGE).crt

## tianocore_fd		: Tianocore FD image
.PHONY: tianocore_fd
tianocore_fd: _tianocore_prepare
	@echo "Build Tianocore $(BUILD_VARIANT_UFL) FD..."
	$(eval DSC_FILE := $(word 1,$(wildcard $(if $(shell echo $(BUILD_LINUXBOOT) | grep -w 1) \
									,$(EDK2_PLATFORMS_PKG_DIR)/$(BOARD_NAME_UFL)Linux*.dsc \
									,$(EDK2_PLATFORMS_PKG_DIR)/$(BOARD_NAME_UFL).dsc))))
	$(if $(DSC_FILE),,$(error "DSC not found"))
	$(eval MAJOR_VER := $(shell echo $(VER) | cut -d \. -f 1 ))
	$(eval MINOR_VER := $(shell echo $(VER) | cut -d \. -f 2 ))
	$(eval EDK2_FD_IMAGE := $(EDK2_FV_DIR)/BL33_$(BOARD_NAME_UPPER)_UEFI.fd)
ifeq ($(BUILD_LINUXBOOT),1)
ifneq ($(wildcard $(LINUXBOOT_BIN)),)
	@cp $(LINUXBOOT_BIN) $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/LinuxBootPkg/AArch64/flashkernel
endif
endif
	. $(EDK2_SRC_DIR)/edksetup.sh && build -a AARCH64 -t $(EDK2_GCC_TAG) -b $(BUILD_VARIANT) -n $(NUM_THREADS) \
		-D FIRMWARE_VER="$(MAJOR_VER).$(MINOR_VER).$(BUILD) Build $(shell date '+%Y%m%d')" \
		-D MAJOR_VER=$(MAJOR_VER) -D MINOR_VER=$(MINOR_VER) -D SECURE_BOOT_ENABLE \
		-p $(DSC_FILE)
	@mkdir -p $(OUTPUT_BIN_DIR)
	@cp -f $(EDK2_FD_IMAGE) $(OUTPUT_FD_IMAGE)

## tianocore_img		: Tianocore Integrated image
.PHONY: tianocore_img
tianocore_img: _check_atf_slim _check_board_setting tianocore_fd
	@echo "Build Tianocore $(BUILD_VARIANT_UFL) Image - ATF VERSION: $(ATF_MAJOR).$(ATF_MINOR).$(ATF_BUILD)..."
	@dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > $(OUTPUT_RAW_IMAGE)
	@dd bs=1 seek=0 conv=notrunc if=$(ATF_SLIM) of=$(OUTPUT_RAW_IMAGE)
	@dd bs=1 seek=2031616 conv=notrunc if=$(OUTPUT_BST_BIN) of=$(OUTPUT_RAW_IMAGE)

ifeq ($(ATF_TBB),1)
	@$(MAKE) -C $(SCRIPTS_DIR) _tianocore_sign_fd
	@dd bs=1024 seek=2048 if=$(OUTPUT_FD_SIGNED_IMAGE) of=$(OUTPUT_RAW_IMAGE)
	@rm -fr $(OUTPUT_FD_SIGNED_IMAGE)
else
	@dd bs=1024 seek=2048 if=$(OUTPUT_FD_IMAGE) of=$(OUTPUT_RAW_IMAGE)
endif

	@if [ $(ATF_VER) -eq 102 ] || [ $(ATF_VER) -eq 101 ]; then \
		cp $(OUTPUT_RAW_IMAGE) $(OUTPUT_IMAGE); \
	else \
		dd if=/dev/zero bs=1024 count=4096 | tr "\000" "\377" > $(OUTPUT_IMAGE); \
		dd bs=1 seek=4194304 conv=notrunc if=$(OUTPUT_RAW_IMAGE) of=$(OUTPUT_IMAGE); \
	fi

## tianocore_capsule	: Tianocore Capsule image
.PHONY: tianocore_capsule
tianocore_capsule: tianocore_img
	@echo "Build Tianocore $(BUILD_VARIANT_UFL) Capsule..."
	$(eval TIANOCORE_ATF_SIGNED_IMAGE := $(WORKSPACE)/Build/$(BOARD_NAME_UFL)/$(BUILD_VARIANT)_$(EDK2_GCC_TAG)/$(BOARD_NAME)_tianocore_atf.img.signed)
	$(eval OUTPUT_CAPSULE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_tianocore_atf$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD).cap)
	$(eval DBU_KEY := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UFL)Pkg/TestKeys/Dbu_AmpereTest.priv.pem)
	@echo "Sign Tianocore Image"
	@openssl dgst -sha256 -sign $(DBU_KEY) -out $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE)
	@cat $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE) > $(OUTPUT_RAW_IMAGE).signed
	@cp -f $(OUTPUT_RAW_IMAGE).signed $(TIANOCORE_ATF_SIGNED_IMAGE)
	# support 1.01 tag
	$(eval EDK2_ATF_SIGNED_IMAGE := $(WORKSPACE)/Build/$(BOARD_NAME_UFL)/$(BOARD_NAME)_atfedk2.img.signed)
	@ln -sf $(TIANOCORE_ATF_SIGNED_IMAGE) $(EDK2_ATF_SIGNED_IMAGE)

	@echo "Build Capsule Image"
	. $(EDK2_SRC_DIR)/edksetup.sh && build -a AARCH64 -t $(EDK2_GCC_TAG) -b $(BUILD_VARIANT) \
		-D UEFI_ATF_IMAGE=$(TIANOCORE_ATF_SIGNED_IMAGE) \
		-p Platform/Ampere/$(BOARD_NAME_UFL)Pkg/$(BOARD_NAME_UFL)Capsule.dsc
	@cp -f $(EDK2_FV_DIR)/JADEFIRMWAREUPDATECAPSULEFMPPKCS7.Cap $(OUTPUT_CAPSULE)
	@rm -fr $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE).signed $(OUTPUT_RAW_IMAGE)

# end of makefile
