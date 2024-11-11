{
  description = "Gleam deve environment ⭐";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
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

        devTools = with pkgs; [
          gleam
          erlang
          rebar3
          ollama
        ];
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = devTools;
          shellHook = ''
            echo "⭐ environment is ready!"
          '';
        };
      }
    );
}
