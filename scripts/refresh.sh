#!/bin/sh
sudo chown $USER:$USER ./output
sudo chown $USER:$USER ./output/qcow2
sudo chown $USER:$USER ./output/qcow2/disk.qcow2

ssh-keygen -R "[localhost]:2222"

