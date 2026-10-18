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

  outputs = { self, nixpkgs, disko, sops-nix, ... }: {
    nixosConfigurations.grimlock = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./nixos/hosts/grimlock
      ];
    };
  };
}
