{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    nfs-utils  # NFS client utilities
    krb5       # Kerberos utilities for authentication
  ];

  services.rpcbind.enable = true;
  
  # Enhanced NFS security configuration
  fileSystems."/mnt/docker-data" = {
    device = "10.4.0.50:/volume1/docker-data";
    fsType = "nfs";
    options = [
      "nfsvers=4.1"        # Use NFS v4.1 for better security
      "noatime"            # Performance optimization
      "actimeo=3"          # Attribute cache timeout
      "proto=tcp"          # Use TCP for reliability
      "fsc"                # Enable local caching
      "hard"               # Hard mount for data integrity
      "intr"               # Allow interruption of NFS requests
      "rsize=32768"        # Optimized read size
      "wsize=32768"        # Optimized write size
      "timeo=14"           # Timeout in deciseconds
      "retrans=2"          # Number of retransmissions
      # Note: sec=krb5p would provide Kerberos auth + encryption
      # but requires Kerberos infrastructure setup
      "sec=sys"            # Use system authentication for now
    ];
  };

  # Optional: Configure for future Kerberos integration
  # Uncomment when Kerberos infrastructure is available
  # services.kerberos = {
  #   enable = true;
  #   realms = {
  #     "HOMELAB.LOCAL" = {
  #       kdc = "10.4.0.50";
  #       admin_server = "10.4.0.50";
  #     };
  #   };
  #   libdefaults = {
  #     default_realm = "HOMELAB.LOCAL";
  #   };
  # };

  # Firewall rules for NFS
  networking.firewall = {
    allowedTCPPorts = [ 
      111   # portmapper
      2049  # nfs
    ];
    allowedUDPPorts = [ 
      111   # portmapper  
      2049  # nfs
    ];
  };

}
