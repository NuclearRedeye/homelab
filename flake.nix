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
      # Systems the dev shell is offered on; add x86_64-linux to deploy
      # from something other than the Mac.
      forEachSystem = nixpkgs.lib.genAttrs [ "aarch64-darwin" ];
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

      # Everything needed to deploy this flake and edit its secrets,
      # versioned by flake.lock rather than by whatever is on PATH.
      devShells = forEachSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [ nixos-rebuild sops age ssh-to-age gitleaks ];
          };
        });
    };
}
