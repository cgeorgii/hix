{
  base,
  compiler,
  overrides ? _: {},
  packages ? {},
  cabal2nixOptions ? "",
  profiling ? false,
}:
self: super:
let
  combined = import ./ghc-overrides.nix {
    inherit base overrides packages cabal2nixOptions profiling compiler;
    pkgs = self;
  };
in {
  haskell = super.haskell // {
    packages = super.haskell.packages // {
      ${compiler} = super.haskell.packages.${compiler}.override { overrides = combined; };
    };
  };
}
