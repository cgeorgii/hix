{config, lib, util}:
with lib;
let
  pkgs = config.pkgs;
  overridesFile = config.gen-overrides.file;

  spec = import ./deps/spec.nix { inherit (pkgs) lib; };
  deps = import ./deps/default.nix { inherit (config) pkgs; };

  # TODO run for all envs
  ghc = config.envs.dev.ghc.vanillaGhc;

  decl = pkg: specs: let
    data = spec.reifyPregen { inherit pkgs pkg; self = ghc; super = ghc; } specs;
  in optionalAttrs (data != null) { ${pkg} = data; };

  decls = concatMapAttrs decl (deps.normalize config.envs.dev.ghc.overrides ghc ghc);

  drvAttr = pkg: dump: "  ${pkg} = ${toString dump};";

  file = pkgs.writeText "overrides.nix" (util.unlines (["{"] ++ mapAttrsToList drvAttr decls ++ ["}"]));

in config.pkgs.writeScript "gen-overrides" ''
  #!${pkgs.bashInteractive}/bin/bash
  mkdir -p ${dirOf overridesFile}
  cp ${file} ${overridesFile}
''
