#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# set -xe
REGISTRY_URL="localhost:5000"

EXPIRED_HOUR=48
#EXPIRED_HOUR=168

# Function to get the manifest
function get_manifest() {
    IMAGE_NAME="$1"
    IMAGE_TAG="$2"
    curl -X GET "${REGISTRY_URL}/v2/${IMAGE_NAME}/manifests/${IMAGE_TAG}"
}

# Function to extract the pushed date from the manifest
function get_pushed_date_time() {
    IMAGE_NAME="$1"
    IMAGE_TAG="$2"
    MANIFEST_JSON=$(get_manifest "$IMAGE_NAME" "$IMAGE_TAG")

    if [ -z "$MANIFEST_JSON" ]; then
        echo "Failed to retrieve manifest. Please check your image name, tag, and registry URL."
        exit 1
    fi

    DATE=$(echo "$MANIFEST_JSON" | jq -r '.history[0].v1Compatibility' | jq -r '.created')
    echo "$DATE"
}

# Function to check if the pushed date is older than 72 hours
function is_older_than_72_hours() {
    PUSHED_DATE_TIME="$1"
    CURRENT_DATE_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    PUSHED_DATE_SECONDS=$(date -d "$PUSHED_DATE_TIME" +%s)
    CURRENT_DATE_SECONDS=$(date -d "$CURRENT_DATE_TIME" +%s)
    SECONDS_DIFF=$((CURRENT_DATE_SECONDS - PUSHED_DATE_SECONDS))
    HOURS_DIFF=$((SECONDS_DIFF / 3600))

    if [ "$HOURS_DIFF" -gt $EXPIRED_HOUR ]; then
        echo "true"
    else
        echo "false"
    fi
}

function list_images() {
    output=$(curl -s -X GET http://${REGISTRY_URL}/v2/_catalog)
    repositories=$(echo "$output" | jq -r '.repositories[]')
    for repo in $repositories; do
        tagoutput=$(curl -s -X GET http://${REGISTRY_URL}/v2/${repo}/tags/list)
        tags=$(echo "$tagoutput" | jq -r '.tags[]?')
        if [ "$tags" != "" ]; then
            for tag in $tags; do
                echo "${repo}:${tag}"
            done
        else
            echo "${repo}:<null>"
        fi
    done

}

function list_names() {
    output=$(curl -s -X GET http://${REGISTRY_URL}/v2/_catalog)
    repositories=$(echo "$output" | jq -r '.repositories[]')
    echo $repositories
}

function list_tags() {
    echo "Listing tags for image $1:"
    image=$1
    output=$(curl -X GET http://${REGISTRY_URL}/v2/${image}/tags/list)
}

function delete_tags() {
    #set -xe
    image=$1
    tag=$2
    # make sure the image is EXPIRED
    PUSHED_DATE_TIME=$(get_pushed_date_time "$image" "$tag")
    echo "$image:$tag pushed date and time: $PUSHED_DATE_TIME"
    if [ "$(is_older_than_72_hours "$PUSHED_DATE_TIME")" == "true" ]; then
        echo "The image was pushed more than $EXPIRED_HOUR hours ago."
    else
        echo "The image was pushed within the last $EXPIRED_HOUR hours."
        exit 0
    fi

    echo "Deleting tag $tag for image $image:"
    diagest=$( curl -s -I -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' http://${REGISTRY_URL}/v2/${image}/manifests/${tag} | grep Docker-Content-Digest | awk '{print $2}' | tr -d '\r')
    echo "$diagest"
    curl -X DELETE http://${REGISTRY_URL}/v2/${image}/manifests/${diagest}
}

function usage_print() {
    echo "Usage: $0 images|tags|delete"
    echo "./registry.sh images: List all images in the registry"
    echo "./registry.sh delete <image> <tag>: Delete the tag for the image"
    echo "./registry.sh names: List all names"
    echo "./registry.sh tags <image name>: list all tags"
    echo "./registry.sh help: print usage"
}

if [ $# -eq 0 ]; then
    usage_print
    exit 1
fi

case "$1" in
   "images")
        list_images
        ;;
   "delete")
        delete_tags $2 $3
        ;;
    "help")
        usage_print
        ;;
    "names")
        list_names
        ;;
    "tags")
        list_tags $1
        ;;
    "manifest")
        get_manifest $2 $3
        ;;
    "get_pushed_date_time")
        get_pushed_date_time $2 $3
        ;;
    *)
        echo "Invalid option"
        usage_print
        exit 1
        ;;
esac
