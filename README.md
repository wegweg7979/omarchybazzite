# OmarchyBazzite

Declarative, atomic, immutable Fedora with the **Omarchy** (Hyprland) desktop, built on the **Bazzite** base image.

A clone of [hurunagus-hyprland](https://github.com/wegweg7979/hurunagus-hyprland) with one thing changed: the base image.

| | base |
|---|---|
| hurunagus-hyprland | `ghcr.io/ublue-os/base-main:latest` — Universal Blue's minimal core, no desktop |
| **OmarchyBazzite** | `ghcr.io/ublue-os/bazzite:latest` — Bazzite: KDE Plasma 6 + the Universal Blue gaming stack |

Everything built on top is the hurunagus-hyprland payload, unchanged: the Omarchy runtime (Omedora, forked for immutable Fedora), the CachyOS kernel swap, Secure Boot signing of that kernel, the SDDM Omarchy theme with its user picker, the Hurunagus settings payload, and the baked apps (huruwave, airgraph, huru-calendar, hyprglaze, flea, icloud-for-omarchy, rclone, hermes) plus the system flatpak list.

## What the base change actually drags in

- **KDE Plasma is installed.** Bazzite derives from `kinoite-main`, so Plasma 6, kwin and the Plasma packages are all present. Its `plasma.desktop` session is removed by the build, so the only session SDDM offers is the Omarchy/Hyprland one.
- **plasmalogin → SDDM.** Bazzite's display manager is `plasma-login-manager`; this image installs SDDM and takes the `display-manager.service` alias over, exactly as on hurunagus-hyprland.
- **The gaming stack comes along.** Steam, gamescope, distrobox, MangoHud, Bazzite's first-boot services (`bazzite-hardware-setup`, `bazzite-flatpak-manager`) and its `ujust` recipes are inherited.
- **Bazzite's kernel is replaced.** The base ships `kernel-*-ogc*.fc45`; the kernel phase swaps in `kernel-cachyos` and generates its initramfs. Bazzite's ~28 out-of-tree `kmod-*` packages are built against the ogc kernel, so they go with it — they cannot load into a CachyOS kernel.

## Install (rebase)

```sh
# 1. rebase to the unsigned image, to get the signing keys and policies installed
rpm-ostree rebase ostree-unverified-registry:ghcr.io/wegweg7979/omarchybazzite:latest

# 2. reboot to complete the rebase
systemctl reboot

# 3. rebase to the signed image
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/wegweg7979/omarchybazzite:latest

# 4. reboot again
systemctl reboot
```

Your existing `$HOME` is preserved across the rebase — atomic rebases never touch it. That means the Omarchy defaults this image ships in `/etc/skel` are **not** seeded into your current user's home. To adopt them, run this once **after your first login**:

```sh
omarchy-reinstall-configs
```

New users (fresh installs, or accounts created after the rebase) get them automatically.

## Build

```sh
just build                # container image
just build-qcow2          # + bootable disk image (bootc-image-builder)
```

The build needs network access plus the omedora and app COPRs. Secure Boot signing needs the kernel signing secret (`SB_SIGNING_KEY`); `--build-arg SB_SIGNING=off` is the explicit opt-out PR builds use, and that kernel ships unsigned.

## References

- Bazzite: https://bazzite.gg — https://github.com/ublue-os/bazzite
- ublue-os image-template: https://github.com/ublue-os/image-template
- Omarchy: https://github.com/omacom/omarchy
- Omedora (omeadora): https://github.com/AndrewGaspar/omadora
- hurunagus-hyprland (this clone's parent): https://github.com/wegweg7979/hurunagus-hyprland
- hurubase — safe rebase helper: https://github.com/wegweg7979/hurunagus-rebase
