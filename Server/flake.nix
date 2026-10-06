{
  description = "13 Years Relay — reproducible Docker image for the realtime cue relay, built with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };

      packageJson = builtins.fromJSON (builtins.readFile ./package.json);
      gitSha = let v = builtins.getEnv "GIT_COMMIT_SHA"; in if v == "" then "dev" else v;

      serverSrc = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.difference
          (pkgs.lib.fileset.fromSource (pkgs.lib.sources.cleanSource ./.))
          (pkgs.lib.fileset.maybeMissing ./node_modules);
      };

      server = pkgs.buildNpmPackage {
        pname = "thirteenyears-relay";
        version = packageJson.version;
        src = serverSrc;
        nodejs = pkgs.nodejs_22;

        npmDepsHash = "sha256-vMNSqN2ZslLVQwOEIDp3OarOSxHiKJ2BVZAGGFNuW98=";

        dontNpmBuild = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r src $out/src
          cp package.json $out/package.json
          cp -r node_modules $out/node_modules
          runHook postInstall
        '';
      };

      nssFiles = pkgs.dockerTools.fakeNss.override {
        extraPasswdLines = [ "relay:x:1001:1001::/app:" ];
        extraGroupLines = [ "relay:x:1001:" ];
      };
    in
    {
      packages.${system} = {
        default = self.packages.${system}.docker;
        server = server;

        docker = pkgs.dockerTools.buildLayeredImage {
          name = "thirteenyears-relay";
          tag = "latest";

          contents = [
            pkgs.dockerTools.binSh
            pkgs.dockerTools.usrBinEnv
            nssFiles
            pkgs.tzdata
            pkgs.cacert
          ];

          config = {
            Entrypoint = [ "${pkgs.nodejs_22}/bin/node" "${server}/src/index.js" ];
            WorkingDir = "${server}";
            User = "1001:1001";
            Env = [
              "NODE_ENV=production"
              "PORT=8080"
              "GIT_COMMIT_SHA=${gitSha}"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "PLOTIPHAR_API_BASE=https://plotiphar.com"
            ];
            ExposedPorts = {
              "8080/tcp" = { };
            };
          };
        };
      };
    };
}
