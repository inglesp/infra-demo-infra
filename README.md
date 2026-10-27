# infra-demo-infra

Infrastructure and configuration as code for demo apps such as [infra-demo-app](https://github.com/inglesp/infra-demo-app).

## Infrastructure

Apps run on DigitalOcean droplets, managed with [OpenTofu](https://opentofu.org/) in `tofu/`.
`droplets.yml` lists the droplets, and the apps each one runs.
OpenTofu creates each droplet with the `droplet` module, and each app's resources with the `app` module.

Each droplet has a cloud firewall that allows inbound SSH, HTTP, HTTPS and ICMP, and all outbound traffic.
Changing a droplet's image or SSH keys only affects new droplets, rather than replacing existing ones.

Each app has a block storage volume attached to its droplet, for all its persistent data, so that the droplet itself can be replaced.
OpenTofu refuses to destroy a volume: to really delete one, first remove `prevent_destroy` from the `app` module.
Each app also has its own DNS zone in DigitalOcean, with A and AAAA records pointing at its droplet.
Adding or removing an app doesn't change its droplet.

At a droplet's first boot, cloud-init writes its settings and vault password to `/etc/web-app/`, installs Ansible, and runs `ansible-pull` against `main` of this repo, which configures the droplet (see [Server configuration](#server-configuration)).
Changing the cloud-init config (the droplet's `user_data`) replaces the droplet: see [After a droplet is replaced](#after-a-droplet-is-replaced).

You need:

- [just](https://github.com/casey/just), [uv](https://docs.astral.sh/uv/), [OpenTofu](https://opentofu.org/docs/intro/install/), [doctl](https://docs.digitalocean.com/reference/doctl/how-to/install/) and [jq](https://jqlang.org/)
- a DigitalOcean API token with full access, named `infra-demo-tofu-local`, exported as `DIGITALOCEAN_ACCESS_TOKEN` (OpenTofu and doctl both read it)
- your SSH public key uploaded to DigitalOcean with the name in `local.ssh_key_name`:

  ```sh
  doctl compute ssh-key import inglesp --public-key-file ~/.ssh/id_ed25519.pub
  ```

- a Spaces access key named `infra-demo-tofu-state-local`, with read/write access to the state bucket (see below), exported as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- the state passphrase, from the password manager, exported as `TF_VAR_state_passphrase`
- each app's zone delegated to DigitalOcean: opensafely.org's DNS is on Cloudflare, which needs NS records for the app's subdomain pointing to `ns1.digitalocean.com`, `ns2.digitalocean.com` and `ns3.digitalocean.com`

```sh
just tofu init  # once, to download the provider and connect to the state bucket
just plan       # show what would change
just apply      # make the changes
```

`just tofu ...` runs any other OpenTofu command in `tofu/`.

`just check` checks that the OpenTofu config is formatted and valid, and that the Ansible playbook's syntax is valid.
It needs no credentials, and CI runs it on every pull request and on pushes to `main`.
Its actions are pinned to commit SHAs.

OpenTofu's state is kept in the `inglesp-infra-demo-tofu-state` Spaces bucket, in `lon1`, as `infra-demo-infra.tfstate`.
The bucket was created by hand, since it can't hold its own state.
The state is encrypted with the state passphrase: if the passphrase is lost, so is the state.
The state holds secrets: each droplet's vault password, which OpenTofu generates and puts in the droplet's `user_data`.
State is locked while OpenTofu uses it, with a lock file next to it in the bucket, so two runs can't change it at once.

## Server configuration

The droplets, and the apps each one runs, are listed in `droplets.yml`, which describes each app's settings.
What runs on each droplet is configured with [Ansible](https://docs.ansible.com/), in `ansible/`.
Each droplet configures itself: every minute, before deploying (see [Deploys](#deploys)), it runs `ansible-pull`, which applies the playbook from `main` if `main` has changed since the last run.
That's the only way config reaches a droplet, and a change pushed to `main` is applied within a minute or so.
If applying the playbook fails, the run still deploys the image, but shows as a failed `deploy` unit, and the next run tries the playbook again.

The playbook:

- installs Docker, [Dokku](https://dokku.com/) and Dokku's [letsencrypt plugin](https://github.com/dokku/dokku-letsencrypt), and sets the plugin's email and renewal cron job
- blocks containers from DigitalOcean's metadata service, which serves the droplet's `user_data`, and so its secrets, to anything on the droplet that asks
- for each app:
    - mounts the app's volume at `/srv/<app>/data`, owned by UID 10001, which every app's image must run as (and listen on port 8000), in place of DigitalOcean's own mount under `/mnt/`
    - creates the app in Dokku, and sets its domain, its environment (`env`, plus its secrets) and its ports
    - mounts the volume into the app's container at `/data`, where the app keeps its database
- installs the deploy service and the alerts (see below)

The letsencrypt plugin is pinned to a commit, `letsencrypt_plugin_commit` in the role's defaults, and changing that updates it.

Once an app has been deployed, the deploy service (see [Deploys](#deploys)) gets it a TLS certificate from Let's Encrypt, which the cron job renews.
HTTP then redirects to HTTPS, and Dokku turns on HSTS, so browsers that have visited will only use HTTPS for the domain.

Dokku has no declarative config, only commands, so Ansible reads each Dokku setting first and only runs a command when the setting differs.

### Secrets

Secrets are kept in the repo, encrypted with [ansible-vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html), in `ansible/host_vars/<droplet>/vault.yml`.
Each droplet's vault has its own password, which OpenTofu generates, and which is on the droplet, so the droplet can decrypt it.
To edit a droplet's secrets in `$EDITOR`, creating the file if needed:

```sh
just vault-edit <droplet>
```

The vault holds the droplet's `alert_webhook_url` (see [Alerts](#alerts)), and each app's secret environment variables under `app_secrets`, where every app needs an entry:

```yaml
app_secrets:
  <app>:
    DJANGO_SECRET_KEY: ...  # generate with: openssl rand -hex 32
    SOME_API_KEY: ...
```

Removing a variable from `env` or the vault doesn't remove it from the app: run `dokku config:unset <app> <variable>` on the droplet.

### Deploys

Each app's `image` and `image_tag` are set in `droplets.yml`, and Ansible writes the droplet's apps to `/etc/web-app/apps.json`.
Every minute, a systemd timer on the droplet starts the `deploy` service, which first applies any changes to `main` with `ansible-pull`.
Then, for each app, it pulls the image, and deploys it by digest if the digest differs from the one Dokku last deployed.
It then enables TLS for the app, if it isn't already enabled.
If one app fails to deploy, the others are still deployed, and the run shows as failed.
So a new image goes live within a minute or so of being published, and a change to an image or tag is applied and deployed in the same run.
To deploy straight away, run `systemctl start deploy` on the droplet.
Its output is in `journalctl -u deploy`.

### Alerts

When the deploy service starts failing, the droplet posts the end of the failed run's log to a Slack channel, and when it next succeeds, it posts that it has recovered.
Runs that fail while it's already failing don't post again.
The droplet posts through an [incoming webhook](https://api.slack.com/messaging/webhooks), which belongs to a Slack app created at https://api.slack.com/apps.
The webhook's URL is a secret, set as `alert_webhook_url` in the droplet's vault.
To send a test alert, run `systemctl start notify-failure@deploy.service` on the droplet. The next successful run then posts that it has recovered.

## Runbook

### SSH into a droplet

```sh
ssh root@$(just tofu output -json ips | jq -r '.["<droplet>"]')
```

### Add a droplet

The droplet's first run needs its vault, which needs its password, so the password is created first:

1. Add the droplet and its apps to `droplets.yml`, and delegate each app's zone (see [Infrastructure](#infrastructure)).
2. Create the droplet's vault password:

   ```sh
   just tofu apply -target='module.droplet["<droplet>"].random_password.vault_password'
   ```

3. Add `alert_webhook_url` and each app's `app_secrets` (see [Secrets](#secrets)) with `just vault-edit <droplet>`.
4. Commit and push.
5. Create the droplet and its apps' resources with `just apply`.

The droplet configures itself at first boot, which takes a few minutes, and within a minute after that, deploys its apps and enables TLS.
`cloud-init status --wait` on the droplet waits for the first boot to finish.

### Add an app to a droplet

1. Delegate the app's zone (see [Infrastructure](#infrastructure)).
2. Add the app's `app_secrets` with `just vault-edit <droplet>`.
3. Add the app to the droplet in `droplets.yml`.
4. Create the app's volume, attachment and zone with `just apply`.
5. Commit and push.

Apply before pushing: otherwise the droplet's next run waits for a volume that doesn't exist yet, and fails.

### After a droplet is replaced

The droplet's apps' data is on their volumes, which are moved to the new droplet, but everything else needs setting up again.
The new droplet has a new IP address and new SSH host keys, so first remove the old keys, using the old IP address:

```sh
ssh-keygen -R <old IP address>
```

The new droplet configures itself at first boot, which takes a few minutes, and within a minute after that, deploys its apps and enables TLS.
`cloud-init status --wait` on the droplet waits for the first boot to finish.
The DNS records can take up to 30 minutes to point at the new IP address everywhere.

### Roll back to an earlier build

Set the app's `image_tag` in `droplets.yml` to `sha-<commit>`, where `<commit>` is the full SHA of a commit on the app repo's `main`, and push the change.
Within a minute or so, the droplet applies and deploys it.
Set it back to `latest`, and push that, to return to deploying each new build.

### Remove a stale state lock

If an OpenTofu run is killed before it releases its lock, later runs fail with "Error acquiring the state lock".
Check that nobody else is running OpenTofu, then remove the lock, using the ID from the error:

```sh
just tofu force-unlock <ID>
```
