# CLAUDE.md

## Project

Bootsybox is an experimental Fedora bootc desktop host. The immutable host owns
boot, authentication and hardware arbitration; every regular user's compositor,
applications and mutable package state live in that user's rootless Podman
container.

The original design conversation is saved as `conversation-with-ai`. It contains
useful product intent but many of its command examples were speculative. This
file and the implementation are authoritative.

## Goals and current interpretation

- **Immutable host:** build and update the host as an OCI/bootc image.
- **Per-user environment:** keep mutable desktop software out of the host image.
- **Least privilege:** the host owns VTs, DRM and input through seatd. A desktop
  container connects to seatd's Unix socket and must not receive host VTs or raw
  input devices.
- **Reproducibility:** eventually replace first-login package installation with
  versioned desktop images or a user-owned declarative image recipe. A
  `distrobox.ini` only describes nested development containers and is not enough
  to reproduce the outer desktop container.

"Isolated" currently means separate Unix users, rootless user namespaces,
container filesystems and normal PID/IPC/network namespaces. It does not claim
VM-grade protection against hostile users. SELinux label separation is disabled
for the desktop container while it bind-mounts an existing home and the shared
seatd socket; this is a known hardening gap.

## Architecture

### Host

- `quay.io/fedora/fedora-bootc:44`
- greetd/agreety authenticates on VT1.
- A root-owned seatd service creates `/run/seatd.sock`, owned by group
  `bootsybox-seat`.
- `launch-user-container.sh` runs as the authenticated user and creates or starts
  that user's rootless container.
- The host does not run the user's compositor or applications.

The Fedora greetd package already ships `/etc/pam.d/greetd` with a session stack
that includes `pam_systemd` through `system-auth`. Do not replace it without a
specific, VM-observed failure. The previous VM appeared to lack a logind session
for the authenticated user; re-check that observation on the rebuilt image.

### Desktop container

- `quay.io/fedora/fedora-toolbox:44`
- `--userns=keep-id` maps the desktop user to their host UID.
- `--group-add keep-groups` preserves membership of `bootsybox-seat`, allowing a
  connection to the seatd socket.
- `/var/home/$USER` is mounted at `/home/$USER`.
- `/run/seatd.sock`, read-only udev metadata and a read-only view of `/dev/dri`
  are bind-mounted into the container. The DRM paths are needed for compositor
  discovery; seatd still performs the privileged opens and passes the resulting
  file descriptors. The container does not mount `/dev/tty*`, `/dev/input`, the
  host runtime directory or system D-Bus.
- `/dev/fuse` is passed explicitly for Flatpak's document portal and future
  nested-container storage; no other raw device is passed with `--device`.
- `startup.sh` forces libseat's seatd backend and launches niri or sway through a
  fresh D-Bus session.

The outer container is persistent but runs only for the graphical login. It is
stopped when the compositor exits, which also makes the next start bind seatd's
current socket inode if the broker was restarted. It bootstraps Flatpak,
Distrobox, Mesa and D-Bus with `dnf` when first created. This is acceptable for
the current prototype but is not the final update/reproducibility model.

## Current milestone

The original login-to-container path has been VM-tested. The former attempt to
let a rootless container claim `/dev/tty2` reached `TIOCSCTTY`/VT permission
failures and accumulated unsafe workarounds (`--privileged`, host namespaces,
static VT permissions and a file-capable `chvt`). That design has been removed.

The current milestone is implemented but still needs VM verification:

1. host seatd starts before greetd;
2. testuser authenticates through agreety;
3. the rootless desktop container connects to host seatd;
4. niri, installed in the user's container, acquires the seat and holds the
   graphical display;
5. logging out returns to greetd without leaving the seat wedged.

Theming, NetworkManager/Bluetooth APIs, nested-container verification, automatic
container rebuilds, installer media and CI are deliberately out of scope until
this milestone passes.

## Repository layout

```text
Containerfile
files/
  etc/greetd/config.toml
  etc/skel/.config/startup.sh
  etc/systemd/system/bootsybox-containers.slice
  etc/systemd/system/greetd.service.d/10-seatd.conf
  etc/systemd/system/seatd.service.d/10-bootsybox.conf
  usr/local/bin/launch-user-container.sh
scripts/
  config.toml
  createvm.sh
  refresh.sh
  startvm.sh
```

`files/` mirrors destination paths in the host image. Add a matching `COPY` to
the `Containerfile` for every new host file.

## Build and verify

Static checks:

```bash
bash -n files/usr/local/bin/launch-user-container.sh \
  files/etc/skel/.config/startup.sh
shellcheck files/usr/local/bin/launch-user-container.sh \
  files/etc/skel/.config/startup.sh
systemd-analyze verify \
  /usr/lib/systemd/system/seatd.service \
  files/etc/systemd/system/bootsybox-containers.slice
python3 -c "import tomllib; tomllib.load(open('files/etc/greetd/config.toml','rb'))"
```

Build the host image:

```bash
sudo podman build -f Containerfile -t bootsybox-host:dev .
```

Build a btrfs qcow2 using the same rootful Podman storage:

```bash
cd scripts
./createvm.sh
./startvm.sh
```

The image-builder test account is `testuser` / `testpass` and belongs to
`wheel` and `bootsybox-seat`. SSH is forwarded to port 2222.

On the first console login the container is created and reports that no WM is
installed. From SSH, install niri in that already-created container:

```bash
ssh -p 2222 testuser@localhost
podman exec -u root desktop-env-testuser dnf install -y niri
```

Then log in again at the graphical console. Collect failures with:

```bash
journalctl -b -u seatd -u greetd
loginctl list-sessions
podman logs desktop-env-testuser
cat ~/.config/startup.log
```

The VM launcher uses `virtio-vga-gl` and GTK OpenGL. Plain `-vga virtio` only
provides software EGL in this VM; niri skips software renderers and fails with
`no allocator available for device`, even though seatd itself is working.

Do not add back direct VT mounts, broad `/dev` mounts, `--privileged`, host PID
or IPC namespaces, or `chvt` capabilities to fix a seatd failure. Diagnose the
host broker/socket boundary instead.
