{
  description = "hix test project";

  inputs.hix.url = path:HIX;

  outputs = { hix, ... }: hix.lib.flake ({lib, ...}: {
    packages.root = {
      src = ./.;
      library.enable = true;
      cabal.dependencies = ["aeson"];
    };
    compat.enable = false;
    overrides = {hackage, ...}: {
      aeson = hackage "2.1.2.1" "1f1f6h2r60ghz4p1ddi6wnq6z3i07j60sgm77hx2rvmncz4vizp0";
    };
    gen-overrides.enable = true;
  });
}
