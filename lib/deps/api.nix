{
  pkgs,
  self,
  super,
}:
with builtins;
with pkgs.lib;
let
  modifiers = import ./modifiers.nix { inherit pkgs; };
  spec = import ./spec.nix { inherit (pkgs) lib; };

  inherit (spec) transform transform_ set;
  hl = pkgs.haskell.lib;

  option = name: value: spec:
  let
    old = spec.options or {};
  in spec // { options = old // { ${name} = value; }; };

  options = name: default: spec:
  (spec.options or {}).${name} or default;


  transformers = {
    jailbreak = transform_ hl.doJailbreak;
    configure = flag: transform_ (flip hl.appendConfigureFlag flag);
    configures = flags: transform_ (flip hl.appendConfigureFlags flags);
    override = conf: transform_ (flip hl.overrideCabal conf);
    overrideAttrs = f: transform_ (drv: drv.overrideAttrs f);
    buildInputs = inputs: transform_ (drv: drv.overrideAttrs (old: { buildInputs = old.buildInputs ++ inputs; }));
    minimal = transform_ modifiers.minimal;
    profiling = transform_ modifiers.profiling;
    noprofiling = transform_ modifiers.noprofiling;
    unbreak = transform_ modifiers.unbreak;
    fast = transform_ modifiers.fast;
    notest = transform_ modifiers.notest;
    nodoc = transform_ modifiers.nodoc;
    bench = transform_ modifiers.bench;
    nobench = transform_ modifiers.nobench;
  };

  hackage = ver: sha256: spec.create ({ self, pkg, ... }: {
    drv = modifiers.unbreak (self.callHackageDirect { inherit pkg ver sha256; } {});
  });

  cabal2nix = src: spec.create ({ self, final, pkg, ... }: {
    drv = self.callCabal2nixWithOptions pkg src (options "cabal2nix" "" final) (options "cabal2nix-overrides" {} final);
  });

  source = rec {
    root = cabal2nix;
    sub = src: path: cabal2nix "${src}/${path}";
    package = src: path: sub src "packages/${path}";
  };

  drv = d: set { drv = d; };

  keep = drv null;

  noHpack = option "cabal2nix" "--no-hpack";

  cabalOverrides = option "cabal2nix-overrides";

in transformers // {
  inherit hackage source self super pkgs keep transform transform_ option noHpack cabalOverrides drv;
  hsLib = hl;
  inherit (pkgs) system lib;
  compilerName = self.ghc.name;
  compilerVersion = self.ghc.version;
}
