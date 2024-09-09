#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe

SCRIPT_DIR="/home/sdp/workspace"

# clean up tag images
output=$("$SCRIPT_DIR/registry.sh" images)
lines=$(echo "$output" | grep -v latest | grep -v "v0.9")
#lines=$(echo "$output" | grep "v0.9")
for line in $lines; do
    image=$(echo "$line" | cut -d':' -f1)
    tag=$(echo "$line" | cut -d':' -f2)
    $SCRIPT_DIR/registry.sh delete $image $tag
done

sleep 20

# run garbage-collect to clean up disk
docker exec registry bin/registry garbage-collect /etc/docker/registry/config.yml

# restart registry
docker kill registry
docker rm registry
docker run -d -p 5000:5000 --restart=always --name registry -v /home/sdp/workspace/registry.yaml:/etc/docker/registry/config.yml -v /data/local_image_registry:/var/lib/registry registry:2
