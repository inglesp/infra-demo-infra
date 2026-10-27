default:
    @just --list

# Run OpenTofu in tofu/, e.g. `just tofu init`
tofu *args:
    tofu -chdir=tofu {{args}}

# Show what OpenTofu would change
plan: (tofu "plan")

# Apply OpenTofu's changes
apply: (tofu "apply")

# Check OpenTofu formatting and validity, and Ansible syntax (needs no credentials)
check:
    just tofu fmt -check -recursive
    just tofu init -backend=false -input=false
    just tofu validate
    cd ansible && uv run ansible-playbook --syntax-check -i localhost, playbook.yml

# Edit an app's secrets, in host_vars/<app>/vault.yml, creating the file if needed
vault-edit app:
    #!/usr/bin/env bash
    set -euo pipefail
    # The password is a secret. mktemp makes the directory readable only by
    # you, and it's deleted on exit.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # -e fails if there's no such app, rather than using "null" as the password
    just tofu output -json vault_passwords | jq -er --arg app "{{app}}" '.[$app]' > "$tmp/password"
    cd ansible
    vault=host_vars/{{app}}/vault.yml
    if [ -e "$vault" ]; then action=edit; else action=create; fi
    uv run ansible-vault $action \
        --vault-id "{{app}}@$tmp/password" --encrypt-vault-id "{{app}}" "$vault"
