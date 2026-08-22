FROM quay.io/fedora/fedora-bootc:44

RUN dnf -y install \
        greetd \
        podman \
        seatd \
        shadow-utils \
        audit \
    && dnf clean all

# Without a running auditd to consume records via netlink, the kernel falls
# back to printk-ing audit events straight to the console, burying the
# login prompt and any debug output under SELinux/PAM noise.
RUN systemctl enable auditd

RUN mkdir -p /etc/skel/.config

# seatd owns the physical seat on the host and passes already-open DRM/input
# file descriptors to compositors over /run/seatd.sock. Desktop users only
# need permission to connect to that socket.
RUN groupadd -r bootsybox-seat

COPY files/usr/local/bin/launch-user-container.sh /usr/local/bin/launch-user-container.sh
COPY files/etc/greetd/config.toml /etc/greetd/config.toml
COPY files/etc/systemd/system/seatd.service.d/10-bootsybox.conf /etc/systemd/system/seatd.service.d/10-bootsybox.conf
COPY files/etc/systemd/system/greetd.service.d/10-seatd.conf /etc/systemd/system/greetd.service.d/10-seatd.conf
COPY files/etc/systemd/system/bootsybox-containers.slice /etc/systemd/system/bootsybox-containers.slice
COPY files/etc/skel/.config/startup.sh /etc/skel/.config/startup.sh

RUN chmod +x /usr/local/bin/launch-user-container.sh /etc/skel/.config/startup.sh

RUN systemctl enable seatd greetd
