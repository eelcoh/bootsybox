# Bootsybox roadmap

## Completed foundation

- Fedora bootc host boots as a qcow2 image.
- greetd authenticates a regular user.
- Host seatd brokers VT, DRM and input access.
- Niri runs inside a rootless per-user Podman container with accelerated
  virtio graphics.

## User stories

### Discover and stage a host update

As the system owner, I can inspect the running and available Bootsybox host
versions, download an update without disrupting my graphical session, and see
that the new deployment is staged before I choose to reboot.

Acceptance:

- `bootc status` identifies the customized Bootsybox image and booted digest.
- `sudo bootc upgrade --check` reports whether a newer host image is available.
- `sudo bootc upgrade` downloads and queues the update without changing the
  running deployment.
- The user receives an understandable success, failure and reboot-required
  indication; an update failure never strands them outside the current desktop.

### Apply a host update deliberately

As the system owner, I can save my work and reboot into a staged update at a
time I choose, rather than the distribution rebooting unexpectedly.

Acceptance:

- `sudo bootc upgrade --apply` is the supported explicit update-and-reboot path.
- Automatic update policy is documented; the upstream apply timer remains
  disabled until Bootsybox has user-facing notification and reboot coordination.
- After reboot, greetd, seatd and the compatible desktop environment start
  without manual repair.
- Home data, user Flatpaks, keyrings and nested-container data are unchanged.

### Recover from a bad host update

As the system owner, I can return to the previous bootable deployment if a host
update breaks boot or graphical login, without losing user state.

Acceptance:

- The previous deployment remains selectable from the bootloader.
- From a working deployment, `sudo bootc rollback --apply` reboots into the
  rollback deployment and discards any unapplied staged update.
- Rollback behavior for image-owned `/etc` configuration is tested and
  documented; persistent user state under `/var/home` is preserved.
- The desktop image compatibility check fails visibly and recoverably rather
  than creating a login loop.

### Stay on the customized distribution

As a Bootsybox user, normal upgrades retain the project-specific host services,
configuration and desktop compatibility contract. I do not need `bootc switch`
for routine updates.

Acceptance:

- CI publishes a pullable customized host image with moving, immutable and
  commit-derived tags.
- Installation artifacts are built from that registry reference rather than
  `localhost/bootsybox-host:dev`, so the installed origin is upgradeable.
- `bootc switch` is documented as an expert recovery or channel migration tool,
  not the normal upgrade path.

### Discover and stage a desktop-environment update

As a Bootsybox user, I can inspect, check and download an updated reproducible
desktop environment without interrupting my current graphical session, just as
I can stage a bootc host update without changing the running deployment.

Acceptance:

- A supported Bootsybox command reports the running, available, staged and
  last-known-good desktop image versions and immutable digests.
- Checking an update fetches metadata without replacing the running container.
- Staging downloads and validates the candidate image but leaves the current
  graphical session untouched.
- The current prototype behavior of automatically pulling and applying the
  moving desktop tag during every login is replaced by this explicit lifecycle.
- Update failures are visible and leave the current environment available.

The intended command shape should mirror bootc where practical:

```text
bootsybox desktop status
bootsybox desktop upgrade --check
bootsybox desktop upgrade
```

### Apply or roll back a desktop-environment update

As a Bootsybox user, I can activate a staged desktop environment at a controlled
session boundary and return to the last-known-good environment if it fails.

Acceptance:

- A normal staged update becomes active on the next logout/login without a host
  reboot.
- An explicit `bootsybox desktop upgrade --apply` warns that it will end the
  graphical session before activating the candidate.
- `bootsybox desktop rollback --apply` selects the last-known-good image and
  restarts the session with the same persistent home and declared volumes.
- Failure before Wayland readiness automatically marks the candidate bad and
  selects the last-known-good image on the next attempt.
- Applying or rolling back the environment never mutates or rolls back user
  documents, configuration, Flatpaks, keyrings or nested-container data.

### Coordinate host and desktop compatibility

As a Bootsybox user, I can update the host and desktop environment independently
without accidentally selecting an incompatible pair.

Acceptance:

- Published releases declare host API, desktop API and compatibility metadata.
- Status output explains when one staged component requires the other component
  to be updated first or alongside it.
- Applying an incompatible host or desktop candidate is refused before logout
  or reboot, while current known-good deployments remain usable.
- CI tests supported host/desktop update and rollback combinations by immutable
  digest.

## Phase 1: reproducible desktop image

Implementation and VM acceptance status: complete. A fresh user can pull the
published image and reach niri without manual package installation.

- Build a dedicated Fedora desktop OCI image containing niri and the supported
  session components.
- Publish the image to GHCR with a stable Fedora-version tag.
- Prototype: pull it automatically during login. Phase 4 replaces this with
  explicit background staging and activation at a session boundary.
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

Implementation status: the persistence contract and a login-time replacement/
fallback prototype are implemented. The deliberate transactional desktop update
interface is Phase 4 work; destructive replacement, migration and rollback
still require VM acceptance testing.

- Treat the outer container filesystem as disposable and never install packages
  into it interactively.
- Persist home data, user Flatpaks, configuration and keyrings through the home
  bind mount; use explicit volumes for any future non-home state.
- Stage and validate replacement containers before removing the current one.
- Track last-known-good and failed image IDs for automatic fallback.
- Test recreation, migration and rollback between desktop image versions.

## Phase 4: transactional host and desktop lifecycle

This is the next priority because the current qcow2 is installed from a local
development image reference and therefore has no usable production update
origin.

Implementation status: the host publication workflow, remote-origin VM build,
narrow update broker/client, explicit desktop staging, session-boundary
activation and last-known-good rollback are implemented in the repository.
Publication and the full VM update/rollback matrix remain to be accepted.

- Add CI for the customized Bootsybox host image.
- Publish Fedora-channel, dated commit-specific and full-SHA tags.
- Build qcow2 artifacts from the published host reference.
- Verify `bootc status`, update checking, staging and explicit application as a
  wheel user.
- Verify bootloader recovery and `bootc rollback --apply`.
- Build the `bootsybox desktop` status, check, stage, apply and rollback command
  surface.
- Move desktop image pulling out of the login-critical path; login should only
  activate an already validated staged image or the current known-good image.
- Test host/desktop API compatibility across update and rollback combinations.
- Add user-visible update state and reboot-required reporting before considering
  automatic application.

Acceptance: an installed VM independently stages and applies published host and
desktop updates, preserves contracted state, refuses incompatible combinations,
and can return both layers to their previous known-good deployments.

## Phase 5: nested containers

- Verify rootless Distrobox/Podman nesting, storage, networking and logout.
- Decide whether nested or host-managed sibling containers are the supported
  model.

## Phase 6: hardening

- Document that the rootless-privileged outer environment is not a security
  boundary and cannot exceed the authenticated user's host privileges.
- Keep meaningful application isolation in Flatpak/Bubblewrap and development
  isolation in nested containers.
- Minimize explicit host sockets and persistent mounts.
- Apply effective per-user CPU, memory, process and file-descriptor limits.
- Audit mounts and capabilities and document the isolation boundary.

## Phase 7: host integrations

- Add narrow interfaces for NetworkManager, Bluetooth, power, PipeWire, camera,
  screen sharing and removable storage.
- Do not expose an unrestricted host system bus.

## Phase 8: release qualification

- Test host and desktop images together in CI.
- Publish signed versioned images and qcow2 artifacts.
- Test coordinated upgrades and rollback.

## Phase 9: installation and provisioning

- Add production image-builder/Kickstart configuration.
- Automate user provisioning and recovery access.
- Test installation, updates and offline failure behavior.

## Phase 10: user experience

- Add a graphical greeter, curated defaults and first-login feedback.
- Add Material You/matugen theming after the underlying session is stable.
