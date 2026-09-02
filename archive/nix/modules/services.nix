{ config, pkgs, lib, ... }:

let
  # urserver (Unified Remote daemon) — closed source, distributed as a tarball.
  # Not in nixpkgs; pin the upstream build and unpack into the store.
  #
  # The path is /linux-x64/<build>/urserver-<version>.tar.gz, where <build> is
  # only the last version component — not the full version, and with no "-1"
  # suffix. An earlier pin here guessed the full version as the directory and
  # 404'd, which no hash would have fixed.
  #
  # To bump: resolve https://www.unifiedremote.com/download/linux-x64-portable
  # (a 302 to the current build) and nix-prefetch-url the target. Upstream
  # garbage-collects old builds, so a pin that has fallen behind eventually
  # 404s rather than merely being stale — treat a fetch failure here as "find
  # the new build", not "the hash is wrong".
  urserver = pkgs.stdenv.mkDerivation rec {
    pname = "urserver";
    version = "3.14.0.2574";

    src = pkgs.fetchurl {
      url = "https://www.unifiedremote.com/static/builds/server/linux-x64/"
        + "${lib.last (lib.splitString "." version)}/urserver-${version}.tar.gz";
      hash = "sha256-4wA2VPb5QN30TWa72pUVTYfvsxlGTO8Vngh7wDHXhDE=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = with pkgs; [ stdenv.cc.cc.lib zlib ];

    installPhase = ''
      mkdir -p $out/opt/urserver
      cp -r * $out/opt/urserver/
      mkdir -p $out/bin
      ln -s $out/opt/urserver/urserver-start $out/bin/urserver-start
    '';

    meta.description = "Unified Remote server";
  };
in
{
  # No containers, and deliberately no container runtime: docker was here only
  # for the AIOStreams and stremio-server stacks, and both are gone.
  #
  # No separate streaming server: Stremio v5 bundles its own, so running another
  # meant two node processes fighting over ports 11470/12470 (the loser fell
  # back to 11471 and sat idle). The torrent tuning lives in the bundled
  # server's settings instead — see cacheSize/btMaxConnections in the README.
  #
  # No AIOStreams: it ran for two months without a single request (nothing had
  # the addon installed) so it was removed rather than carried forward. If it
  # ever comes back it needs BASE_URL on a hostname, not a DHCP address — the
  # old deployment broke silently when the box's lease moved.

  # No cellular modem in this laptop, so ModemManager only adds a daemon and
  # boot-time device probing.
  systemd.services.ModemManager.enable = false;

  # urserver is started by the kiosk session (home/files/kiosk-wayland.sh),
  # which also watchdogs it. All we expose here is the LAN-visible web-UI
  # proxy on :9530 → 127.0.0.1:9510.
  systemd.services.urserver-web-proxy = {
    description = "Expose Unified Remote web UI on the LAN";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.socat}/bin/socat TCP6-LISTEN:9530,fork,reuseaddr,ipv6only=0 TCP:127.0.0.1:9510";
      Restart = "on-failure";
      RestartSec = "3";
    };
  };

  # Ports we own.
  networking.firewall.allowedTCPPorts = [
    22       # ssh
    9530     # unified remote web UI proxy
    9510     # unified remote (local only, but firewall would block xdg LAN clients)
    9512     # unified remote binary protocol
    11470    # stremio-server http
    11471    # stremio-server https
    12470    # stremio-server peer
    40719    # uxplay control
    7000     # uxplay airplay
    7001     # uxplay airplay
  ];
  networking.firewall.allowedUDPPorts = [
    5353     # mDNS
    7011     # uxplay airplay
    6000 6001 6002  # uxplay raop
  ];

  # urserver as a package — launched and watchdogged by home/files/kiosk-wayland.sh.
  environment.systemPackages = [ urserver ];
}
