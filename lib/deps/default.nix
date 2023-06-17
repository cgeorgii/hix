{ pkgs, }:
with pkgs.lib;
let
  util = import ../../lib/default.nix { inherit (pkgs) lib; };

  spec = import ./spec.nix { inherit (pkgs) lib; };

  normalize = overrides: self: super: let
    api = import ./api2.nix { inherit pkgs self super; };
  in zipAttrsWith (_: concatLists) (map (o: mapAttrs (_: spec.listOC) (o api)) overrides);

  compile = overrides: self: super:
  mapAttrs (_: spec.compile) (normalize overrides self super);

  reifySpec = self: super: pkg: spec.reify { inherit pkgs self super pkg; };

  reify = overrides: self: super:
  mapAttrs (reifySpec self super) (normalize overrides self super);

  pregenDecl = drv:
  (spec.decl "pregen" "Pregen derivation" { inherit drv; } (meta: args: args.self.callPackage meta.drv {})).single;

  # TODO replace `src`
  replaceDecl = self: super: pregen: pkg: comp: let
    replaced =
      if hasAttr pkg pregen
      then comp // { decl = pregenDecl pregen.${pkg}; }
      else comp;
  in spec.reifyComp { inherit pkgs self super pkg; } replaced;

  replace = pregen: overrides: self: super: let
    comp = compile overrides self super;
  in mapAttrs (replaceDecl self super pregen) comp;

in {
  inherit normalize compile reify replace;
}
