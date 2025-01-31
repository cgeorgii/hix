{
  pkgs,
  compiler,
  rev,
  name,
  overrides ? [],
}:
final: prev:
with prev.lib;
let

  deps = import ./deps/default.nix { inherit pkgs; };

  packages = prev.haskell.packages.${compiler}.override { overrides = deps.compose overrides; };

in {
  hixPackages = packages // { hix-nixpkgs-rev = rev; hix-name = name; };
}
