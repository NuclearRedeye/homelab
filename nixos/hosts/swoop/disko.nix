{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-SAMSUNG_MZNLH128HBHQ-000H1_S4HENX1N708951";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
