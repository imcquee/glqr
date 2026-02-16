{
  description = "Gleam development environment";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  outputs = { nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = nixpkgs.legacyPackages.${system};
      });
    in
    {
      devShells = forAllSystems ({ pkgs }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              gleam
              erlang_28
              rebar3
            ]
            ++
            pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [
              inotify-tools
            ]);
            shellHook = ''
              gleam --version
            '';
          };
        });
    };
}
