# LinuxBoot

LinuxBoot is a firmware that replaces specific firmware functionality like the UEFI DXE phase with a Linux kernel and runtime. It is built-in UEFI image like an application as it will be executed at the end of DXE phase.

The LinuxBoot binary, named flashkernel, consists of [Linux](https://kernel.org) kernel and initramfs generated using [u-root](https://github.com/u-root/u-root). It is built completely from the [linuxboot/linuxboot](https://github.com/linuxboot/linuxboot) repository.

This provides instructions to build a EDK2+LinuxBoot FD (Flash Device) image for Ampere's platforms.

## Building LinuxBoot binary

Before building, please make sure that your build system has the following tools installed:

* golang
* Cross-compiler for Arm64 if needed.

Step 1: Clone the `linuxboot` repository

```shell
git clone --branch master https://github.com/linuxboot/linuxboot.git
```

Step 2: Building LinuxBoot binary

```shell
GO111MODULE=off make -C linuxboot/mainboards/ampere/jade fetch flashkernel ARCH=arm64
```

**Notes:** If using cross-compilation, append argument CROSS_COMPILE=${CROSS_COMPILE} pointing to the cross compiler.

You can use the helper script `linuxboot-bin-build.sh` provided in this repository to build the LinuxBoot binary. The command is as follows:

```shell
./linuxboot-bin-build.sh
```

Step 3: Copy the `flashkernel` to the `edk2-platforms/Platform/Ampere/LinuxBootPkg/AArch64/`

```shell
cp linuxboot/mainboards/ampere/jade/flashkernel edk2-platforms/Platform/Ampere/LinuxBootPkg/AArch64/flashkernel
```

## Building EDK2+LinuxBoot FD

```shell
cd edk2-platforms && build -a AARCH64 -t GCC5 -b RELEASE -p Platform/Ampere/JadePkg/JadeLinuxBoot.dsc
```

The resulting image will be at

`edk2-platforms/Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd`
