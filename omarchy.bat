@echo off
setlocal

set CPUS=4
set RAM=8G
set DISK=64G

set "BASE=%~dp0"
set "BASE=%BASE:~0,-1%"

if not exist "%BASE%\bin\qemu-system-x86_64.exe" (
  echo qemu-system-x86_64 not found in bin
  exit /b 1
)
if not exist "%BASE%\bin\qemu-system-x86_64w.exe" (
  echo qemu-system-x86_64w not found in bin
  exit /b 1
)

if not exist "%BASE%\bin\qemu-system-x86_64_patched.exe" "%BASE%\patch\whpx_nested_patch.exe" "%BASE%\bin\qemu-system-x86_64.exe"
if not exist "%BASE%\bin\qemu-system-x86_64w_patched.exe" "%BASE%\patch\whpx_nested_patch.exe" "%BASE%\bin\qemu-system-x86_64w.exe"

set PARAMS=
if not exist "%BASE%\vm\omarchy.qcow2" (
  if not exist "%BASE%\vm\omarchy-4.0.0.iso" (
    echo Please download omarchy-4.0.0.iso and put it in the vm subfolder
    exit /b 1
  )
  "%BASE%\bin\qemu-img.exe" create -f qcow2 -o preallocation=metadata "%BASE%\vm\omarchy.qcow2" %DISK%
  set PARAMS=-drive if=none,id=cd0,file="%BASE%\vm\omarchy-4.0.0.iso",format=raw,readonly=on -device virtio-blk-pci,drive=cd0,bootindex=0
)

if not exist "%BASE%\vm\efivars.fd" "%BASE%\bin\qemu-img.exe" create -f raw "%BASE%\vm\efivars.fd" 4M


set WINQ_VAAPI=1
"%BASE%\bin\qemu-system-x86_64_patched.exe" ^
  -machine q35 ^
  -accel whpx ^
  -cpu host ^
  -smp %CPUS% ^
  -m %RAM% ^
  -drive if=pflash,format=raw,unit=0,readonly=on,file="%BASE%\bin\share\edk2-x86_64-code.fd" ^
  -drive if=pflash,format=raw,unit=1,file="%BASE%\vm\efivars.fd" ^
  -object iothread,id=iot0 ^
  -drive if=none,id=hd0,file="%BASE%\vm\omarchy.qcow2",format=qcow2,cache=writeback,aio=threads ^
  -device virtio-blk-pci,drive=hd0,iothread=iot0,bootindex=1 ^
  -vga none ^
  -device virtio-vga-gl,blob=on,hostmem=4G,venus=on ^
  -display sdl,gl=on ^
  -device virtio-sound-pci ^
  -device virtio-net-pci,netdev=net0 ^
  -netdev user,id=net0,hostfwd=tcp::2223-:22 ^
  -device virtio-keyboard-pci ^
  -device virtio-tablet-pci ^
  -object rng-builtin,id=rng0 ^
  -device virtio-rng-pci,rng=rng0 ^
  %PARAMS%

if errorlevel 1 pause
