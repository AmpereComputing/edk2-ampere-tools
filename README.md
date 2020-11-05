This repository contains various instructions and tools to assist in the 
compilation and final build of Tianocore for Ampere's platforms. It is
an extension of what is already provided in the README located at
`edk2-platforms/Platform/Ampere/README.md`

# Manual Building

It is assumed that your build environment has been set up appropriately
based on `edk2-platforms/Platform/Ampere/README.md`.

Througout this document, the Mt. Jade platform is used to illustrate
various steps to arrive at a final Tianocore UEFI image that can be 
flashed to the platform.

## Building UEFI image

Building UEFI image without Linuxboot

```
$ cd edk2-platforms && build -a AARCH64 -t GCC5 -b RELEASE -D SECURE_BOOT_ENABLE -p Platform/Ampere/JadePkg/Jade.dsc

```

Building UEFI image with Linuxboot

```
$ cd edk2-platforms && build -a AARCH64 -t GCC5 -b RELEASE -D SECURE_BOOT_ENABLE -p Platform/Ampere/JadePkg/JadeLinuxboot.dsc

```

The resulted image will be at 

`edk2-platforms/Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd`

## Signing the image

Download the pre-built fiptool and cert_create binaries from this repository
and and set your PATH environment to include the location where these are
put.

```
$ cd edk2-platforms
$ cert_create -n --ntfw-nvctr 0 --key-alg rsa --nt-fw-key Platform/Ampere/JadePkg/TestKeys/Dbb_AmpereTest.priv.pem --nt-fw-cert Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd.crt --nt-fw Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd
$ fiptool create --nt-fw-cert Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd.crt --nt-fw Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fd Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fip.signed
```

## Integrating Board Setting and Ampere's Arm Trusted Firmware (ATF)

You need to download the appropriate Ampere ATF image from Ampere Connect portal at https://amperecomputing.com/customers/. Refer to the edk2-platforms release note for compatible ATF image version.

and export ATF_IMG variable

Build Board Settings

```
$ cd edk2-platforms
$ python Platform/Ampere/JadePkg/Tools/nvparam.py -f Platform/Ampere/JadePkg/jade_board_setting.txt -o Build/Jade/RELEASE_GCC5/FV/jade_board_setting.bin

```

Build UEFI +Board Setting + ATF image

```
$ dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > Build/Jade/RELEASE_GCC5/FV/jade_tianocore_atf.img
$ dd bs=1 conv=notrunc if=${ATF_IMG} of=Build/Jade/RELEASE_GCC5/FV/jade_tianocore_atf.img
$ dd bs=1 seek=2031616 conv=notrunc if=Build/Jade/RELEASE_GCC5/FV/jade_board_setting.bin of=Build/Jade/RELEASE_GCC5/FV/jade_tianocore_atf.img
$ dd bs=1024 seek=2048 if=Build/Jade/RELEASE_GCC5/FV/BL33_JADE_UEFI.fip.signed of=Build/Jade/RELEASE_GCC5/FV/jade_tianocore_atf.img

Result: Build/Jade/RELEASE_GCC5/FV/jade_tianocore_atf.img

```
Build Tianocore Capsule

```
$ openssl dgst -sha256 -sign Platform/Ampere/JadePkg/TestKeys/Dbb_AmpereTest.priv.pem -out Build/Jade/RELEASE_GCC5/FV/jade_tianocore_atf.img.sig Build/Jade/RELEASE_GCC5/FV/jade_tianocore_atf.img
$ cat Build/Jade/jade_tianocore_atf.img.sig Build/Jade/jade_tianocore_atf.img > Build/Jade/RELEASE_GCC5/FV/jade_atfedk2.img.signed
$ build -a AARCH64 -t GCC5 -b RELEASE -p Platform/Ampere/JadePkg/JadeCapsule.dsc
$ cp Build/Jade/RELEASE_GCC5/FV/JADEFIRMWAREUPDATECAPSULEFMPPKCS7.Cap Build/Jade/jade_tianocore_atf.cap

Result: Build/Jade/jade_tianocore_atf.cap
```
