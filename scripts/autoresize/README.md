# qemu-display-autoresize

Make a Hyprland guest follow the QEMU window when you resize it.

Written by Claude

## The problem

Everything works except the last step:

1. You resize the QEMU window; QEMU regenerates the EDID.
2. The guest kernel reads it — `/sys/class/drm/<conn>/modes` updates.
3. The kernel fires a DRM hotplug uevent, and Hyprland receives it.
4. aquamarine logs `Skipping connector <name>, has crtc N and is connected`.

Step 4 is the bug. `scanConnectors()` calls `SDRMConnector::init()` — the only
code that parses EDID and builds the mode list — exclusively for connectors it
has never seen. A connector that stays `connected` across a hotplug takes the
fast path and keeps its boot-time mode list forever. That assumption holds for
physical monitors and breaks for virtio-gpu, where the EDID changes without the
connector ever disconnecting.

Consequences: `hyprctl monitors` shows a stale `availableModes`, `mode =
"preferred"` can only ever resolve to the resolution that was current at login,
and `hyprctl reload` does not help. There is no config flag or env var to force
a re-probe (checked against aquamarine `main`); forcing one via
`/sys/class/drm/<conn>/status` needs root and tears the output down.

## The fix

Watch for the hotplug the kernel *does* emit, read the new preferred mode from
sysfs, and hand it to Hyprland explicitly — bypassing the stale mode list.
Hyprland accepts a custom mode that isn't in its list.

Two triggers:

- **DRM uevent** — the resize itself.
- **`configreloaded`** on Hyprland's socket2 — any reload re-applies
  `mode = "preferred"` from `monitors.lua`, which resolves against the stale
  list and snaps the display back, with no uevent to announce it.

The service also pins the current mode into `monitors.lua`, replacing
`mode = "preferred"` with the real resolution, so a reload is correct on its own
rather than being repaired afterwards. Only the `mode` field of the generic
catch-all line is touched; `scale` stays owned by
`omarchy-hyprland-monitor-scaling`.

## Install

```sh
./install.sh              # from anywhere; resolves its own directory
bash install.sh           # if the +x bit was lost (e.g. extracted from a ZIP)
./install.sh --uninstall
```

Installs `~/.local/bin/qemu-display-autoresize`, its `ExecStop` helper
`qemu-display-autoresize-reset`, and a user unit enabled via
`graphical-session.target`. No root, nothing outside `$HOME`.

Requires: `hyprctl jq socat udevadm logger stdbuf`.

```sh
journalctl --user -b -t qemu-display-autoresize    # logs
systemctl --user status qemu-display-autoresize    # state
```

## Notes

- **Safe on real hardware.** It only acts on connectors whose driver is
  `virtio*`, and the unit sets `ConditionVirtualization=vm`. On a physical
  machine the cached mode list is already correct, and forcing the preferred
  mode would trample a deliberate lower resolution.
- **Mode pinning needs Omarchy's `monitors.lua` layout.** Without a matching
  catch-all line the write is skipped; resizes still work, but a config reload
  reverts until the next resize.
- **A pinned mode must never survive a reboot**, which is what the `ExecStop`
  helper enforces. The QEMU window always starts small, so a stale pin makes
  Hyprland modeset a resolution that does not match the window -- pointless at
  best, and it leaves the compositor disagreeing with the host until the first
  correction lands. If the session dies without a clean stop (hard reset, power
  loss) the pin can survive anyway; clear it by setting `mode` back to
  `"preferred"` by hand.

  This is hygiene, *not* a fix for the separate black-screen-on-boot bug in this
  setup. Writing the correct mode before the display manager starts was tested
  and made no difference, so a mismatched initial modeset is not what causes
  that.
- **`monitors.lua` becomes machine-specific** — it names a resolution instead of
  asking for `preferred`. Set it back to `"preferred"` by hand if you move the
  config to a physical machine.
- **Scale can collapse to 1x.** Hyprland only accepts scales dividing the mode
  into whole logical pixels (1/120 steps), so an awkward window size leaves 1x
  as the only valid scale. Size the window so `gcd(w, h)` is generous —
  multiples of 120 in both dimensions give the full range. Your configured scale
  is read back from `monitors.lua` and returns when it fits again.
- **One config reload per resize.** Pinning the mode rewrites `monitors.lua`,
  which Hyprland auto-reloads; that reload re-applies the mode already on
  screen, so nothing visibly changes, and it settles immediately.
