#
# Build LinuxBoot image - flashkernel
#

BUILD_ARCH := $(shell uname -m)
GOLANG_VER := 1.15.6
GOLANG_ARCH := amd64
ifeq ($(BUILD_ARCH),aarch64)
GOLANG_ARCH := arm64
endif

TOOLCHAIN_DIR = $(SCRIPTS_DIR)/toolchain

linuxboot_prepare:
	$(eval LINUXBOOT_REPO = https://github.com/linuxboot/mainboards.git)
	$(eval LINUXBOOT_BRANCH = master)
ifeq ($(wildcard $(ROOT_DIR)/mainboards),)
	@cd $(ROOT_DIR) && \
	git clone --single-branch --branch $(LINUXBOOT_BRANCH) $(LINUXBOOT_REPO)
	@echo "Clone mainboard source...OK"
endif
ifeq ($(wildcard $(TOOLCHAIN_DIR)/go),)
	@mkdir -p $(TOOLCHAIN_DIR)
	$(eval GOLANG_TAR = go$(GOLANG_VER).linux-$(GOLANG_ARCH).tar.gz)
	$(eval GOLANG_URL = https://golang.org/dl/$(GOLANG_TAR))
	@echo "Downloading $(GOLANG_URL)..."
	@wget -O - -q $(GOLANG_URL) | tar xzf - -C $(TOOLCHAIN_DIR)
else
	@echo "Checking golang...OK"
endif
	$(eval export GOPATH=$(TOOLCHAIN_DIR)/gosource)
	@mkdir -p $(GOPATH)
	$(eval export PATH=$(GOPATH)/bin:$(TOOLCHAIN_DIR)/go/bin:$(PATH))

linuxboot_bin: linuxboot_prepare
	$(eval LINUXBOOT_JADE_DIR = $(ROOT_DIR)/mainboards/ampere/jade)
	$(eval EDK2_FLASHKERNEL_DIR = $(ROOT_DIR)/edk2-platforms/Platform/Ampere/LinuxBootPkg/AArch64)
	@rm -rf $(ROOT_DIR)/mainboards/ampere/jade/{flashkernel,flashinitramfs.*}
	@$(MAKE) -C $(LINUXBOOT_JADE_DIR) CROSS_COMPILE=$(COMPILER) fetch flashkernel
	@cp -f $(ROOT_DIR)/mainboards/ampere/jade/flashkernel $(EDK2_FLASHKERNEL_DIR)

linuxboot_clean:
	@rm -rf $(ROOT_DIR)/mainboards/ampere/jade/{flashkernel,flashinitramfs.*}
ifneq ($(wildcard $(ROOT_DIR)/mainboards/ampere/jade/linux),)
	@cd $(ROOT_DIR)/mainboards/ampere/jade/linux && $(MAKE) distclean
endif
