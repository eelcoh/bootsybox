FROM quay.io/fedora/fedora-bootc:44

RUN dnf -y install \
        greetd \
        podman \
        shadow-utils \
    && dnf clean all

RUN mkdir -p /etc/skel/.config

COPY files/usr/local/bin/launch-user-container.sh /usr/local/bin/launch-user-container.sh
COPY files/etc/greetd/config.toml /etc/greetd/config.toml
COPY files/etc/systemd/system/bootsybox-containers.slice /etc/systemd/system/bootsybox-containers.slice
COPY files/etc/skel/.config/startup.sh /etc/skel/.config/startup.sh

RUN chmod +x /usr/local/bin/launch-user-container.sh /etc/skel/.config/startup.sh

RUN systemctl enable greetd
