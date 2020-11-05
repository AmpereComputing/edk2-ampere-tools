This repository contains instructions and tools to assist in the
compilation and final build of Tianocore for Ampere's platforms. It is
an extension of what is already provided in the README located at
`edk2-platforms/Platform/Ampere/README.md`

# Manual Building

It is assumed that your build environment has been set up appropriately
based on `edk2-platforms/Platform/Ampere/README.md`.

Througout this document, Ampere's Mt. Jade platform is used to illustrate
various steps to arrive at a final Tianocore UEFI image that can be
flashed to the platform.

The process of creating a flashable image involves the following steps:
1. Building the UEFI image
2. Signing the UEFI image
3. Integrating Ampere's Arm Trusted Firmware binary and platform's board settings
4. Building the capsule update image that can be used to update Tianocore firmware via `fwupdate` or `fwupd` methods.

## Building the UEFI image

Building UEFI image without Linuxboot

```
$ cd edk2-platforms && build -a AARCH64 -t GCC5 -b RELEASE -D SECURE_BOOT_ENABLE -p Platform/Ampere/JadePkg/Jade.dsc

```

Building UEFI image with Linuxboot

```
$ cd edk2-platforms && build -a AARCH64 -t GCC5 -b RELEASE -D SECURE_BOOT_ENABLE -p Platform/Ampere/JadePkg/JadeLinuxboot.dsc

```

The resulting image will be at

`edk2-platforms/Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd`


We will be using edk2-platforms/Build/Jade for the final artifacts.

## Signing the image

Download the pre-built fiptool and cert_create binaries from this repository
and and set your PATH environment to include the location where these are
put.

```
$ cd edk2-platforms
$ cert_create -n --ntfw-nvctr 0 --key-alg rsa --nt-fw-key Platform/Ampere/JadePkg/TestKeys/Dbb_AmpereTest.priv.pem --nt-fw-cert Build/Jade/jade_tianocore.fd.crt --nt-fw Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd
$ fiptool create --nt-fw-cert Build/Jade/jade_tianocore.fd.crt --nt-fw Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd Build/Jade/jade_tianocore.fip.signed
```

## Integrating Board Setting and Ampere's Arm Trusted Firmware (ATF)

You need to download the compatible Ampere ATF image from Ampere Connect portal at https://amperecomputing.com/customers/. Refer to the edk2-platforms release note for compatible ATF image version.

### Build Board Setting

Download nvparam.py from this repository to your build machine.

A sample working board setting file is located under Platform/Ampere/{Platform Name}Pkg/.

```
$ cd edk2-platforms
$ python nvparam.py -f Platform/Ampere/JadePkg/jade_board_setting.txt -o Build/Jade/jade_board_setting.bin

```

### Build Integrated UEFI + Board Setting + ATF image

```
$ dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > Build/Jade/jade_tianocore_atf.img
$ dd bs=1 conv=notrunc if=<ampere_atf_image_filepath> of=Build/Jade/jade_tianocore_atf.img
$ dd bs=1 seek=2031616 conv=notrunc if=Build/Jade/jade_board_setting.bin of=Build/Jade/jade_tianocore_atf.img
$ dd bs=1024 seek=2048 if=Build/Jade/jade_tianocore.fip.signed of=Build/Jade/jade_tianocore_atf.img

Result: Build/jade_tianocore_atf.img

```
### Build Tianocore Capsule

```
$ openssl dgst -sha256 -sign Platform/Ampere/JadePkg/TestKeys/Dbb_AmpereTest.priv.pem -out Build/Jade/jade_tianocore_atf.img.sig Build/Jade/jade_tianocore_atf.img
$ cat Build/Jade/jade_tianocore_atf.img.sig Build/Jade/jade_tianocore_atf.img > Build/Jade/jade_atfedk2.img.signed
$ build -a AARCH64 -t GCC5 -b RELEASE -p Platform/Ampere/JadePkg/JadeCapsule.dsc
$ cp Build/Jade/RELEASE_GCC5/FV/JADEFIRMWAREUPDATECAPSULEFMPPKCS7.Cap Build/Jade/jade_tianocore_atf.cap

Result: Build/Jade/jade_tianocore_atf.cap
```

# Using helper-scripts and Makefile

Provided in this repository are the helper script edk2-build.sh modified from Linaro's uefi-tools at https://git.linaro.org/uefi/uefi-tools.git with added support for building Ampere's platform and final integrated Tianocore image.
```
$ ./edk2-ampere-tools/edk2-build.sh -b RELEASE Jade --atf-image <ampere_atf_slim_path>
...
BUILDS/jade_tianocore_atf_1.01.100
├── [1.4K]  jade_board_setting.bin
├── [9.8K]  jade_board_setting.txt
├── [7.8M]  jade_tianocore_1.01.100.fd
├── [ 13M]  jade_tianocore_atf_1.01.100.cap
└── [9.8M]  jade_tianocore_atf_1.01.100.img

0 directories, 5 files
------------------------------------------------------------
                         Ampere Jade (AARCH64) RELEASE pass
------------------------------------------------------------
pass   1
fail   0
```
An equivalent Makefile is also provided for those who wish to use it instead. Place the Makefile in your ${WORKSPACE} directory and run `make` or `make help` for options.

