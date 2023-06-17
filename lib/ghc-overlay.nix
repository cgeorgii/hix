{
  global,
  config,
}:
final: prev:
with prev.lib;
let

  gen = global.gen-overrides;

  reified = deps.reify config.overrides;

  path = "${global.base}/${gen.file}";

  deps = import ./deps/default.nix { pkgs = prev; };

  readOverrides = self: super:
    if ! (pathExists path)
    then throw ''
    The option 'gen-overrides.enable' is set, but the file '${gen.file}' doesn't exist.
    Please run 'nix run .#gen-overrides' to create it.
    ''
    else deps.replace (import path) config.overrides self super;

  computeOverrides =
    if gen.enable
    then readOverrides
    else reified;

  packages = prev.haskell.packages.${config.compiler}.override { overrides = computeOverrides; };

in {
  hixPackages = packages // { hix-nixpkgs-rev = config.nixpkgs.rev; hix-name = config.name; };
}
