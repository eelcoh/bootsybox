# CLAUDE.md

## Project

Bootsybox is an experimental Fedora bootc desktop host. The immutable host owns
boot, authentication and hardware arbitration. Each regular user's compositor,
applications and mutable package state live in a rootless Podman container.

The original design conversation is saved as `conversation-with-ai`, but its
commands were exploratory. This file, `docs/ROADMAP.md` and the implementation
are authoritative.

## Architecture

### Host image

- `quay.io/fedora/fedora-bootc:44`
- greetd/agreety authenticates on VT1.
- seatd owns the physical seat and exposes `/run/seatd.sock` to members of
  `bootsybox-seat`.
- `launch-user-container.sh` pulls the declared desktop image, replaces an
  outdated outer container while preserving the bind-mounted home, and runs the
  graphical session as the authenticated UID.
- The container receives the seatd socket, read-only udev/DRM discovery data,
  `/dev/fuse`, the user's home and machine ID. It does not receive raw input,
  host VTs, the host runtime directory or the host system bus.

### Desktop image

- `ghcr.io/eelcoh/bootsybox-desktop:44`, built by `desktop/Containerfile`.
- Contains niri, Waybar, Alacritty, Fuzzel, Mako, Xwayland Satellite, Flatpak,
  Distrobox, Mesa, D-Bus, GNOME/GTK portals and GNOME Keyring.
- Its init entrypoint creates a user matching the authenticated host UID/GID.
- `bootsybox-session` starts a private D-Bus session, launches niri through host
  seatd, exports the Wayland environment to D-Bus activation, and starts
  notifications, secrets and portals.
- The outer container is persistent but session-scoped. Logout stops it and
  returns control to greetd; the next login starts it again.

`--userns=keep-id` and `--group-add keep-groups` preserve the user identity and
seat group. SELinux label separation is currently disabled because the desktop
shares an existing home and host socket. This is a documented hardening gap,
not VM-grade isolation.

## Repository layout

```text
Containerfile                         host image
desktop/Containerfile                 reproducible desktop image
desktop/files/usr/local/bin/          container init and session launchers
files/                                files copied into the host image
docs/ROADMAP.md                       staged project plan
.github/workflows/build-desktop.yml   GHCR publisher
scripts/                              image-builder and QEMU helpers
```

## Build and verify

Build the desktop image locally:

```bash
podman build -f desktop/Containerfile -t ghcr.io/eelcoh/bootsybox-desktop:44 .
```

Build the host image and VM using the same rootful Podman storage:

```bash
sudo podman build -f Containerfile -t bootsybox-host:dev .
cd scripts
./createvm.sh
./startvm.sh
```

The image-builder test account is `testuser` / `testpass`; SSH is forwarded to
port 2222. A fresh console login should pull the desktop image and reach niri
without SSH or package installation. The GHCR package must be public for an
unauthenticated new user to pull it.

Static checks:

```bash
bash -n files/usr/local/bin/launch-user-container.sh \
  desktop/files/usr/local/bin/bootsybox-container-init \
  desktop/files/usr/local/bin/bootsybox-session
shellcheck files/usr/local/bin/launch-user-container.sh \
  desktop/files/usr/local/bin/bootsybox-container-init \
  desktop/files/usr/local/bin/bootsybox-session
python3 -c "import tomllib; tomllib.load(open('files/etc/greetd/config.toml','rb'))"
```

Useful VM diagnostics:

```bash
journalctl -b -u seatd -u greetd
loginctl list-sessions
podman logs desktop-env-testuser
cat ~/.local/state/bootsybox/session.log
```

The QEMU launcher uses `virtio-vga-gl`; plain virtio VGA exposes only software
EGL in this VM and niri refuses it. Do not reintroduce direct VT/input mounts,
`--privileged`, host PID/IPC namespaces or `chvt` capabilities. Diagnose the
seatd/socket boundary instead.
