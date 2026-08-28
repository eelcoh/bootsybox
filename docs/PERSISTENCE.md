# Desktop environment contract

The outer Bootsybox desktop container is a disposable, reproducible realization
of the declared desktop OCI image. It is not a security boundary and must never
be the only location of user data.

## Persistent state

The host binds `/var/home/$USER` to `/home/$USER`. Consequently these survive an
image update, rollback or complete outer-container replacement:

- documents and other user files;
- configuration under `$HOME/.config`;
- application data and state under `$HOME/.local`;
- user Flatpak installations and their application data;
- keyrings stored in the home directory;
- nested-container storage located in the home directory.

Future state outside the home directory must use an explicitly declared named
volume and be added to this contract before it is relied upon.

## Disposable state

The outer container's writable layer, including changes beneath `/etc`, `/usr`
and `/var`, can disappear at any login. Installing RPMs or editing system files
interactively is unsupported. Such changes belong in `desktop/Containerfile` so
they are reproducible and upgradeable.

## Desktop updates and rollback

The first login bootstraps the declared moving tag. After that, `bootsybox
desktop upgrade` pulls the tag, checks the desktop API label and records its
immutable image ID as staged without disturbing the running session. Login only
activates a staged digest or starts the current environment; it does not contact
the registry on every session.

A session that reaches a Wayland-ready state immediately records its immutable
image ID as the last known good version and retains the preceding known-good ID
in a separate rollback slot. If a staged image exits before readiness, the next
login removes that stage and returns to the cached last-known-good image.
`bootsybox desktop rollback --apply` activates the rollback slot and preserves
the current good image so rollback can be toggled deliberately.

CI publishes the Fedora channel tag, a dated commit-specific tag and a full
commit-derived tag. Image IDs remain cached locally for rollback; pruning them
also removes that rollback option.

The image-owned declaration is `/usr/share/bootsybox/desktop-image`. An
administrator may select a different channel by placing one OCI reference in
`/etc/bootsybox/desktop-image`; removing that file returns to the image-owned
default. This override is also used for compatibility acceptance tests. It does
not bypass API checks: an incompatible image may be downloaded into the user's
cache, but it is rejected before being staged or activated.

Host updates remain bootc deployments. The root-owned update broker exposes a
small command allowlist over `/run/bootsybox-update.sock`; it does not expose the
host system bus. Socket access is restricted to `wheel`, and request parameters
are validated before dispatching bootc or user-scoped rootless Podman commands.
The broker announces its protocol and terminates every response with an explicit
result status, allowing the unprivileged client to propagate failures instead
of treating a disconnected service as success. New clients remain compatible
with the earlier text-only broker during independent host/desktop upgrades.

Before a host update is checked, staged or applied, the broker compares the
candidate host API and supported desktop API labels with the selected desktop
image's API and required host API labels. Desktop staging performs the same
four-label check in the opposite direction. Missing or mismatched metadata
rejects the candidate before logout or reboot.

## Trust model

The outer container runs rootless but privileged. Rootless mode prevents it from
exceeding the authenticated user's host privileges; privileged mode deliberately
turns off most isolation between that user and their outer environment. This is
required for nested Bubblewrap mounts. Flatpak remains the supported application
sandbox, while nested development containers provide isolation for development
workloads.
