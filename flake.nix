{
  description = "git with force push disabled and gh that cannot create issues, pull requests or commits: overlay, NixOS VM tests and Docker image";

  inputs.nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      }));
    in
    {
      overlays.default = import ./nix/overlay.nix;

      packages = forAllSystems (pkgs: {
        inherit (pkgs) git gitFull gh;
        dockerImage = import ./nix/docker.nix { inherit pkgs; };
        default = pkgs.git;
      });

      checks = forAllSystems (pkgs: {
        git = pkgs.git;
        gh = pkgs.gh;
        no-force-push = import ./nix/tests/no-force-push.nix { inherit pkgs; };
        no-gh-writes = import ./nix/tests/no-gh-writes.nix {
          inherit pkgs;
          stockGh = nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.gh;
        };
      });
    };
}
