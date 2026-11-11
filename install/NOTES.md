# icc-brightness: dimming issue notes

Date: 2026-11-05

## What it is
- OLED laptop dims via `icc-brightness` (Python, by Udi Fuchs, modified by Kahlil Hodgson), installed in `/usr/local/bin` on 2024-12-08 with `icc-brightness-gen`.
- It dims with ICC colour profiles through colord (`colormgr`) rather than the hardware backlight, which avoids OLED flicker.
- `icc-brightness watch` is launched by gnome-session at login (journal tag `icc-brightness.desktop`). The autostart file was not found in `~/.config/autostart` or `/etc/xdg/autostart`.
- It watches `/sys/class/backlight/intel_backlight` (dnotify). The brightness keys change that value, which triggers the script.
- Profiles are written to `~/.local/share/icc/brightness_<n>_852.icc`. Values are rounded to 5% steps.

## Problem
After the screen turns off and you log in again, brightness stays dim. Pressing brightness-up doesn't help. You have to lower it and then raise it again.

## Root cause
- colord drops the profiles from the display device (`Scope: temp`) after a re-login or screen reset. The profile files and colord profile objects survive.
- The script only ran `device-add-profile` when it created a new profile.
- For an existing profile it called `device-make-profile-default` directly. That fails with `profile object path '.../icc_edc60df7..._dan_...' does not exist for this device`.
- The journal shows this error at every login.
- Reproduced: the `brightness_852_852` (full brightness) profile existed but was not attached. `icc-brightness set 852 852` failed with that error.

## Fix
- Always run `device-add-profile` (ignoring failure and "already added") before `device-make-profile-default`.
- The patched script is `icc-brightness` in the repo root. It was tested and applies cleanly.
- Install (needs sudo; the original is root-owned):
  ```
  sudo install -m755 icc-brightness /usr/local/bin/icc-brightness
  ```
  Then restart the watcher: `kill $(pgrep -f "icc-brightness watch")`, then `setsid icc-brightness watch >/dev/null 2>&1 &`. Or log out and back in.

## Sluggishness fix (also in the patch)
- Each change took ~0.9s. `colormgr get-devices-by-kind display` alone takes ~0.65s because it dumps all ~94 attached profiles. All colormgr device lookups are similarly slow.
- The patch caches the device path and only looks it up again if `make-profile-default` fails. Warm applies take ~0.22s.
- The signal handler used to drop events that arrived while it was busy, so rapid key presses could leave a stale level. It now sets a pending flag and re-applies the latest value.
- Install with `install/install.sh`.

## Status
- Installed 2026-11-05 ~21:37 via `install-icc-brightness.sh`. `/usr/local/bin/icc-brightness` matches the repo script.
- The original is backed up at `/usr/local/bin/icc-brightness.orig`. To roll back: `sudo cp -p /usr/local/bin/icc-brightness.orig /usr/local/bin/icc-brightness`, then restart the watcher.
- You reported that it responds quickly and works after the screen dims and you log in again. You're monitoring for further issues.
- To check for regressions: `journalctl --user -b -g "does not exist for this device"` should show no new entries.

## Open items
- The watcher only fires when the backlight value changes. If the profile is lost without a brightness change, it won't re-apply until a key is pressed. This did not show up in your post-login test.
- If it does appear, options are:
  - a hook on unlock or session-active (for example `gnome-session`/`loginctl` signals) that runs `icc-brightness apply`;
  - a periodic `apply` in the watch loop.
- The autostart entry that launches `icc-brightness watch` was never located, so check it if the watcher doesn't start at login.
- The upstream is Kahlil Hodgson's fork of Udi Fuchs' icc-brightness.

