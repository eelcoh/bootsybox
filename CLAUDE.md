# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

This repository ("bootsybox") contains a design conversation (`conversation-with-ai`, a saved chat transcript, partly in Dutch) that lays out the full target architecture for an immutable, multi-tenant Linux desktop distribution, plus a first, partial implementation of it — see "Current implementation" below for exactly what exists and what's still just design. Treat the transcript as the design record for anything not yet built; treat the sections below as authoritative for anything that is.

Related repositories referenced as prior art / inspiration (not vendored here):
- https://github.com/eelcoh/bootsy-linux
- https://github.com/eelcoh/kubevirt-host-bootc-image
- https://github.com/eelcoh/zirconium-base

## What bootsybox is

A bootc-based (bootable container) immutable Linux host that gives every regular user a fully isolated, GUI-capable desktop running inside a rootless Podman container, rather than a login session on the host itself. The goal is a distribution that is:
- **Immutable at the base**: the host root filesystem is built from a `Containerfile` and shipped as an OCI image; only `/var` and `/etc` are writable. Updates are atomic (`bootc switch` / `bootc update`), with automatic rollback on failure.
- **Isolated per user**: each user's entire desktop environment — window manager, apps, dotfiles, Flatpaks, nested containers — lives inside their own container, never on the host.
- **Reproducible**: a user's environment is declared in a `distrobox.ini` manifest and can be recreated identically (`distrobox assemble create`) on any other host running this distribution, by carrying just their home directory / dotfiles.

## Core architecture

Two layers, cleanly separated:

1. **Host layer (bootc)** — kernel, drivers, `greetd` (login manager), `podman`, and nothing user-facing. The host never runs a window manager or user applications itself in the latest iteration of the design (see "Design evolution" below); it only brokers hardware access. Base image is **Fedora bootc** (`quay.io/fedora/fedora-bootc:44`), not CentOS Stream bootc as most of the transcript assumes — `greetd` has no package in CentOS Stream 9's repos, only in Fedora's.
2. **User layer (rootless Podman container)** — one long-lived container per user (`podman create --name desktop-env-$USER ...`), started at login and torn into by `podman exec`. This is where the window manager, Flatpaks, Distrobox (nested containers), dotfiles, and all user state live. Base image is `quay.io/fedora/fedora-toolbox:44` — the transcript's `quay.io/toolbx-images/fedora-toolbox` repo isn't anonymously accessible (`unauthorized` on pull); `quay.io/fedora/fedora-toolbox` is the correct, working repo.

Key mechanisms tying the layers together:

- **Home persistence**: `/var/home/$USER` on the host is bind-mounted to `/home/$USER` in the container (`-v /var/home/$USER:/home/$USER:rw`), so everything the user creates survives container rebuilds and host reboots.
- **Login flow**: `greetd` (optionally themed via `regreet`) on the host authenticates the user, then execs a host script (`/usr/local/bin/launch-user-container.sh`) that creates/starts the user's container and hands off control to it. `[default_session].user` in `files/etc/greetd/config.toml` is `"greetd"`, not the transcript's/upstream greetd docs' `"greeter"` — Fedora's `greetd` RPM only creates a `greetd` sysuser (`/usr/lib/sysusers.d/greetd.conf`), no separate `greeter` account exists. Using a nonexistent user here doesn't error loudly: `greetd.service` (`Restart=always`, `RestartSec=1`, `StartLimitBurst=5`) just crash-loops silently and gets rate-limited within seconds, leaving a blank console with no login prompt — check `journalctl -u greetd` / audit logs for `unit=greetd ... res=failed` if this regresses. `launch-user-container.sh` derives the username via `USER=$(id -un)` rather than trusting an ambient `$USER` env var — greetd execs the session command directly with no login shell involved, so nothing sources profile scripts to set `$USER`, and the script's `set -u` turns a missing one into an immediate `unbound variable` exit on the very first line that uses it, before anything else runs.
- **Display**: Wayland only (never X11), because Wayland isolates input/output per client — X11 would let one user's container keylog or screen-scrape another user's session. The Wayland socket (`/run/user/$UID/wayland-0`) and `XDG_RUNTIME_DIR` are shared into the container.
- **GPU**: `--device /dev/dri` (and `/dev/kfd` for compute) is passed into the container so rendering is hardware-accelerated instead of falling back to software rendering.
- **Network/Bluetooth from inside the container** *(not yet implemented — design only)*: containers don't get raw access to the wifi/bluetooth hardware. The host's D-Bus system bus socket is already bind-mounted read-only (`/run/dbus/system_bus_socket`) by `launch-user-container.sh`, but no D-Bus policy file (`/etc/dbus-1/system.d/...`) granting the `users` group permission to talk to `org.bluez` / NetworkManager interfaces has been added yet — until that lands, Bluetooth pairing from inside the container won't work.
- **Nested containers**: because the host runs Podman rootless with user namespaces (subuid/subgid), users can run `distrobox create` *inside* their own container to spin up further sibling containers (e.g. a separate Ubuntu or Arch toolbox), with no root daemon involved anywhere in the chain. This requires `--device /dev/fuse` and `--security-opt unmask=ALL` on the outer container.
- **Session lingering is required, and isn't automated yet**: rootless Podman with `--cgroup-manager=systemd` parents containers under the target user's own `systemd --user` instance (`user@$UID.service`), not the system manager — `/etc/systemd/system/bootsybox-containers.slice` is a *system* unit and is actually inert for this flow; podman just auto-creates a same-named transient slice under the user's tree instead. `user@$UID.service` stops as soon as that user's last login session closes, which kills every container nested under it — defeating the entire point of `desktop-env-$USER` outliving any single login — unless `loginctl enable-linger $USER` has been run for that account. That can only be done as root (`org.freedesktop.login1.set-user-linger`'s default polkit policy is `auth_admin_keep`, so a user can't self-service it, and `launch-user-container.sh` runs unprivileged), so it belongs in the not-yet-implemented Kickstart `%post` (or equivalent user-provisioning step), not in the launch script. Until that lands, any test user must have `sudo loginctl enable-linger <user>` run for them manually once per boot before their container will survive session teardown.
- **Resource containment**: all user containers are placed in a systemd slice (`/etc/systemd/system/bootsybox-containers.slice`, invoked via `podman create --cgroup-manager=systemd --cgroup-parent=...`) with `CPUQuota` / `MemoryMax` limits, so one user's runaway process can't starve the host or other users. Named `bootsybox-containers.slice` rather than the transcript's `user-container-limit.slice` — that name collides with systemd's dash-based slice hierarchy (it's parsed as a child of `user.slice`) and produces a real ordering cycle; the transcript's `CPUSchedulingPolicy=` key was also dropped, as it isn't valid in a `[Slice]` section. The transcript's `podman create --slice=...` flag doesn't exist either — `podman create --help` has no `--slice`, only `--cgroup-parent`, which is what actually assigns a container to a systemd slice under `--cgroup-manager=systemd`. Verify any changes to the unit itself with `systemd-analyze verify`.
- **Update model** *(not yet implemented — design only)*: the transcript's launch script tracks an installed container version in `/var/home/$USER/.config/container_version` and rebuilds the container (never touching `/var/home`) when the host's `CURRENT_VERSION` changes. The current `launch-user-container.sh` has no version tracking — it only creates the container if it doesn't already exist.
- **Declarative per-user environments** *(not yet implemented — design only)*: a central `/etc/distrobox/central.ini` manifest, shipped in the bootc image, would be copied into a new user's home on first login and built via `distrobox assemble create`. Not wired up yet.

### Theming (Material You) *(not yet implemented — design only)*

- Config templates live under `/etc/skel/.config/{gtk-4.0,waybar,niri}` in the host image so every new user starts themed.
- `matugen` (run from inside the user's container) derives a Material Design 3 palette from the user's wallpaper and rewrites templated config files (`*.base.css` / `*.base.kdl` → `style.css` / `config.kdl`) for Waybar and Niri, then triggers a live reload (`niri msg action reload-config`).
- GTK4/libadwaita apps are forced into the theme via `~/.config/gtk-4.0/settings.ini` since libadwaita ignores traditional GTK theme switching.

### Design evolution: where the window manager runs

The design in the conversation evolves over its course — later sections supersede earlier ones on this point:
- **Earlier iterations** installed a specific WM (Niri) directly into the shared container image and had the host launch script exec it by name.
- **Final iteration** moves WM choice entirely into the user's container: the host launch script only creates the container and execs a generic `/home/$USER/.config/startup.sh` *inside* it; that script (seeded from `/etc/skel`) detects and launches whichever WM the user has installed (Niri, Sway, Hyprland, ...), selected via their own `distrobox.ini`. This requires `--privileged` and `-v /dev:/dev:rw`, since a compositor launched from a bare TTY needs direct `libinput`/DRM access. Treat this as the intended target architecture unless told otherwise — the host should stay maximally generic and WM-agnostic. The transcript also passed a handful of individual `--device` flags (`/dev/dri`, `/dev/kfd`, `/dev/fuse`, the controlling TTY) alongside `--privileged -v /dev:/dev:rw` — those are both redundant (the privileged full-`/dev` mount already grants everything they'd add) and actively harmful (`podman create --device` stats the path up front, so `--device /dev/kfd` hard-fails container creation on any host without an AMD GPU, e.g. any plain VM). Dropped in favor of just `--privileged -v /dev:/dev:rw`.

### Provisioning / deployment *(not yet implemented — design only)*

- **CI**: a GitHub Actions workflow (`.github/workflows/build-os.yml`, not yet created) is intended to build the host `Containerfile` with Podman and push it to GHCR on every push to `main`.
- **Installation**: a Kickstart file (`ks.cfg`) drives Anaconda to partition a disk and pull the built image directly via `ostreecontainer --url ghcr.io/...`, rather than a traditional package-based install. Root filesystem is **btrfs**, not the transcript's `xfs` (its `ks.cfg` snippet used `part / --fstype=xfs --grow`) — when `ks.cfg` is actually written, use `part / --fstype=btrfs --grow` instead. This also applies anywhere else a root filesystem type is chosen for this image (e.g. `bootc-image-builder --rootfs`, see below).

## Current implementation

The foundational milestone is built and **VM-verified end-to-end**: a host `Containerfile` and the login → per-user-container → in-container-WM hand-off. This is the only part of the design with real files on disk. Confirmed by actually booting a `bootc-image-builder`-produced qcow2 in QEMU: `greetd`/`agreety` authenticates a test user at the console, `launch-user-container.sh` creates and starts `desktop-env-<user>`, execs into it, and `startup.sh` correctly reports "No Window Manager found" (since none is installed) before control returns to the greeter — exactly the expected outcome for this milestone. The container also now survives that whole cycle instead of dying, once `loginctl enable-linger` is set for the test user (see the session-lingering bullet above). Every fix below was found this way, not by static review — the VM boot surfaced things `podman build`/`shellcheck`/`systemd-analyze` alone could not have.

Installing an actual WM (`dnf install -y niri`) inside the running container still hits a separate, unresolved snag: RPM `%triggerin` scriptlets for several packages (`systemd-udev`, `glib2`, `fontconfig`, `adwaita-icon-theme`, others) fail with exit 127, because they assume a real running `systemd` PID 1 and our container's PID 1 is just `/bin/sh -c "...; exec sleep infinity"` — this is a known class of issue installing desktop packages into non-systemd toolbox-style containers, not specific to our config. Workaround: `dnf install -y --setopt=tsflags=noscripts niri`. Even with that, `niri` wasn't confirmed actually launching by the end of the last session — this is open, unfinished follow-up work, separate from the (done) foundational milestone itself.

```
Containerfile                                   # FROM quay.io/fedora/fedora-bootc:44
files/
  usr/local/bin/launch-user-container.sh         # host script greetd execs on login
  etc/greetd/config.toml                         # plain agreety session, no theming yet
  etc/systemd/system/bootsybox-containers.slice   # CPU/memory limits for user containers
  etc/skel/.config/startup.sh                    # in-container: detects/execs niri or sway
```

`files/` mirrors absolute host paths one-to-one and is `COPY`'d into the image path-by-path from the `Containerfile` — when adding a new host-destined file, add it under `files/<same absolute path>` and add a matching `COPY` line, don't invent a different layout.

### Build & verify

- `podman build -f Containerfile -t bootsybox-host:dev .` — builds the host image. This is the primary check that the `Containerfile` and every file it `COPY`s are consistent; it also runs on a real Fedora bootc base so `dnf install` failures for packages referenced anywhere in this design (e.g. `greetd`, which does **not** exist in CentOS Stream repos — see above) surface immediately. Use `set -o pipefail` if piping the output through `tee`, or you'll silently lose a non-zero exit code.
- `shellcheck files/usr/local/bin/launch-user-container.sh files/etc/skel/.config/startup.sh` — lint both shell scripts. If `shellcheck` isn't installed locally, run it via `podman run --rm --security-opt label=disable -v "$(pwd)/files:/mnt/files:ro" docker.io/koalaman/shellcheck:stable /mnt/files/...` (the `--security-opt label=disable` is required on SELinux hosts, or the mount is unreadable inside the container).
- `systemd-analyze verify "$(pwd)/files/etc/systemd/system/bootsybox-containers.slice"` — catches invalid unit keys and ordering-cycle bugs like the one this file already had once (see above).
- `python3 -c "import tomllib; tomllib.load(open('files/etc/greetd/config.toml','rb'))"` — sanity-checks the greetd TOML.

There is no bootc host available to boot in this dev/CI environment itself, so none of the above alone proves the login flow works end-to-end — that requires an actual VM, and it has been done (see "Current implementation" above for the result). To repeat it: build a bootable disk image with `bootc-image-builder`, boot it under libvirt/qemu with a console, create a test user (with `loginctl enable-linger <user>` run once as root — required, see the session-lingering bullet above, or the container will die as soon as that user's login session ends), and confirm at the `greetd`/`agreety` prompt that logging in creates and enters a `desktop-env-<user>` container running `startup.sh` (which will correctly report "No Window Manager found" until a WM is `dnf install`ed inside that container).

`bootc-image-builder` needs both the host image built under the **same podman storage it mounts** (build with `sudo podman build ...` if you're mounting `/var/lib/containers/storage`, since a plain rootless `podman build` lands in `~/.local/share/containers/storage` instead and won't be found) and an explicit `--rootfs btrfs` flag — this container image doesn't carry default-root-filesystem metadata, so omitting the flag fails with `missing required info: DefaultRootFs`. Example:

```bash
sudo podman run --rm -it --privileged --pull=newer --security-opt label=type:unconfined_t \
  -v "$(pwd)/config.toml:/config.toml:ro" -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --rootfs btrfs localhost/bootsybox-host:dev
```

## Working in this repo

- When implementing pieces of this design, keep the host/container boundary strict: nothing user-installable or user-configurable belongs in the host `Containerfile` — it belongs in the container image, `/etc/skel`, or the user's own `distrobox.ini`.
- Scripts destined for the host (`launch-user-container.sh`, D-Bus policy, systemd slice, `Containerfile`) are trusted/admin-controlled; scripts destined for inside the user container (`startup.sh`, matugen templates) should be treated as user-editable and not assumed to be pristine.
- The source conversation (`conversation-with-ai`) is the design record, not documentation to keep in sync — once real Containerfiles/scripts exist, prefer reading and updating those directly rather than re-deriving requirements from the transcript.
