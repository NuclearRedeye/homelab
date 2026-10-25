{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-SAMSUNG_SSD_PM871b_M.2_2280_128GB_S3U2NF0JA01409";
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
