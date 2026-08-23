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
- `launch-user-container.sh` bootstraps the declared desktop image once, then
  activates explicitly staged immutable image IDs while preserving the
  bind-mounted home. Failed images fall back to the cached last-known-good image.
- `bootsybox-update.socket` is a narrow root-owned update broker, accessible to
  `wheel`. The desktop's `bootsybox` client uses it for bootc and user-scoped
  desktop lifecycle operations without exposing the host system bus.
- The container receives the seatd socket, read-only udev/DRM discovery data,
  the user's home and machine ID. It does not receive host VTs, the host runtime
  directory or the host system bus.

### Desktop image

- `ghcr.io/eelcoh/bootsybox-desktop:44`, built by `desktop/Containerfile`.
- Contains niri, Waybar, Alacritty, Fuzzel, Mako, Xwayland Satellite, Flatpak,
  Distrobox, Mesa, D-Bus, GNOME/GTK portals and GNOME Keyring.
- Its init entrypoint creates a user matching the authenticated host UID/GID.
- `bootsybox-session` starts a private D-Bus session, launches niri through host
  seatd, exports the Wayland environment to D-Bus activation, and starts
  notifications, secrets and portals.
- The outer container is disposable and session-scoped. Logout stops it and
  returns control to greetd; image changes replace it on the next login.

`--userns=keep-id` and `--group-add keep-groups` preserve the user identity and
seat group. The outer environment runs rootless-privileged so nested Flatpak
Bubblewrap can mount its sandbox. It cannot exceed the authenticated user's host
privileges, but Podman isolation is deliberately not a security boundary. See
`docs/PERSISTENCE.md` for the persistence, update and trust contracts.

## Repository layout

```text
Containerfile                         host image
desktop/Containerfile                 reproducible desktop image
desktop/files/usr/local/bin/          container init and session launchers
files/                                files copied into the host image
docs/ROADMAP.md                       staged project plan
docs/PERSISTENCE.md                   state, upgrade and trust contract
.github/workflows/build-desktop.yml   GHCR publisher
.github/workflows/build-host.yml      customized bootc host publisher
scripts/                              image-builder and QEMU helpers
```

## Build and verify

Build the desktop image locally:

```bash
podman build -f desktop/Containerfile -t ghcr.io/eelcoh/bootsybox-desktop:44 .
```

Build the host image locally, or build a VM from the published upgradeable
origin:

```bash
sudo podman build -f Containerfile -t bootsybox-host:dev .
cd scripts
./createvm.sh
./startvm.sh
```

Override the VM source for local development with
`BOOTSYBOX_HOST_IMAGE=localhost/bootsybox-host:dev ./createvm.sh`.

Lifecycle commands available inside the desktop include:

```bash
bootsybox host status
bootsybox host upgrade --check
bootsybox host upgrade
bootsybox host upgrade --apply
bootsybox host rollback --apply

bootsybox desktop status
bootsybox desktop upgrade --check
bootsybox desktop upgrade
bootsybox desktop upgrade --apply
bootsybox desktop rollback --apply
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
EGL in this VM and niri refuses it. Do not add direct VT/input mounts, host
PID/IPC namespaces or `chvt` capabilities. Rootless privileged mode exists only
to support nested Bubblewrap and does not replace seatd ownership of the seat.
