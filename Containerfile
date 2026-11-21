# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
## SINGLE DIFFERENCE FROM hurunagus-hyprland: the base.
## hurunagus-hyprland builds on ghcr.io/ublue-os/base-main (ublue's minimal
## "core" base, no desktop). This image builds on Bazzite, the
## KDE-Plasma/gaming edition of the same Universal Blue family.
##
## Bazzite's own Containerfile derives from ghcr.io/ublue-os/kinoite-main
## (Fedora 45), so what arrives with this base and NOT with base-main:
##   * KDE Plasma 6 + kwin, with `plasma.desktop` as a Wayland session
##   * plasmalogin (plasma-login-manager) as the display manager, so SDDM is
##     not installed -- build.sh installs it and takes the
##     display-manager.service alias over
##   * the gaming stack: Steam, gamescope, distrobox, MangoHud, and ~28
##     out-of-tree kmod-* packages (v4l2loopback, xone, xpadneo, ...) built
##     against Bazzite's own kernel
##   * Bazzite's first-boot services (bazzite-hardware-setup,
##     bazzite-flatpak-manager, uupd.timer) and its ujust recipe set
##   * Bazzite's kernel, kernel-<ver>-ogc<n>.fc45, which the kernel phase
##     below swaps out for kernel-cachyos exactly as on base-main. The kmod-*
##     packages are built for the ogc kernel, so they go with it -- they cannot
##     load into a CachyOS kernel.
##
## Everything this image does ON TOP of its base is the hurunagus-hyprland
## payload: the Omarchy runtime (Omedora COPR), the CachyOS kernel swap,
## Secure Boot signing of that kernel, the SDDM Omarchy theme with the user
## picker, the Hurunagus settings payload and the baked apps.
##
## Fedora line: bazzite:latest tracks Fedora 45 (45.20261117.1 at the time of
## writing) and the Omedora COPR we install from publishes fedora-44-x86_64 and
## fedora-45-x86_64 only, so pin a date tag here if you need a reproducible
## build.
FROM ghcr.io/ublue-os/bazzite:latest
## Other possible base images include:
# FROM ghcr.io/ublue-os/base-main:latest    (what hurunagus-hyprland uses)
# FROM ghcr.io/ublue-os/bazzite-gnome:latest (the GNOME edition, kinoite -> silverblue)
# FROM ghcr.io/ublue-os/aurora:stable
#
# The kernel is NOT the base image's stock Fedora kernel: build.sh swaps in
# kernel-cachyos (BORE scheduler, 1000 Hz, x86_64-v3) from the bieszczaders
# COPR, so the baked kernel version moves on every build. It is then signed for
# Secure Boot with the hurunagus kernel signing key (phase 3/4, and see
# system_files/usr/share/hurunagus/secureboot/README.md). Secure Boot stays OFF
# unless you turn it on, and turning it on needs one MOK enrollment per machine
# (ujust enroll-hurunagus-kernel-key), because firmware only trusts keys it has
# been told about.

### CACHE-BUSTING INPUTS
## The build is split into three layers below, ordered by how often their
## content really changes. A layer is invalidated when the build arg it
## references changes, so freshness is paid for where it is needed instead of
## throwing the whole layer cache away (`--no-cache`, which this replaced).
##
##   OMEDORA_BUST  every build (CI passes the run id). The Omedora COPR mutates
##                 between builds of the same commit, so the volatile tail is
##                 always re-resolved. This is the old --no-cache, scoped down.
##   KERNEL_BUST   weekly scheduled builds and manual "fresh" runs: re-resolve
##                 the CachyOS kernel from its COPR.
##   ALL_BUST      weekly scheduled builds and manual "fresh" runs: rebuild every
##                 layer from scratch, i.e. exactly what --no-cache used to do.
ARG OMEDORA_BUST=0
ARG KERNEL_BUST=0
ARG ALL_BUST=0

### [IM]MUTABLE /opt
## Fedora's base image symlinks /opt -> /var/opt. RPMs such as brave-origin
## unpack into /opt and fail with "cpio: mkdir failed - File exists" unless
## /opt is a real directory.
RUN rm /opt && mkdir /opt

### MODIFICATIONS
## Everything (packages, SDDM, Omarchy defaults, Hurunagus overrides) happens in
## build.sh. It is mounted at /ctx so it can see build_files/ and system_files/.
## Each RUN below is one phase (see the header of build.sh) and one cacheable
## layer; ALL_BUST is threaded through all of them so a scheduled build can force
## a full rebuild the way --no-cache used to.

## Phase 1/4 -- the stable bulk: repos, the whole package install, system files,
## services. This is the ~10 minute part and the one worth reusing.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    ALL_BUST="${ALL_BUST}" /ctx/build.sh base

## Phase 2/4 -- the CachyOS kernel swap and its initramfs. The kernel COPR moves
## on its own schedule, so this is refreshed by the weekly build rather than by
## every push.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    ALL_BUST="${ALL_BUST}" KERNEL_BUST="${KERNEL_BUST}" /ctx/build.sh kernel

## Phase 3/4 -- Secure Boot signing of the kernel image. Its own layer on purpose:
## the layer cache key CANNOT see a build secret's contents, so signing must not
## ride inside the kernel layer -- a cached kernel layer would ship an unsigned
## kernel on an otherwise green build, and the phase's own assertion could not
## catch it, because a cached layer is not executed at all. A new instruction runs
## at least once, and rotating the key means committing a new certificate, which
## is read from the image (phase 1) and so invalidates this layer by itself.
## The secret is optional here only so that PR builds, which receive no secrets,
## can pass --build-arg SB_SIGNING=off and still build; with signing on and no
## key the phase fails, deliberately.
ARG SB_SIGNING=on
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=sb_signing_key,required=false \
    SB_SIGNING="${SB_SIGNING}" \
    SB_SIGNING_KEY_FILE=/run/secrets/sb_signing_key \
    /ctx/build.sh sign

## Phase 4/4 -- the volatile tail: re-resolve the Omedora payload, re-mirror its
## SDDM theme, clean build artifacts. Invalidated on every build.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    ALL_BUST="${ALL_BUST}" OMEDORA_BUST="${OMEDORA_BUST}" /ctx/build.sh fresh

# Rebrand system identifiers in /usr/lib/os-release.
#
# Bazzite's os-release carries more keys than base-main's, and the ones this
# sed does not match are left as they are on purpose: it is still a Bazzite
# (kinoite-derived) system underneath, and VERSION ("45.<date>.<n> (Kinoite)")
# and CPE_NAME describe that honestly. What is rewritten is the identity a user
# or a tool reads first -- and omarchy-distro keys off ID= plus the
# /run/ostree-booted marker, which is why ID stays "fedora" here exactly as it
# does on hurunagus-hyprland (ID=fedora + booted from a deployment ->
# `fedora-ostree`, the distro token Omedora dispatches on).
#
# LOGO is rewritten because Bazzite sets LOGO=bazzite-logo, which would put the
# Bazzite mark in firmware/plymouth/About surfaces; this image ships omarchy.png
# in /usr/share/pixmaps, which is what the key resolves against.
RUN sed -i \
    -e 's/^ID=.*/ID=fedora/' \
    -e 's/^ID_LIKE=.*/ID_LIKE="fedora"/' \
    -e 's/^NAME=.*/NAME="OmarchyBazzite"/' \
    -e 's/^PRETTY_NAME=.*/PRETTY_NAME="OmarchyBazzite"/' \
    -e 's/^VERSION_CODENAME=.*/VERSION_CODENAME=omarchybazzite/' \
    -e 's/^VARIANT=.*/VARIANT="OmarchyBazzite"/' \
    -e 's/^VARIANT_ID=.*/VARIANT_ID=omarchybazzite/' \
    -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="omarchybazzite"/' \
    -e 's/^LOGO=.*/LOGO=omarchy/' \
    /usr/lib/os-release

# Copy custom Flatpak list into the system configuration path. The first-boot
# flatpak-system-install.service installs anything missing.
COPY system-flatpaks.list /usr/share/ublue-os/flatpaks/system-flatpaks.list

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
