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
  --flake .#grimlock \
  --build-host grimlock \
  --target-host grimlock
```

Then, switch to the new derivation using...

```sh
nixos-rebuild switch \
  --flake .#grimlock \
  --build-host grimlock \
  --target-host grimlock \
  --sudo
```

Any issues, roll back to the previous derivation using...

```sh
nixos-rebuild switch \
  --rollback \
  --target-host grimlock \
  --sudo
```

## Secrets

Secrets are encrypted and stored inside the repo using [sops](https://github.com/getsops/sops) and age.

Secrets can be edited/updated in place using...

```sh
sops secrets/grimlock.yaml
```

And decrypted using...

```sh
sops --decrypt secrets/pihole-net
```

Files under `secrets/` with no extension are whole-file secrets, written out verbatim.

## License

Licensed under [MIT](https://choosealicense.com/licenses/mit/).
