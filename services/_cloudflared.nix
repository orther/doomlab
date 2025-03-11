{
  config,
  pkgs,
  lib,
  ...
}: {
  sops.secrets = {
    "cloudflare-tunnel" = {
      owner = config.services.cloudflared.user;
      inherit (config.services.cloudflared) group;
      format = "binary";
      sopsFile = ./../secrets/cloudflare-tunnel;
    };
    "cloudflare-token" = {
      owner = config.services.cloudflared.user;
      inherit (config.services.cloudflared) group;
      format = "binary";
      sopsFile = ./../secrets/cloudflare-cert.pem;
    };
  };

  environment.etc."cloudflared/cert.pem".source = config.sops.secrets."cloudflare-token".path;

  services.cloudflared = {
    enable = true;
    tunnels = {
      "doomlab-01" = {
        credentialsFile = config.sops.secrets."cloudflare-tunnel".path;
        default = "http_status:404";
        ingress = {
          "watch.orther.dev" = {
            service = "http://localhost:8096";
          };
        };
      };
    };
  };

  systemd.services = {
    "cloudflared-route-tunnel" = {
      description = "Point traffic to tunnel subdomain";
      after = ["cloudflared-tunnel-doomlab-01.service"];
      wants = ["cloudflared-tunnel-doomlab-01.service"];
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe pkgs.cloudflared} tunnel route dns 'doomlab-01' 'watch.orther.dev'";
      };
    };
  };
}
