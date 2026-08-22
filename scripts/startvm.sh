#!/bin/sh
qemu-system-x86_64 \
    -enable-kvm -m 4096 -smp 2 \
    -drive file=output/qcow2/disk.qcow2,format=qcow2,if=virtio \
    -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
    -display gtk,gl=on \
    -device virtio-vga-gl
