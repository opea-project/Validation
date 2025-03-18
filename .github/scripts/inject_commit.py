#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
import os
import re
import subprocess

WORKPATH = os.getcwd()
blocks = []

# Read the docker-compose.yaml file and extract build blocks
with open('docker-compose.yaml', 'r') as file:
    lines = file.readlines()

block = ""
i = 0
while i < len(lines):
    line = lines[i].rstrip()  # Remove trailing newline characters
    if re.match(r'^\s*build:', line):
        block = line
        i += 1
        while i < len(lines):
            next_line = lines[i].rstrip()  # Remove trailing newline characters
            if re.match(r'^\s{6,}', next_line):
                block += "\n" + next_line
                i += 1
            else:
                blocks.append(block)
                block = ""
                break
    else:
        i += 1

# Read the entire content of docker-compose.yaml
with open('docker-compose.yaml', 'r') as file:
    docker_compose_content = file.read()


for build_block in blocks:
    # Extract context and dockerfile paths
    # context = re.search(r'context:\s*(\S+)', build_block).group(1)
    context_match = re.search(r'context:\s*(\S+)', build_block)
    if context_match:
        context = context_match.group(1)  # 如果匹配成功，提取 context
    else:
        context = './'
    dockerfile = re.search(r'dockerfile:\s*(\S+)', build_block).group(1)
    config_path = os.path.join(context, dockerfile).replace('//', '/')

    # Insert ARG and LABEL into Dockerfile
    dockerfile_path = os.path.join(WORKPATH, config_path)
    with open(dockerfile_path, 'r') as file:
        dockerfile_content = file.read()
    # new_dockerfile_content = re.sub(r'(^[^#]*FROM .*$)', r'\1\nARG COMMIT_SHA\nARG COMMIT_MESSAGE\nLABEL commit.sha=$COMMIT_SHA\nLABEL commit.message=$COMMIT_MESSAGE', dockerfile_content, flags=re.MULTILINE)
    new_dockerfile_content = re.sub(r'(^[^#]*FROM .*$)', r'\1\nARG COMMIT_SHA\nLABEL commit.sha=$COMMIT_SHA\n', dockerfile_content, flags=re.MULTILINE)

    with open(dockerfile_path, 'w') as file:
        file.write(new_dockerfile_content)

    # Get commit SHA and message
    # commit_path = re.search(r'context:\s*(\S+)', build_block).group(1)
    os.chdir(os.path.join(WORKPATH, context))
    COMMIT_SHA = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD']).strip().decode('utf-8')
    # COMMIT_MESSAGE = subprocess.check_output(['git', 'log', '-1', '--pretty=%B']).strip().decode('utf-8')
    new_content = f"        COMMIT_SHA: {COMMIT_SHA}"

    # Update build block with new args
    if "args:" in build_block:
        lines = build_block.split('\n')
        args_line_index = 0
        for i, line in enumerate(lines):
            if "args:" in line:
                args_line_index = i + 1
                break
        first_part = lines[:args_line_index]
        second_part = lines[args_line_index:]
        insert_build = "\n".join(first_part + [new_content] + second_part)
    else:
        lines = build_block.split('\n')
        args_line_index = 0
        for i, line in enumerate(lines):
            if "build:" in line:
                args_line_index = i + 1
                break
        first_part = lines[:args_line_index]
        second_part = lines[args_line_index:]
        insert_build = "\n".join(first_part + ["      args:", new_content] + second_part)
    pattern = re.compile(re.escape(build_block), re.MULTILINE)
    docker_compose_content = pattern.sub(insert_build, docker_compose_content, count=1)

with open(os.path.join(WORKPATH, 'docker-compose.yaml'), 'w') as file:
    file.write(docker_compose_content)
