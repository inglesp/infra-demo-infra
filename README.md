# infra-demo-infra

Infrastructure and configuration as code for demo apps such as [infra-demo-app](https://github.com/inglesp/infra-demo-app).

## Infrastructure

Apps run on DigitalOcean droplets, managed with [OpenTofu](https://opentofu.org/) in `tofu/`.
Each app in `local.apps` in `tofu/main.tf` gets its own droplet, created by the `web-app` module.
There are no apps yet.
Each droplet has a block storage volume attached, for all persistent data, so that the droplet itself can be replaced.
OpenTofu refuses to destroy a volume: to really delete one, first remove `prevent_destroy` from the `web-app` module.
Changing a droplet's image or SSH keys only affects new droplets, rather than replacing existing ones.
Each droplet has a cloud firewall that allows inbound SSH, HTTP, HTTPS and ICMP, and all outbound traffic.
Each app also has its own DNS zone in DigitalOcean, with A and AAAA records pointing at its droplet.

At a droplet's first boot, cloud-init writes its settings and secrets to `/etc/web-app/`, installs Ansible, and runs `ansible-pull` against `main` of this repo, which configures the droplet (see [Server configuration](#server-configuration)).
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
The state holds secrets, such as each app's Django secret key, which OpenTofu generates and puts in the droplet's `user_data`.
State is locked while OpenTofu uses it, with a lock file next to it in the bucket, so two runs can't change it at once.

## Server configuration

What runs on each droplet is configured with [Ansible](https://docs.ansible.com/), in `ansible/`.
Each droplet configures itself: every minute, before deploying (see [Deploys](#deploys)), it runs `ansible-pull`, which applies the playbook from `main` if `main` has changed since the last run.
That's the only way config reaches a droplet, and a change pushed to `main` is applied within a minute or so.
If applying the playbook fails, the run still deploys the image, but shows as a failed `deploy` unit, and the next run tries the playbook again.

The playbook:

- installs Docker, [Dokku](https://dokku.com/) and Dokku's [letsencrypt plugin](https://github.com/dokku/dokku-letsencrypt), and sets the plugin's email and renewal cron job
- blocks containers from DigitalOcean's metadata service, which serves the droplet's `user_data`, and so its secrets, to anything on the droplet that asks
- mounts the droplet's volume at `/srv/<app>/data`, owned by UID 10001, which the app runs as, in place of DigitalOcean's own mount under `/mnt/`
- creates the app in Dokku, and sets its domain, its environment (`app_env` in the `web_app` role's defaults) and its ports
- mounts the volume into the app's container at `/data`, where the app keeps its database
- installs the deploy service and the alerts (see below)

The letsencrypt plugin is pinned to a commit, `letsencrypt_plugin_commit` in the role's defaults, and changing that updates it.

Once the app has been deployed, the deploy service (see [Deploys](#deploys)) gets it a TLS certificate from Let's Encrypt, which the cron job renews.
HTTP then redirects to HTTPS, and Dokku turns on HSTS, so browsers that have visited will only use HTTPS for the domain.

Dokku has no declarative config, only commands, so Ansible reads each Dokku setting first and only runs a command when the setting differs.

### Secrets

Secrets that OpenTofu doesn't generate are kept in the repo, encrypted with [ansible-vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html), in `ansible/host_vars/<app>/vault.yml`.
Each app's vault has its own password, which OpenTofu generates, and which is on the app's droplet, so the droplet can decrypt it.
To edit an app's secrets in `$EDITOR`, creating the file if needed:

```sh
just vault-edit <app>
```

To give the app a secret environment variable, add it under `app_secret_env` in the vault:

```yaml
app_secret_env:
  SOME_API_KEY: ...
```

Removing a variable from the vault doesn't remove it from the app: run `dokku config:unset <app> <variable>` on the droplet.

### Deploys

Each app's image and tag are set in `ansible/host_vars/<app>/main.yml`, which Ansible writes to `/etc/web-app/image` on the droplet.
Every minute, a systemd timer on the droplet starts the `deploy` service, which first applies any changes to `main` with `ansible-pull`.
It then pulls the image, and deploys it by digest if the digest differs from the one Dokku last deployed.
It then enables TLS for the app, if it isn't already enabled.
So a new image goes live within a minute or so of being published, and a change to the image or tag is applied and deployed in the same run.
To deploy straight away, run `systemctl start deploy` on the droplet.
Its output is in `journalctl -u deploy`.

### Alerts

When the deploy service starts failing, the droplet posts the end of the failed run's log to a Slack channel, and when it next succeeds, it posts that it has recovered.
Runs that fail while it's already failing don't post again.
The droplet posts through an [incoming webhook](https://api.slack.com/messaging/webhooks), which belongs to a Slack app created at https://api.slack.com/apps.
The webhook's URL is a secret, set as `alert_webhook_url` in the app's vault.
To send a test alert, run `systemctl start notify-failure@deploy.service` on the droplet. The next successful run then posts that it has recovered.

## Runbook

### SSH into a droplet

```sh
ssh root@$(just tofu output -json ips | jq -r '.["<app>"]')
```

### After a droplet is replaced

The droplet's data is on its volume, which is moved to the new droplet, but everything else needs setting up again.
The new droplet has a new IP address and new SSH host keys, so first remove the old keys, using the old IP address:

```sh
ssh-keygen -R <domain>
ssh-keygen -R <old IP address>
```

The new droplet configures itself at first boot, which takes a few minutes, and within a minute after that, deploys the app and enables TLS.
`cloud-init status --wait` on the droplet waits for the first boot to finish.
The DNS records can take up to 30 minutes to point at the new IP address everywhere.

### Roll back to an earlier build

Set `image_tag` in `ansible/host_vars/<app>/main.yml` to `sha-<commit>`, where `<commit>` is the full SHA of a commit on the app repo's `main`, and push the change.
Within a minute or so, the droplet applies and deploys it.
Set it back to `latest`, and push that, to return to deploying each new build.

### Remove a stale state lock

If an OpenTofu run is killed before it releases its lock, later runs fail with "Error acquiring the state lock".
Check that nobody else is running OpenTofu, then remove the lock, using the ID from the error:

```sh
just tofu force-unlock <ID>
```
