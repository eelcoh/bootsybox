FROM quay.io/fedora/fedora-bootc:44

RUN dnf -y install \
        greetd \
        podman \
        shadow-utils \
        kbd \
        libcap \
        audit \
    && dnf clean all

# Without a running auditd to consume records via netlink, the kernel falls
# back to printk-ing audit events straight to the console, burying the
# login prompt and any debug output under SELinux/PAM noise.
RUN systemctl enable auditd

# VT_ACTIVATE (switching which VT is displayed) requires CAP_SYS_TTY_CONFIG,
# checked against the VT subsystem globally — it's not namespace-aware, so no
# capability set inside a rootless container (however --privileged) can ever
# satisfy it; only a real host-level process can. launch-user-container.sh
# (unprivileged, runs as the logging-in user) needs to perform this switch
# itself before handing off to the container, so grant chvt that one
# capability via a file capability rather than requiring full root/sudo.
RUN setcap cap_sys_tty_config+ep /usr/bin/chvt

RUN mkdir -p /etc/skel/.config

# greetd doesn't register a logind seat session for the logged-in user (see
# files/etc/udev/rules.d/99-bootsybox-seat.rules for details), so VT/console
# device access is granted via static group membership instead of per-session
# ACLs. Desktop users need to be added to this group (not yet automated —
# see the session-lingering caveat in CLAUDE.md for the same class of gap).
RUN groupadd -r bootsybox-seat

COPY files/usr/local/bin/launch-user-container.sh /usr/local/bin/launch-user-container.sh
COPY files/etc/greetd/config.toml /etc/greetd/config.toml
COPY files/etc/systemd/system/bootsybox-containers.slice /etc/systemd/system/bootsybox-containers.slice
COPY files/etc/skel/.config/startup.sh /etc/skel/.config/startup.sh
COPY files/etc/udev/rules.d/99-bootsybox-seat.rules /etc/udev/rules.d/99-bootsybox-seat.rules

RUN chmod +x /usr/local/bin/launch-user-container.sh /etc/skel/.config/startup.sh

RUN systemctl enable greetd
