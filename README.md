# OmarchyBazzite

Omarchy and Bazzite made a baby. 

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
