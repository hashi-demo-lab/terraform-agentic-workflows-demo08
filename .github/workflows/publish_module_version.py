#!/usr/bin/env python3
"""
Publish a new module version to Terraform Cloud Private Module Registry.

Creates a new module version in TFC using the Registry Modules API,
linking it to a specific Git commit SHA.
"""

import os
import sys
import json
from typing import Dict, Any
import requests


def create_module_version(
    tfe_hostname: str,
    org_name: str,
    module_name: str,
    provider_name: str,
    token: str,
    new_version: str,
    commit_sha: str
) -> Dict[str, Any]:
    """Create a new module version in Terraform Cloud."""
    url = (
        f"https://{tfe_hostname}/api/v2/organizations/{org_name}/"
        f"registry-modules/private/{org_name}/{module_name}/{provider_name}/versions"
    )

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/vnd.api+json"
    }

    payload = {
        "data": {
            "type": "registry-module-versions",
            "attributes": {
                "version": new_version,
                "commit-sha": commit_sha
            }
        }
    }

    try:
        response = requests.post(
            url,
            headers=headers,
            data=json.dumps(payload),
            timeout=30
        )
        response.raise_for_status()

        data = response.json()
        version_id = data.get('data', {}).get('id', 'unknown')

        print(f"Successfully published version {new_version} (ID: {version_id})")
        return data

    except requests.Timeout:
        print("ERROR: Request timed out while publishing module version", file=sys.stderr)
        sys.exit(1)
    except requests.HTTPError as e:
        error_detail = "Unknown error"
        try:
            error_data = e.response.json()
            errors = error_data.get('errors', [])
            if errors:
                error_detail = errors[0].get('detail', str(errors[0]))
        except (json.JSONDecodeError, KeyError):
            error_detail = e.response.text

        print(
            f"ERROR: Failed to publish module version {new_version}\n"
            f"HTTP {e.response.status_code}: {error_detail}",
            file=sys.stderr
        )
        sys.exit(1)
    except requests.RequestException as e:
        print(f"ERROR: Failed to publish module: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


def validate_version_format(version_str: str) -> bool:
    """Validate semantic version format (x.y.z)."""
    try:
        parts = version_str.split('.')
        if len(parts) != 3:
            return False
        for part in parts:
            int(part)
        return True
    except (ValueError, AttributeError):
        return False


def main() -> None:
    """Main entry point."""
    tfe_hostname = os.getenv('TFE_HOSTNAME')
    org_name = os.getenv('TFE_ORG')
    module_name = os.getenv('TFE_MODULE')
    provider_name = os.getenv('TFE_PROVIDER')
    token = os.getenv('TFE_TOKEN')
    commit_sha = os.getenv('COMMIT_SHA')
    new_version = os.getenv('NEW_VERSION')

    missing_vars = []
    for var_name, var_val in [
        ('TFE_HOSTNAME', tfe_hostname), ('TFE_ORG', org_name),
        ('TFE_MODULE', module_name), ('TFE_PROVIDER', provider_name),
        ('TFE_TOKEN', token), ('COMMIT_SHA', commit_sha),
        ('NEW_VERSION', new_version),
    ]:
        if not var_val:
            missing_vars.append(var_name)

    if missing_vars:
        print(
            f"ERROR: Required environment variables not set: {', '.join(missing_vars)}",
            file=sys.stderr
        )
        sys.exit(1)

    if not validate_version_format(new_version):
        print(
            f"ERROR: Invalid version format '{new_version}'. "
            "Expected semantic version (e.g., 1.2.3)",
            file=sys.stderr
        )
        sys.exit(1)

    if len(commit_sha) < 7 or not all(c in '0123456789abcdef' for c in commit_sha.lower()):
        print(f"ERROR: Invalid commit SHA format: {commit_sha}", file=sys.stderr)
        sys.exit(1)

    print(f"Publishing {org_name}/{module_name}/{provider_name} version {new_version}")
    print(f"Linked to commit: {commit_sha}")

    try:
        create_module_version(
            tfe_hostname, org_name, module_name, provider_name,
            token, new_version, commit_sha
        )
        sys.exit(0)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
