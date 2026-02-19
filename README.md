# BlackBox

BlackBox is a compact proxy chain environment (mihomo + Tor + i2p) based on Debian Trixie on `crosvm`.
It provides:

- Guided first-run setup
- Layered disk (R/O debian base image with R/W qcow2 layer)
- Three runtime persistence modes (Full, Half, None)
- Allow local config import for mihomo
- Android 15 support (Experimental)
- Emergency reboot (Optional): In emergency situation when you don't have time to clean up manually, just reboot your phone and script in /data/adb/boot-completed.d will take care of the rest of clean up.

## Disclaimer

Use only in authorized, legal environments.
You are fully responsible for compliance with local laws and regulations.

## Requirements

- Root access (KernelSU or Magisk, if Magisk Alpha then you need have [additional patch](https://github.com/Alexjr2/magisk_alpha_fix_termux_tsu) applied before use)
- `/dev/gunyah` available
- `sudo`, `wget`, `qemu-img`

Install missing packages in Termux:

```bash
pkg install -y root-repo sudo wget qemu-utils
```

## Quick Start

Download and run:

```bash
wget https://github.com/omen3666/BlackBox/raw/refs/heads/main/blackbox_download_and_run.sh
chmod +x blackbox_download_and_run.sh
./blackbox_download_and_run.sh
```

On first run, the script will:

1. Show legal notice and ask confirmation. (Remember, you have to be responsible for what you have done)
3. Select persistence mode.
4. (For full of half persistent modes) optionally ask whether to enable emergency reboot cleanup.

Then it downloads required runtime assets and enters the main menu.
For `none` mode, runtime downloads are deferred to each VM launch (ephemeral path).

## Persistence Modes

### Full persistence

- Uses `~/.blackbox/runtime/session_diff.qcow2`
- Which means all changes are persistant

### Semi persistence

- Uses `/tmp/session_diff.qcow2`
- Persistence is temporary (depends on `/tmp` lifecycle, usually gone after reboot)

### No persistence

- Designed for minimal residue
- Every launch is treated like a fresh run path
- Runtime files are prepared under `/tmp` and recreated each run
- Ephemeral artifacts are cleaned after VM exit
- The setup config is not persisted

## Local Config Transfer Mode

Use menu option `2` and place config at one of the Termux storage candidates, typically:

- `Downloads/config.yaml`

The script copies it into the VM shared staging directory and boots VM in transfer mode then copy it into VM using `shared-dir` feature [Learn More](https://crosvm.dev/book/devices/fs.html).

## Emergency Reboot (Optional)

Available only for persistent modes (`full` / `half`).

When enabled, the script installs a boot task at:

- `/data/adb/boot-completed.d/blackbox_emergency_cleanup.sh`

Runtime behavior:

1. Before VM launch, script creates a running flag:
   - `/data/adb/boot-completed.d/.blackbox_vm_running.flag`
2. On normal VM exit, the flag is removed.
3. If device reboots without exiting VM normally, the flag will remain and the script will detects it and enter clean up procedure, boot task waits for [Credential Encrypted Storage](https://source.android.com/docs/security/features/encryption/file-based?hl=zh-cn#storage-classes) to decrypt (when you unlock the lockscreen after reboot):
   - `getprop sys.user.0.ce_available == true`
4. Then it removes BlackBox runtime data automatically.

To avoid false positives, script startup also auto-clears stale flags when no `crosvm` process exists.

## Android LD-Preload Notes

At runtime, preload libraries are selected by environment:

- Android 15 chain (the order CANNOT be changed):
  - `libbinder_ndk.so:libbinder.so:liboplusaudiopcmdump.so`

Libraries are downloaded in first setup.

## Files and Paths

Primary state directory:

- `${HOME}/.blackbox`

Important subpaths:

- `${HOME}/.blackbox/runtime`
- `${HOME}/.blackbox/prebuilt`
- `/tmp/blackbox_runtime`
- `/tmp/blackbox_prebuilt`

## Related Scripts

- `blackbox_download_and_run.sh`: runtime launcher and menu, usually you just need to download and run it
- `build_blackbox.sh`: Build BlackBox from source
- `init.sh`: VM-side init/service script

## CREDIT

[Mihomo](https://github.com/MetaCubeX/mihomo/tree/Meta): Unified Proxy Kernel with the highest compatibility and the richest feature

[The Tor Project](https://www.torproject.org/): The non-profit organization works hard for privacy and anonymity

[I2P](https://i2p.net/): End-to-End encrypted and anonymous Internet

[I2PD](https://github.com/PurpleI2P/i2pd): Full-featured C++ implementation of I2P client

[GrapheneOS](https://grapheneos.org/): Demystify the idea of Emergency reboot

[ZygiskNext](https://github.com/Dr-TSNG/ZygiskNext): Demystify the detailed way of Emergency reboot

[CrosVM](https://github.com/google/crosvm): Google's VM front-end interface for light weight VM

[CrosVM-on-android](https://github.com/bvucode/Crosvm-on-android)/[gunyah-on-sd-guide](https://github.com/polygraphene/gunyah-on-sd-guide): Figure out basic steps of using CrosVM on Rooted Android with pKVM support
