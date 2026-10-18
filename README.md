# Homelab

NixOS configuration for my homelab, as a flake. One host so far.

## Layout

```
flake.nix              inputs and the nixosConfigurations
nixos/hosts/<host>     per-host configuration, including disko layout
nixos/modules          reusable service modules
services/<group>/<svc> compose stacks, referenced by the modules
secrets                sops-encrypted; decrypted at activation
```

## Deploying

Secrets are decrypted on the host at activation, so a deploy is just a
rebuild:

```sh
nixos-rebuild switch --flake .#grimlock --target-host root@grimlock
```

## First install

Partition with disko, then install. This wipes the target disk:

```sh
nix run github:nix-community/disko -- --mode disko --flake .#grimlock
nixos-install --flake .#grimlock
```

The host needs its own age key before secrets will decrypt. That key is
derived from `/etc/ssh/ssh_host_ed25519_key`, so generate the host keys
first and add the public age key to `.sops.yaml`.

## Secrets

Encrypted with [sops](https://github.com/getsops/sops) and age. Edit in
place; `.sops.yaml` decides the recipients:

```sh
sops secrets/grimlock.yaml
```

Files under `secrets/` with no extension are whole-file secrets, written
out verbatim and consumed as env files. Decrypt one with:

```sh
sops --decrypt --input-type json --output-type binary secrets/pihole-net
```

## Working on this repo

Enable the pre-commit hook once per clone. It runs
[gitleaks](https://github.com/gitleaks/gitleaks) over staged changes and
refuses to commit anything that looks like a credential:

```sh
git config core.hooksPath .githooks
```
