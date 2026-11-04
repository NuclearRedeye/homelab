# Homelab

Configuration for my homelab, as a NixOS flake.

## Prerequisites

Clone this repository, and...

- Install [Nix](https://nixos.org/).
- Activate the pre-commit hook using `git config core.hooksPath .githooks`.

## Quick Start

First, activate the nix development shell...

```sh
nix develop
```

Then, check the flake is valid and builds...

```sh
nixos-rebuild build \
  --flake .#<host> \
  --build-host <host> \
  --target-host <host>
```

Then, switch to the new derivation using...

```sh
nixos-rebuild switch \
  --flake .#<host> \
  --build-host <host> \
  --target-host <host> \
  --sudo
```

Any issues, roll back to the previous derivation using...

```sh
nixos-rebuild switch \
  --rollback \
  --target-host <host> \
  --sudo
```

## First Install

New hosts are bootstrapped using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) over ssh. Note, this is a destructive operation!

```sh
nix run --inputs-from . nixpkgs#nixos-anywhere -- \
  --flake .#<host> \
  --target-host <host> \
  --build-on remote
```

Once complete, remove the host's old entry from `known_hosts` before reconnecting.

```sh
ssh-keygen -R <host>
```

A new host can't decrypt secrets until its key is in `.sops.yaml`, so install it and then fetch its host key using...

```sh
ssh-keyscan -t ed25519 <host> | ssh-to-age
```

Add the key to the relevant rule in `.sops.yaml`, then re-encrypt the affected files using...

```sh
sops updatekeys <file>
```

## Secrets

Secrets are encrypted and stored inside the repo using [sops](https://github.com/getsops/sops) and age.

Secrets can be edited/updated in place using...

```sh
sops <file>
```

And decrypted using...

```sh
sops --decrypt <file>
```

Files under `secrets/` with no extension are whole-file secrets, written out verbatim.

## License

Licensed under [MIT](https://choosealicense.com/licenses/mit/).
