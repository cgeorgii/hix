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

  replaceSrc = src: drv:
  pkgs.haskell.lib.overrideCabal drv (_: { inherit src; });

  # TODO compare metadata and fail on mismatch
  pregenDecl = pregen: pkg: decl: let

    properSrc = decl.pregen.src decl.meta pkg;

    impl = meta: {self, ...}: replaceSrc properSrc (self.callPackage meta.drv {});

    d = spec.decl "pregen" "Pregen derivation" { drv = pregen.${pkg}; } impl;

  in
  if hasAttr pkg pregen
  then d.single
  else throw ''
    The package '${pkg}' is declared in the overrides as pregenerated derivation, but the generated file does not
    contain an entry for it.
    Please run 'nix run .#gen-overrides'.
    If that doesn't resolve the issue, the override combinator supplying the derivation might be buggy.
  '';

  replaceDecl = self: super: pregen: pkg: comp: let
    replaced = comp // optionalAttrs comp.decl.pregen.enable { decl = pregenDecl pregen pkg comp.decl; };
  in spec.reifyComp { inherit pkgs self super pkg; } replaced;

  replace = pregen: overrides: self: super: let
    comp = compile overrides self super;
  in mapAttrs (replaceDecl self super pregen) comp;

in {
  inherit normalize compile reify replace;
}
