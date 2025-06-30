# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

FROM ghcr.io/actions/actions-runner:latest
ENV LANG C.UTF-8
SHELL ["/bin/bash", "-c"]

RUN sudo -E apt-get update && sudo apt-get install -y \
    build-essential numactl tree gpg-agent wget curl \
    htop unzip net-tools git-lfs ca-certificates docker.io file
RUN wget --tries=5 --no-verbose https://github.com/docker/compose/releases/download/v2.33.1/docker-compose-linux-x86_64
RUN sudo mkdir -p /usr/local/lib/docker/cli-plugins \
    && sudo mv docker-compose-linux-x86_64 /usr/local/lib/docker/cli-plugins/docker-compose \
    && sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
RUN sudo usermod -a -G docker runner

USER runner

RUN wget --tries=5 --no-verbose "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
RUN bash Miniforge3-$(uname)-$(uname -m).sh -p "${HOME}/miniforge3" -b && rm -rf Miniforge3-$(uname)-$(uname -m).sh
RUN source "${HOME}/miniforge3/etc/profile.d/conda.sh" && conda init
SHELL ["/bin/bash", "-i", "-c"]
RUN conda activate

RUN conda install -c conda-forge nodejs -y
RUN pip install "huggingface_hub[cli]
