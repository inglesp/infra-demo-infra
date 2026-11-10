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

# Create a new droplet's vault password and logging client cert, before the droplet itself (see the README's "Add a droplet")
set-vault-password droplet: (tofu "apply" '-target=module.droplet["' + droplet + '"].random_password.vault_password' '-target=tls_locally_signed_cert.log_client["' + droplet + '"]')

# Write each droplet's logging TLS files to host_vars/<droplet>/log_tls.yml, encrypted with its vault password
sync-log-tls:
    #!/usr/bin/env bash
    set -euo pipefail
    # The keys and passwords are secrets. mktemp makes the directory readable
    # only by you, and it's deleted on exit.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # Read from the state with console, rather than from outputs, since a new
    # droplet's cert is created with a targeted apply, which doesn't update
    # outputs. console prints each as a quoted string of JSON.
    echo 'nonsensitive(jsonencode(local.log_tls))' \
        | just tofu console | jq -r . > "$tmp/tls.json"
    echo 'nonsensitive(jsonencode({ for name, d in module.droplet : name => d.vault_password }))' \
        | just tofu console | jq -r . > "$tmp/passwords.json"
    cd ansible
    for droplet in $(jq -r 'keys[]' "$tmp/tls.json"); do
        f=host_vars/$droplet/log_tls.yml
        mkdir -p "$(dirname "$f")"
        jq -r --arg d "$droplet" '.[$d]' "$tmp/passwords.json" > "$tmp/password"
        # JSON is valid YAML
        jq --arg d "$droplet" '.[$d]' "$tmp/tls.json" > "$tmp/new.yml"
        # Only rewrite a file when its contents change, since encrypting it
        # again would change it anyway
        if [ -e "$f" ] && uv run ansible-vault view --vault-id "$droplet@$tmp/password" "$f" \
            | cmp -s - "$tmp/new.yml"; then
            continue
        fi
        uv run ansible-vault encrypt \
            --vault-id "$droplet@$tmp/password" --encrypt-vault-id "$droplet" \
            --output "$f" "$tmp/new.yml"
        echo "Updated $f"
    done

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
