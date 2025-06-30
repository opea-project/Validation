#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe

SCRIPT_DIR="/home/sdp/workspace"

python $SCRIPT_DIR/clean_registry.py

# to read_only mode
docker kill registry
docker rm registry
docker run -d -p 5000:5000 --restart=always --name registry -v $SCRIPT_DIR/read_only.yaml:/etc/docker/registry/config.yml -v /data/local_image_registry:/var/lib/registry registry:2

sleep 20

# run garbage-collect to clean up disk
docker exec registry bin/registry garbage-collect /etc/docker/registry/config.yml

# restart registry
docker kill registry
docker rm registry
docker run -d -p 5000:5000 --restart=always --name registry -v $SCRIPT_DIR/registry.yaml:/etc/docker/registry/config.yml -v /data/local_image_registry:/var/lib/registry registry:2
