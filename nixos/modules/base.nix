{ config, lib, pkgs, ... }:
{
  time.timeZone = "Europe/London";

  services.fstrim.enable = true;

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

  # Keep local logs short; long-term retention belongs in central logging
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    MaxRetentionSec=7day
  '';

  # Admin user: key-only login, no password
  users.users.joel = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ../keys/joel.id_rsa.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Unattended updates from the public flake. Nothing automerges, so this
  # only ever applies what has already been merged by hand. Each host sets
  # its own dates, so cluster nodes never upgrade at once.
  system.autoUpgrade = {
    enable = true;
    flake = "github:NuclearRedeye/homelab#${config.networking.hostName}";
    operation = "switch";
    randomizedDelaySec = "15min";

    # Drops --upgrade, which only means anything for channels. On a flake it
    # is inert and logs a warning on every run.
    upgrade = false;

    # FIXME(#19): Unattended reboots are disabled as the hosts are headless,
    # so kernel patches need a manual reboot to be applied.
    allowReboot = false;
  };
}
