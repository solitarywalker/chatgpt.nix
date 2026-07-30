{
  description = "Unofficial ChatGPT desktop client (Electron) packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    {
      overlays.default = final: prev: {
        chatgpt-desktop-linux = final.callPackage ./chatgpt.nix { };
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        chatgpt-desktop-linux = pkgs.callPackage ./chatgpt.nix { };
      in
      {
        packages = {
          inherit chatgpt-desktop-linux;
          default = chatgpt-desktop-linux;
        };

        formatter = pkgs.nixfmt-tree;
      }
    );
}
