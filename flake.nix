{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    {
      nixpkgs,
      self,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
      pkgsForSystem = system: (import nixpkgs { inherit system; });
    in
    {
      nixosModules = rec {
        watcher = import ./module.nix;
        default = watcher;
      };
      nixosConfigurations.pcA = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./example/example.nix
          self.nixosModules.watcher
        ];
      };
      formatter = forAllSystems (
        system:
        let
          pkgs = (pkgsForSystem system);
        in
        pkgs.nixfmt-rfc-style
      );
    };
}
