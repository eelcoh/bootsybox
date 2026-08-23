# Bootsybox roadmap

## Completed foundation

- Fedora bootc host boots as a qcow2 image.
- greetd authenticates a regular user.
- Host seatd brokers VT, DRM and input access.
- Niri runs inside a rootless per-user Podman container with accelerated
  virtio graphics.

## Phase 1: reproducible desktop image

Implementation and VM acceptance status: complete. A fresh user can pull the
published image and reach niri without manual package installation.

- Build a dedicated Fedora desktop OCI image containing niri and the supported
  session components.
- Publish the image to GHCR with a stable Fedora-version tag.
- Pull it automatically during login.
- Replace an existing outer container when its image ID changes, preserving the
  bind-mounted home directory.
- Remove all first-login package installation from the host launcher.

Acceptance: a new user reaches niri on first login without SSH or manual package
installation.

## Phase 2: complete graphical session

Implementation status: all VM acceptance checks passed except nested Flatpak.
The outer container is now explicitly a disposable rootless-privileged
environment so Bubblewrap can provide the application sandbox. Flatpak launch
and application discovery require one final VM retest.

- Provide a terminal, launcher, Waybar and notifications.
- Start a private D-Bus session and export the compositor-created display to
  D-Bus activation.
- Provide GTK/GNOME portal backends and `/dev/fuse` for Flatpak document access.
- Return cleanly to greetd when niri exits.
- Verify first login, logout, second login, reboot and a GUI Flatpak.

Acceptance: terminal, launcher, portal-backed file chooser, Flatpak, logout and
repeat login work without fatal journal errors.

## Phase 3: persistence contract

Implementation status: contract and upgrade mechanics are implemented; destructive
replacement, migration and rollback still require VM acceptance testing.

- Treat the outer container filesystem as disposable and never install packages
  into it interactively.
- Persist home data, user Flatpaks, configuration and keyrings through the home
  bind mount; use explicit volumes for any future non-home state.
- Stage and validate replacement containers before removing the current one.
- Track last-known-good and failed image IDs for automatic fallback.
- Test recreation, migration and rollback between desktop image versions.

## Phase 4: nested containers

- Verify rootless Distrobox/Podman nesting, storage, networking and logout.
- Decide whether nested or host-managed sibling containers are the supported
  model.

## Phase 5: hardening

- Document that the rootless-privileged outer environment is not a security
  boundary and cannot exceed the authenticated user's host privileges.
- Keep meaningful application isolation in Flatpak/Bubblewrap and development
  isolation in nested containers.
- Minimize explicit host sockets and persistent mounts.
- Apply effective per-user CPU, memory, process and file-descriptor limits.
- Audit mounts and capabilities and document the isolation boundary.

## Phase 6: host integrations

- Add narrow interfaces for NetworkManager, Bluetooth, power, PipeWire, camera,
  screen sharing and removable storage.
- Do not expose an unrestricted host system bus.

## Phase 7: release automation

- Build and test host and desktop images in CI.
- Publish versioned images and qcow2 artifacts.
- Test coordinated upgrades and rollback.

## Phase 8: installation and provisioning

- Add production image-builder/Kickstart configuration.
- Automate user provisioning and recovery access.
- Test installation, updates and offline failure behavior.

## Phase 9: user experience

- Add a graphical greeter, curated defaults and first-login feedback.
- Add Material You/matugen theming after the underlying session is stable.
