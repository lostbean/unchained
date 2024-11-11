{
  description = "Gleam deve environment ⭐";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (
              final: prev: {erlang = final.erlang_27;}
            )
          ];
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gleam
            erlang
            rebar3
          ];

          shellHook = ''
            echo "⭐ environment is ready!"
          '';
        };
      }
    );
}
