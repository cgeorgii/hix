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

  # TODO error for missing name
  readOverrides = self: super: let
    pregen = import path;
  in
    if ! (pathExists path)
    then throw ''
    The option 'gen-overrides.enable' is set, but the file '${gen.file}' doesn't exist.
    Please run 'nix run .#gen-overrides' to create it.
    ''
    else if ! (hasAttr config.name pregen)
    then throw  ''
    The pregenerated overrides do not contain an entry for the GHC set named '${config.name}'.
    Please run 'nix run .#gen-overrides' again if you changed this GHC, otherwise this might be a bug.
    ''
    else deps.replace pregen.${config.name} config.overrides self super;

  computeOverrides =
    if gen.enable
    then readOverrides
    else reified;

  packages = prev.haskell.packages.${config.compiler}.override { overrides = computeOverrides; };

in {
  hixPackages = packages // { hix-nixpkgs-rev = config.nixpkgs.rev; hix-name = config.name; };
}
