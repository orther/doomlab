{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    pkgs.cifs-utils
  ];

  sops.secrets."smb-secrets" = {
    ##owner = config.services.cloudflared.user;
    ##inherit (config.services.cloudflared) group;
    format = "binary";
    sopsFile = ./../secrets/smb-secrets;
  };

  fileSystems."/mnt/docker-data" = {
      device = "//10.4.0.50/path/to/docker-data";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

      in ["${automount_opts},credentials=${config.sops.secrets."smb-secrets".path}"];
  };


  networking.firewall.extraCommands = ''iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns'';

}
