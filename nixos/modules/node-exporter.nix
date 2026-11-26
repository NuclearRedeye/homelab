{ config, lib, pkgs, ... }:
let
  # Issued once by scripts/telemetry-cert.sh, into this host's own secrets file
  secret = {
    sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
    owner = "node-exporter";
    restartUnits = [ "prometheus-node-exporter.service" ];
  };

  webConfig = (pkgs.formats.yaml { }).generate "node-exporter-web.yml" {
    tls_server_config = {
      cert_file = config.sops.secrets.node_exporter_cert.path;
      key_file = config.sops.secrets.node_exporter_key.path;
      client_ca_file = "${../keys/telemetry-ca.crt}";
      client_auth_type = "RequireAndVerifyClientCert";
      # Revoke a leaked client by reissuing it under a new name and changing this
      client_allowed_sans = [ "vmagent" ];
      min_version = "TLS13";
    };
  };
in
{
  sops.secrets.node_exporter_key = secret;
  sops.secrets.node_exporter_cert = secret;

  services.prometheus.exporters.node = {
    enable = true;
    # Open to the LAN: mTLS, not the firewall, decides who can scrape
    openFirewall = true;
    extraFlags = [ "--web.config.file=${webConfig}" ];
  };
}
