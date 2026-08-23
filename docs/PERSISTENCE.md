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

## Updates and rollback

The host pulls the declared moving tag, checks the desktop API label, then stages
and validates a candidate container before replacing the current container. A
session that reaches a Wayland-ready state records its immutable image ID as the
last known good version. If a new image exits before readiness, subsequent
logins use the cached last-known-good image until the moving tag points to a new
image ID.

CI publishes the Fedora channel tag, a dated commit-specific tag and a full
commit-derived tag. Image IDs remain cached locally for rollback; pruning them
also removes that rollback option.

## Trust model

The outer container runs rootless but privileged. Rootless mode prevents it from
exceeding the authenticated user's host privileges; privileged mode deliberately
turns off most isolation between that user and their outer environment. This is
required for nested Bubblewrap mounts. Flatpak remains the supported application
sandbox, while nested development containers provide isolation for development
workloads.
