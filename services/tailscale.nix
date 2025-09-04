{config, lib, ...}: {
  sops.secrets."tailscale-authkey" = {};

  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets."tailscale-authkey".path;
    useRoutingFeatures = "server";
    extraUpFlags = [
      # Only advertise specific networks that need routing
      # 10.4.0.0/24 - Local homelab network
      # 192.168.1.0/24 - Router/IoT network  
      "--advertise-routes=10.4.0.0/24,192.168.1.0/24"
    ];
  };

  # Note: Tailscale state persistence can be configured separately if using impermanence module
}
