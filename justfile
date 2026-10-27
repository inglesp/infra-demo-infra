default:
    @just --list

# Run OpenTofu in tofu/, e.g. `just tofu init`
# Positional arguments, so that the shell doesn't strip quotes inside them
[positional-arguments]
tofu *args:
    tofu -chdir=tofu "$@"

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

# Create a new droplet's vault password, before the droplet itself (see the README's "Add a droplet")
set-vault-password droplet: (tofu "apply" '-target=module.droplet["' + droplet + '"].random_password.vault_password')

# Edit a droplet's secrets, in host_vars/<droplet>/vault.yml, creating the file if needed
vault-edit droplet:
    #!/usr/bin/env bash
    set -euo pipefail
    # The password is a secret. mktemp makes the directory readable only by
    # you, and it's deleted on exit.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # Read from the state with console, rather than from an output, since a new
    # droplet's password is created with a targeted apply, which doesn't
    # update outputs. console prints the password as a quoted string.
    echo 'nonsensitive(module.droplet["{{droplet}}"].vault_password)' \
        | just tofu console | jq -r . > "$tmp/password"
    cd ansible
    vault=host_vars/{{droplet}}/vault.yml
    mkdir -p "$(dirname "$vault")"
    if [ -e "$vault" ]; then action=edit; else action=create; fi
    uv run ansible-vault $action \
        --vault-id "{{droplet}}@$tmp/password" --encrypt-vault-id "{{droplet}}" "$vault"
