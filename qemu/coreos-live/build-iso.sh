#!/bin/bash

KERNEL_ARG='--live-karg-append=coreos.liveiso.fromram'
IGNITION_ARG='--live-ignition=./config.ign'
podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data     quay.io/coreos/coreos-installer:release iso customize --live-karg-append=coreos.liveiso.fromram --live-ignition=./config.ign     -o ignited.iso fedora-coreos-42.20250914.3.0-live-iso.x86_64.iso
