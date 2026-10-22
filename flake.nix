{
  description = "Homelab";

  inputs = {
    # The package set and NixOS modules. 26.05 is the current stable release.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # Declarative disk partitioning (used at install time).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Decrypts sops secrets onto the machine at boot.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, sops-nix, ... }:
    let
      # Systems the dev shell is offered on.
      forEachSystem = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ];
    in
    {
      nixosConfigurations.grimlock = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./nixos/hosts/grimlock
        ];
      };

      nixosConfigurations.snarl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./nixos/hosts/snarl
        ];
      };

      nixosConfigurations.swoop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./nixos/hosts/swoop
        ];
      };

      nixosConfigurations.slag = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./nixos/hosts/slag
        ];
      };

      # Everything needed to deploy this flake and edit its secrets,
      # versioned by flake.lock rather than by whatever is on PATH.
      devShells = forEachSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [ nixos-rebuild sops age ssh-to-age gitleaks kubectl ];

            # Point kubectl at the homelab cluster, never at whatever ~/.kube/config holds.
            shellHook = ''
              export KUBECONFIG="$HOME/.kube/homelab.yaml"

              # A short prompt that makes it obvious when you're inside the dev shell.
              PS1='[\[\e[1;34m\]nix\[\e[0m\]:\[\e[1;32m\]homelab\[\e[0m\]] \W \$ '
            ''
            # nixos-rebuild budgets its ssh ControlPath against Linux's
            # 107-byte socket limit, but darwin's is 103. A nix shell TMPDIR
            # is 44 bytes, which passes its check and still overflows ssh,
            # so shorten it past the gap.
            + nixpkgs.lib.optionalString pkgs.stdenv.isDarwin ''
              export TMPDIR=/tmp
            '';
          };
        });
    };
}
