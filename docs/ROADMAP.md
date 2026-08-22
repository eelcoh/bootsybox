# Bootsybox roadmap

## Completed foundation

- Fedora bootc host boots as a qcow2 image.
- greetd authenticates a regular user.
- Host seatd brokers VT, DRM and input access.
- Niri runs inside a rootless per-user Podman container with accelerated
  virtio graphics.

## Phase 1: reproducible desktop image

Implementation status: complete in the repository. Acceptance is pending the
first GHCR publication and a fresh-VM login test.

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

Implementation status: complete in the repository. Local image/config checks
pass; portal, Flatpak and logout behavior still require the fresh-VM acceptance
run after publication.

- Provide a terminal, launcher, Waybar and notifications.
- Start a private D-Bus session and export the compositor-created display to
  D-Bus activation.
- Provide GTK/GNOME portal backends and `/dev/fuse` for Flatpak document access.
- Return cleanly to greetd when niri exits.
- Verify first login, logout, second login, reboot and a GUI Flatpak.

Acceptance: terminal, launcher, portal-backed file chooser, Flatpak, logout and
repeat login work without fatal journal errors.

## Phase 3: persistence contract

- Specify which home data, Flatpaks, configuration, keyrings and volumes survive
  outer-container replacement.
- Test recreation and migration between desktop image versions.

## Phase 4: nested containers

- Verify rootless Distrobox/Podman nesting, storage, networking and logout.
- Decide whether nested or host-managed sibling containers are the supported
  model.

## Phase 5: hardening

- Replace `label=disable` with a targeted SELinux policy.
- Minimize DRM and seatd exposure.
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
