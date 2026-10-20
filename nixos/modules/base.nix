{ config, lib, pkgs, ... }:
{
  # Nix settings and housekeeping
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
    min-free = 5368709120; # When < 5GiB free space remains
    max-free = 16106127360; # collect garbage until >=15 GiB is free
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.optimise.automatic = true;
}
