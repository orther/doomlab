{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
  ];

  services.rpcbind.enable = true;
  
  # Mount the NFS share
  fileSystems."/mnt/docker-data" = {
    device = "10.4.0.50:/volume1/docker-data";
    fsType = "nfs";
    options = [
      "nfsvers=4.1"
      "noatime"
      "actimeo=3"
    ];
  };

}
