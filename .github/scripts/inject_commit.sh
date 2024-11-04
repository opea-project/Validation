#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
WORKPATH=$PWD
blocks=()
while IFS= read -r line; do
    if [[ $line =~ build ]]; then
        block="$line"
        while IFS= read -r next_line; do
            if [[ $next_line =~ ^\ {6,} ]]; then
            block="$block"$'\n'"$next_line"
            else
            blocks+=("$block")
            block=""
            break
            fi
        done
    fi
done < docker-compose.yaml
for build_block in "${blocks[@]}"; do
    config_path=$(echo "$build_block" | awk '/context:/ { context = $2 } /dockerfile:/ { dockerfile = $2; combined = context "/" dockerfile; gsub(/\/+/, "/", combined); print combined }')
    sed -i -e '/^[^#]*FROM /a\'"\nARG COMMIT_SHA\nARG COMMIT_MESSAGE\nLABEL commit.sha=\$COMMIT_SHA\nLABEL commit.message=\$COMMIT_MESSAGE" $WORKPATH/$config_path

    commit_path=$(echo "$build_block" | awk '$1 == "context:" {print$2}')
    cd $WORKPATH/$commit_path
    COMMIT_SHA=$(git rev-parse --short HEAD)
    COMMIT_MESSAGE=$(git log -1 --pretty=%B)
    new_content=$(printf "        COMMIT_SHA: %s\n        COMMIT_MESSAGE: |\n%s" "$COMMIT_SHA" "$(echo "$COMMIT_MESSAGE" | sed 's/^/          /')")
    echo "$build_block"
    if [[ "$build_block" == *"args:"* ]]; then
        mapfile -t lines <<< "$build_block"
        args_line_index=0
        for i in "${!lines[@]}"; do
            if [[ "${lines[$i]}" == *"args:"* ]]; then
            args_line_index=$((i+1))
            break
            fi
        done
        first_part=("${lines[@]:0:args_line_index}")
        second_part=("${lines[@]:args_line_index}")
        insert_build=$(printf "%s\n" "${first_part[@]}" "$new_content" "${second_part[@]}")
    else
        mapfile -t lines <<< "$build_block"
        args_line_index=0
        for i in "${!lines[@]}"; do
            if [[ "${lines[$i]}" == *"dockerfile:"* ]]; then
            args_line_index=$((i+1))
            break
            fi
        done
        first_part=("${lines[@]:0:args_line_index}")
        second_part=("${lines[@]:args_line_index}")
        insert_build=$(printf "%s\n" "${first_part[@]}" "      args:" "$new_content" "${second_part[@]}")
    fi

    escaped_build_block=$(printf '%s\n' "$build_block" | sed 's/[\/&]/\\&/g; $!s/$/\\/')
    escaped_insert_build=$(printf '%s\n' "$insert_build" | sed 's/[\/&]/\\&/g; $!s/$/\\/')
    sed -i ":a;N;\$!ba;s/$escaped_build_block/$escaped_insert_build/" $WORKPATH/docker-compose.yaml
done
