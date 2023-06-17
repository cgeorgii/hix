{pkgs}: let

  modifiers = import ./modifiers.nix { inherit pkgs; };
  spec = import ./spec.nix { inherit (pkgs) lib; };

  inherit (spec) transform transform_ decl;

  # TODO modifiers.unbreak will be ineffective for pregen. maybe add a post hook to the decl? or unconditionally unbreak
  # all pregens
  hackageDrv = meta: {self, pkg, options, ...}:
  modifiers.unbreak (self.callHackageDirect { inherit (meta) ver sha256; inherit pkg; } (options.cabal2nix-overrides or {}));

  srcHackage = meta: pkg: let
    pkgver = "${pkg}-${meta.ver}";
  in pkgs.fetchzip {
    url = "mirror://hackage/${pkgver}/${pkgver}.tar.gz";
    inherit (meta) sha256;
  };

  pregenHackage = meta: args: let
    drv = hackageDrv meta args;
  in builtins.readFile "${drv.passthru.cabal2nixDeriver}/default.nix";

  hackage = ver: sha256:
  spec.pregen srcHackage pregenHackage (decl "hackage" "Hackage derivation" { inherit ver sha256; } hackageDrv);

  cabal2nixDrv = {src}: {self, final, pkg, options, ...}:
  self.callCabal2nixWithOptions pkg src (options.cabal2nix or "") (options.cabal2nix-overrides or {});

  srcCabal2nix = meta: pkg: meta.src;

  pregenCabal2nix = meta: args: let
    drv = cabal2nixDrv meta args;
  in builtins.readFile "${drv.passthru.cabal2nixDeriver}/default.nix";

  cabal2nix = src:
  spec.pregen srcCabal2nix pregenCabal2nix (decl "cabal2nix" "Cabal2nix derivation from ${src}" { inherit src; } cabal2nixDrv);

  source = {
    root = cabal2nix;
    sub = src: path: cabal2nix "${src}/${path}";
    package = src: path: cabal2nix src "${src}/packages/${path}";
  };

in {
  inherit hackage source;
}
