# PatchFd

## Terminology

- FD: Flash Device
- FV: Firmware Volume

## Issue

- FD binary is the final product of EDK2 compilation process.
- FD is made up by several FV binaries. FV, in turn, is the combination of various modules.
- The FV which contains the PrePeiCore module is normally known as the FV\_MAIN.
- For ARM64 system, the offset 0 of the FD must contain a valid instruction.
- During the compilation process, BaseTools will add this such an instruction to the offset 0 of the FV\_MAIN
- It should not cause any issues if FV\_MAIN is the first FV within the FD. However, It will become an issue if FV\_MAIN is located a different location within the FD other than the first.

## Solution

- PatchFd was created to address the issue above.
- It will add a valid instruction to the offset 0 of the FD no matter where FV\_MAIN is.

## How to use

There are separate versions for x86\_64 and AArch64 Linux:

- PatchFd\_x86\_64
- PatchFd\_aarch64

```
Usage: PatchFd [options] <input FD file>

optional arguments:
  -h, --help
            Show this help message and exit
  --version
            Show program's version number and exit
  -v, --verbose
            Print informational statements
```
