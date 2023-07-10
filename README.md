This repository contains instructions and tools to assist in the
compilation and final build of Tianocore for Ampere's platforms. It is
an extension of what is already provided in the README located at
`edk2-platforms/Platform/Ampere/README.md`

# Manual Building

It is assumed that your build environment has been set up appropriately
based on `edk2-platforms/Platform/Ampere/README.md`.

Throughout this document, Ampere's Mt. Jade platform is used to illustrate
various steps to arrive at a final Tianocore UEFI image that can be
flashed to the platform.

The process of creating a flashable image involves the following steps:
1. Building the UEFI image
2. Signing the UEFI image
3. Integrating Ampere's Arm Trusted Firmware binary and platform's board settings
4. Building the capsule update image that can be used to update Tianocore firmware via `fwupdate` or `fwupd` methods.

## Building the UEFI image

Building EDK2 FD with the following command:

```
$ cd edk2-platforms && build -a AARCH64 -t GCC5 -b RELEASE -D SECURE_BOOT_ENABLE -p Platform/Ampere/JadePkg/Jade.dsc
```

**Notes**: Please refer to [LinuxBoot.md](LinuxBoot.md) for building EDK2+LinuxBoot FD.

The resulting image will be at

`edk2-platforms/Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd`


We will be using edk2-platforms/BUILDS/jade_tianocore_atf for the final artifacts.

```
$ cd edk2-platforms
$ mkdir -p BUILDS/jade_tianocore_atf
```

## Signing the image

You need to download and install `cert_create` and `fiptool` from
Arm Trusted Firmware.

```
$ git clone --depth 1 https://github.com/ARM-software/arm-trusted-firmware.git
$ cd arm-trusted-firmware
$ make -C tools/cert_create
$ make -C tools/fiptool
```

Set up your $PATH to include cert_create and fiptool from above.

Perform the following to sign the image:
```
$ cd edk2-platforms
$ cert_create -n --ntfw-nvctr 0 --key-alg rsa --nt-fw-key edk2-platforms/Platform/Ampere/JadePkg/TestKeys/Dbb_AmpereTest.priv.pem --nt-fw-cert BUILDS/jade_tianocore_atf/jade_tianocore.fd.crt --nt-fw Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd
$ fiptool create --nt-fw-cert BUILDS/jade_tianocore_atf/jade_tianocore.fd.crt --nt-fw Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd BUILDS/jade_tianocore_atf/jade_tianocore.fip.signed
```

## Integrating Board Setting and Ampere's Arm Trusted Firmware (ATF)

You need to obtain Ampere ATF image and Board Setting file compatible with
this vesion of Ampere EDK2 in order to build a final firmware image.

Contact developer@amperecomputing.com for information.

### Build Board Setting

Download nvparam.py from this repository to your build machine.

A sample working board setting file is located under Platform/Ampere/{Platform Name}Pkg/.

```
$ cd edk2-platforms
$ python nvparam.py -f Platform/Ampere/JadePkg/jade_board_setting.txt -o BUILDS/jade_tianocore_atf/jade_board_setting.bin

```

### Build integrated UEFI + Board Setting + ATF image

Generating the final image with the following commands:

```
$ dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > BUILDS/jade_tianocore_atf/jade_tianocore_atf.img
$ dd bs=1 conv=notrunc if=<ampere_atf_image_filepath> of=BUILDS/jade_tianocore_atf/jade_tianocore_atf.img
$ dd bs=1 seek=2031616 conv=notrunc if=BUILDS/jade_tianocore_atf/jade_board_setting.bin of=BUILDS/jade_tianocore_atf/jade_tianocore_atf.img
$ dd bs=1024 seek=2048 if=BUILDS/jade_tianocore_atf/jade_tianocore.fip.signed of=BUILDS/jade_tianocore_atf/jade_tianocore_atf.img

Result: BUILDS/jade_tianocore_atf/jade_tianocore_atf.img
```

Note that the `jade_tianocore_atf.img` image is flashed at the beginning of the ATF SLIM region according to the SPI-NOR Flash Layout.

### Build Tianocore Capsule

For current Ampere ATF
```
$ build -a AARCH64 -t GCC5 -b RELEASE               \
    -p Platform/Ampere/JadePkg/JadeCapsule.dsc      \
    -D UEFI_ATF_IMAGE=<ampere_atf_image_filepath>   \
    -D SCP_IMAGE=<ampere_scp_slim_image_filepath>
$ cp Build/Jade/RELEASE_GCC5/FV/JADEUEFIATFFIRMWAREUPDATECAPSULEFMPPKCS7.Cap BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap
$ cp Build/Jade/RELEASE_GCC5/FV/JADESCPFIRMWAREUPDATECAPSULEFMPPKCS7.Cap BUILDS/jade_tianocore_atf/jade_scp.cap

Result:
    BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap
    BUILDS/jade_tianocore_atf/jade_scp.cap
```

For Ampere ATF version 1.05 and earlier
```
$ dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap.img
$ dd bs=1 conv=notrunc if=<ampere_atf_image_filepath> of=BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap.img
$ dd bs=1 seek=2031616 conv=notrunc if=BUILDS/jade_tianocore_atf/jade_board_setting.bin of=BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap.img
$ dd bs=1024 seek=2048 if=BUILDS/jade_tianocore_atf/jade_tianocore.fip.signed of=BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap.img
$ openssl dgst -sha256 -sign Platform/Ampere/JadePkg/TestKeys/Dbu_AmpereTest.priv.pem -out BUILDS/jade_tianocore_atf/jade_tianocore_atf.img.sig BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap.img
$ cat BUILDS/jade_tianocore_atf/jade_tianocore_atf.img.sig BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap.img > Build/Jade/RELEASE_GCC5/jade_tianocore_atf.img.signed
$ build -a AARCH64 -t GCC5 -b RELEASE -p Platform/Ampere/JadePkg/JadeCapsule.dsc -D UEFI_ATF_IMAGE=Build/Jade/RELEASE_GCC5/jade_tianocore_atf.img.signed
$ cp Build/Jade/RELEASE_GCC5/FV/JADEFIRMWAREUPDATECAPSULEFMPPKCS7.Cap BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap

Result: BUILDS/jade_tianocore_atf/jade_tianocore_atf.cap
```

# Using helper-scripts and Makefile

Provided in this repository are the helper script **edk2-build.sh** modified from Linaro's uefi-tools at https://git.linaro.org/uefi/uefi-tools.git with added support for building Ampere's platform and final integrated Tianocore image.

```
$ cd edk2-ampere-tools/
$ ./edk2-build.sh -b RELEASE Jade --atf-image <full-path-to-ATF-image.slim>
...
BUILD/jade_tianocore_atf_1.01.100
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
An equivalent **Makefile** is also provided for those who wish to use it instead. Run `make -f edk2-ampere-tools/Makefile` for options.

**Note**
- For cross-compilation, use CROSS_COMPILE environment variable to specify the cross-compiler.
- For native compilation, make sure that the location of the compiler invocations has been added to the PATH environment variable.
