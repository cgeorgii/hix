{
  description = "hix test project";

  inputs.hix.url = path:HIX;

  outputs = { hix, ... }:
  hix.lib.flake ({ config, ... }: {
    ifd = false;
    packages.root = {
      src = ./.;
      library.enable = true;
      executable.enable = true;
    };
    envs.dev.ghc.compiler = "ghc92";
    envs.dev.ghc.crossPkgs = config.envs.dev.ghc.pkgs.pkgsCross.musl64;
    overrides = { hsLib, self, ... }: {
      static = hsLib.justStaticExecutables self.root;
    };
    output.extraPackages = ["static"];
  });
}
