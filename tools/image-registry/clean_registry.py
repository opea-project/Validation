import requests
import json
import sys
import os

# --- Configuration ---
# Docker Registry URL. Can be overridden by DOCKER_REGISTRY_URL environment variable.
DEFAULT_REGISTRY_URL = "http://localhost:5000"
REGISTRY_URL = os.getenv("DOCKER_REGISTRY_URL", DEFAULT_REGISTRY_URL)

# Timeout for requests in seconds
TIMEOUT_SECONDS = 10

# Accept Headers for manifest operations
MANIFEST_ACCEPT_HEADERS = {
    "Accept": "application/vnd.docker.distribution.manifest.v2+json, "
    "application/vnd.docker.distribution.manifest.list.v2+json, "
    "application/vnd.oci.image.manifest.v1+json, "
    "application/vnd.oci.image.index.v1+json"
}

# --- WARNING ---
# This script is DESTRUCTIVE. It will delete image manifests from your Docker Registry.
# Its purpose is to keep ONLY images that have the 'latest' tag in each repository.
# If a repository does not have a 'latest' tag, ALL images in that repository will be deleted.
#
# Prerequisites:
# 1. Ensure your registry is configured to ALLOW DELETES (e.g., REGISTRY_STORAGE_DELETE_ENABLED=true).
# 2. After running this script, you MUST run garbage collection on your registry server
#    to free up disk space, e.g.:
#    docker exec -it <registry_container_name> bin/registry garbage-collect /etc/docker/registry/config.yml
#
# ALWAYS BACK UP YOUR REGISTRY DATA BEFORE RUNNING THIS SCRIPT.
# USE WITH EXTREME CAUTION.
# --- END WARNING ---


def get_repositories(registry_url):
    """Fetches all repository names from the registry."""
    try:
        response = requests.get(f"{registry_url}/v2/_catalog", timeout=TIMEOUT_SECONDS)
        response.raise_for_status()  # Raises HTTPError for bad responses (4XX or 5XX)
        return response.json().get("repositories", [])
    except requests.exceptions.RequestException as e:
        print(f"❌ ERROR: Failed to connect to registry or list repositories: {e}")
        return []
    except json.JSONDecodeError as e:
        print(f"❌ ERROR: Failed to parse repositories response: {e}")
        return []


def get_tags(registry_url, repo_name):
    """Fetches all tags for a given repository."""
    try:
        response = requests.get(f"{registry_url}/v2/{repo_name}/tags/list", timeout=TIMEOUT_SECONDS)
        response.raise_for_status()
        return response.json().get("tags", [])
    except requests.exceptions.RequestException as e:
        print(f"  ❌ ERROR: Failed to get tags for repository '{repo_name}': {e}")
        return []
    except json.JSONDecodeError as e:
        print(f"  ❌ ERROR: Failed to parse tags response for repository '{repo_name}': {e}")
        return []


def get_manifest_digest(registry_url, repo_name, tag):
    """Fetches the manifest digest (SHA256) for a given tag."""
    try:
        # Using HEAD request to avoid downloading the entire manifest body
        response = requests.head(
            f"{registry_url}/v2/{repo_name}/manifests/{tag}", headers=MANIFEST_ACCEPT_HEADERS, timeout=TIMEOUT_SECONDS
        )
        response.raise_for_status()
        digest = response.headers.get("Docker-Content-Digest")
        if not digest:
            print(
                f"  ⚠️ WARNING: No Docker-Content-Digest header for tag '{tag}' in repo '{repo_name}'. "
                "This might be an unsupported image type or a registry issue."
            )
        return digest
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            print(f"  ℹ️ INFO: Manifest for tag '{tag}' in repo '{repo_name}' not found (404).")
        else:
            print(f"  ❌ ERROR: Getting digest for tag '{tag}' in repo '{repo_name}': {e}")
        return None
    except requests.exceptions.RequestException as e:
        print(f"  ❌ ERROR: Network error getting digest for tag '{tag}' in repo '{repo_name}': {e}")
        return None


def delete_manifest(registry_url, repo_name, digest):
    """Deletes a manifest by its digest."""
    if not digest:
        print(f"  ❌ ERROR: Attempted to delete an empty digest for repo '{repo_name}'. Skipping.")
        return False
    try:
        # Per Docker Registry API v2, an Accept header can be useful for DELETE
        response = requests.delete(
            f"{registry_url}/v2/{repo_name}/manifests/{digest}",
            headers=MANIFEST_ACCEPT_HEADERS,  # Some registries might require this
            timeout=TIMEOUT_SECONDS,
        )
        # Successful deletion usually returns 202 Accepted
        if response.status_code == 202:
            print(f"    ✅ SUCCESS: Digest '{digest}' in repo '{repo_name}' marked for deletion (202 Accepted).")
            return True
        response.raise_for_status()  # Handle other HTTP errors
        return True  # Should not be reached if raise_for_status works for non-202
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            print(
                f"    ℹ️ INFO: Digest '{digest}' in repo '{repo_name}' not found, may have been already deleted (404)."
            )
            return True  # Target non-existent, effectively "deleted" for our purpose
        elif e.response.status_code == 405:
            print(
                f"    ❌ ERROR: Deleting digest '{digest}' in repo '{repo_name}' failed (405 Method Not Allowed). "
                "Ensure registry is configured to allow deletes."
            )
        else:
            print(
                f"    ❌ ERROR: Deleting digest '{digest}' in repo '{repo_name}': {e} (Status: {e.response.status_code})"
            )
        return False
    except requests.exceptions.RequestException as e:
        print(f"    ❌ ERROR: Network error deleting digest '{digest}' in repo '{repo_name}': {e}")
        return False


def main():
    """Main cleanup logic."""
    print(f"🚀 Starting registry cleanup for: {REGISTRY_URL}")
    print("=" * 70)
    print("🛑 IMPORTANT WARNING 🛑")
    print("This script is DESTRUCTIVE and will delete image manifests from your Docker Registry.")
    print("It aims to keep ONLY images with the 'latest' tag in each repository.")
    print("If a repository lacks a 'latest' tag, ALL its images will be targeted for deletion.")
    print("Ensure your registry allows deletes and you have adequate backups.")
    print("After this script, run garbage collection on the registry server to reclaim space.")
    print("=" * 70)

    repositories = get_repositories(REGISTRY_URL)
    if not repositories:
        print("No repositories found or failed to connect to the registry. Exiting.")
        return

    print(f"\n🔍 Found {len(repositories)} repositories: {', '.join(repositories) if repositories else 'None'}")

    total_digests_deleted_count = 0
    total_digests_processed_for_deletion = 0

    for repo_name in repositories:
        print(f"\n--- Processing repository: {repo_name} ---")
        tags = get_tags(REGISTRY_URL, repo_name)

        if not tags:
            print(f"  ℹ️ No tags found in repository '{repo_name}'. Skipping.")
            continue

        print(f"  🏷️ Found tags: {', '.join(tags)}")

        latest_tag_digest = None
        if "latest" in tags:
            latest_tag_digest = get_manifest_digest(REGISTRY_URL, repo_name, "latest")
            if latest_tag_digest:
                print(f"  🎯 'latest' tag points to Digest: {latest_tag_digest}")
            else:
                print(
                    f"  ⚠️ WARNING: Could not get digest for 'latest' tag in '{repo_name}'. "
                    "This 'latest' tag cannot be used to preserve an image."
                )
        else:
            print(
                f"  ℹ️ No 'latest' tag found in repository '{repo_name}'. All images in this repo will be targeted for deletion."
            )

        digests_in_repo_map = {}  # Maps tag to its digest
        all_unique_digests_in_repo = set()

        for tag in tags:
            digest = get_manifest_digest(REGISTRY_URL, repo_name, tag)
            if digest:
                digests_in_repo_map[tag] = digest
                all_unique_digests_in_repo.add(digest)
            else:
                print(
                    f"  ⚠️ Could not get digest for tag '{tag}' in repo '{repo_name}'. Skipping this tag for digest collection."
                )

        if not all_unique_digests_in_repo:
            print(f"  ℹ️ No processable manifest digests found in repository '{repo_name}'. Skipping.")
            continue

        digests_to_delete = set()
        if latest_tag_digest:
            # If 'latest' tag and its digest exist, delete all other digests
            for digest in all_unique_digests_in_repo:
                if digest != latest_tag_digest:
                    digests_to_delete.add(digest)
            if digests_to_delete:
                print(f"  🗑️ Will attempt to delete the following non-'latest' digests: {', '.join(digests_to_delete)}")
            else:
                print(
                    f"  👍 All images in '{repo_name}' point to the same digest as 'latest', or only 'latest' exists. No deletion needed based on this rule."
                )
        else:
            # If no 'latest' tag (or its digest couldn't be fetched), delete all digests in this repository
            digests_to_delete.update(all_unique_digests_in_repo)
            if digests_to_delete:
                print(
                    f"  🗑️ No 'latest' tag (or its digest was unavailable). Targeting all digests in this repo for deletion: {', '.join(digests_to_delete)}"
                )
            else:
                print(f"  ℹ️ No 'latest' tag and no other deletable digests found in '{repo_name}'.")

        if not digests_to_delete:
            print(f"  ✅ No deletion operations required for repository '{repo_name}'.")
        else:
            repo_deleted_count = 0
            total_digests_processed_for_deletion += len(digests_to_delete)
            for digest_to_delete in list(digests_to_delete):  # Iterate over a copy
                print(f"  🔥 Attempting to delete Digest: {digest_to_delete} (from repo: {repo_name})")
                # Log tags pointing to this digest for better context
                tags_pointing_to_this_digest = [t for t, d in digests_in_repo_map.items() if d == digest_to_delete]
                if tags_pointing_to_this_digest:
                    print(f"    (This digest is referenced by tags: {', '.join(tags_pointing_to_this_digest)})")

                if delete_manifest(REGISTRY_URL, repo_name, digest_to_delete):
                    repo_deleted_count += 1
            total_digests_deleted_count += repo_deleted_count
            print(
                f"  📊 Repository '{repo_name}': Attempted to delete {len(digests_to_delete)} digests, successfully deleted {repo_deleted_count}."
            )

    print("\n🎉 Cleanup process finished.")
    print(
        f"📈 Summary: Processed {total_digests_processed_for_deletion} digests for deletion, successfully deleted {total_digests_deleted_count} digests across all repositories."
    )
    print("🔔 REMINDER: Run garbage collection on your Docker Registry server to actually free up disk space.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n🚫 Operation interrupted by user.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ An unexpected error occurred: {e}")
        sys.exit(1)
