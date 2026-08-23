# Omarchy for Windows on Hyper-V with GPU acceleration

(this setup isn't limited to Omarchy, but that is what I'm trying to run today)

## Why?

I wanted to try Omarchy in a VM to see what all the fuss is about, but no hardware to dedicate
at the moment, and all I could use as host was this Windows machine.

However, because this box also uses WSL2, Windows is already running on Hyper-V, which
makes the easy options work badly or not at all.

If you are NOT running Windows on Hyper-V (if you're using WSL2, you are), this repo
might be overkill for you. Might still work, though.

## The problem

- Running as a proper Hyper-V guest doesn't virtualize GPU
- Running on QEMU/KVM inside WSL2 could in theory give us GPU rendering, then blitted into a buffer, and WSLg/RDP/VNC'd to a window, which is also not ideal 
- Running on VMware... idk I don't run VMware
- Running on VirtualBox... idk I don't run VirtualBox
- Running on basic QEMU doesn't give us much of GPU either

## The solution

Use [WINQ-EMU](https://github.com/cmspam/winq-emu) as base to get GPU working, and keep tinkering until stuff works.
My first attempts required many QEMU flag customizations, and everything was still unusably slow and jittery. Bummer.

I eventually figured out the problems were interrupt related. Long story short, QEMU 11 fixes things over QEMU 10
that we need to get interrupts working correctly under Hyper-V, but at the same time broke QEMU startup on targets
such as *exactly my setup*.

To that end, we patch the binaries from WINQ-EMU to nop some ifs, the flags we need now work, and everything runs
fast and with GPU. See the [patch/](patch/) directory for sources for the patch, which contains further details. 

## Instructions

- Download and install [WINQ-EMU Alpha 10](https://github.com/cmspam/winq-emu/releases#release-alpha10). Do **NOT** use a different version, it **MUST** be **Alpha 10**. I am going to assume you installed to **C:\WINQ-EMU** which is the default.
- Download the [Omarchy Quattro ISO](https://iso.omarchy.org/omarchy-4.0.0.iso) and save it to the `vm` directory of your *WINQ-EMU* install.
- Download the ZIP of this repo (*Code* drop-down button above the file listing, select *Download ZIP*)
- Extract `omarchy.bat` and the `patch` directory from the ZIP into your *WINQ-EMU* directory

Now, again assuming you installed to **C:\WINQ-EMU**, you should have *at least* these new files:
- C:\WINQ-EMU\vm\omarchy-4.0.0.iso
- C:\WINQ-EMU\patch\whpx_nested_patch.exe
- C:\WINQ-EMU\omarchy.bat

At the top of *omarchy.bat* you can configure your setup. Defaults are 4 CPU, 8 GB RAM, and 64 GB disk. If you want 
to change those, do that before continuing.

The *omarchy.bat* file should setup everything for you at first run, patching QEMU, creating EFI vars, and creating
your disk (pre-allocating!). It will then boot into the Omarchy installer. When that is complete, you need to start
*omarchy.bat* **again** to actually start Omarchy.

Et voila, a fully GPU accelerated Omarchy instance on your Windows-on-Hyper-V box. If you're lucky!

All of this takes about 5 minutes start to finish.

## Must-knows

- At Omarchy boot, immediately after the boot selection, you may be greeted by a black screen. It is probably waiting for your disk decryption password but the prompt is invisible. Pressing ENTER usually fixes that.
- Hyprland sometimes errors during boot, you'll get a flickering black screen, or nothing at all. Ctrl+Alt+F2, login, `sudo systemctl restart sddm`.
- There are some if ands buts with WINQ-EMU's GPU support. I do recommend you check the [repo](https://github.com/cmspam/winq-emu).
- Chromium (and anything Chromium based) is known to have some issues. Recommend setting Firefox as your browser in Omarchy, or forcing software rendering for Chromium things; if you must run Chromium, be sure to disable hardware video decoding in `chrome://flags`.
- Virtualization inside Omarchy probably does not work (QEMU and friends).

## Extras

### QEMU display auto-resize

See [scripts/autoresize/](scripts/autoresize/)

`git clone` this repo inside your installation, and run the installer. Now the resolution 
of Omarchy follows the size of the QEMU window.

Notes: 
- Ctrl+Alt+F full-screens QEMU
- Not resizing the window at all until the GUI is fully loaded is advised

## Disclaimer

This works for me on my AMD 9950x3D + Nvidia 4090, Windows 11 Pro 21H2. In `Windows Security -> Device Security -> Core Isolation`, I have `Memory Integrity` turned **OFF**. Claude feels that is relevant information, having it **ON** might stop all this from working - or it might not!
