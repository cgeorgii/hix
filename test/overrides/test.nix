{ pkgs }: with pkgs.lib; let
  inherit (pkgs) lib;

  ghc = pkgs.haskellPackages;
  self = ghc;
  super = ghc;

  spec = import ../../lib/deps/spec.nix { inherit lib; };
  api = import ../../lib/deps/api2.nix { inherit pkgs self super; };
  dep = import ../../lib/deps/default.nix { inherit pkgs; };

  single = api.hackage "2.1.2.1" "1f1f6h2r60ghz4p1ddi6wnq6z3i07j60sgm77hx2rvmncz4vizp0";
  multi = api.notest single;
  pkg = "aeson";

  args = { inherit pkgs self super pkg; };

  finalSingle = spec.reify args (spec.listOC single);
  finalMulti = spec.reify args (spec.listOC multi);

in {
  test = builtins.toFile "overrides-test" ''
    cd ./root
    nix flake update

    check_eq '${finalSingle.version}' '2.1.2.1' 'Wrong version for aeson (single)'
    check_eq '${finalMulti.version}' '2.1.2.1' 'Wrong version for aeson (multi)'
    check_eq '${builtins.toJSON finalSingle.doCheck}' 'true' 'tests not enabled for single'
    check_eq '${builtins.toJSON finalMulti.doCheck}' 'false' 'tests not disabled for multi'

    error_target="The option 'gen-overrides.enable' is set, but the file 'ops/overrides.nix' doesn't exist."
    check_match_err 'nix eval .#legacyPackages.${pkgs.system}.ghc.aeson.version' $error_target 'Wrong error before gen-overrides'
    nix run .#gen-overrides
    check 'ls ops' 'overrides.nix' 'No overrides.nix in ops/'

    check 'nix eval .#legacyPackages.${pkgs.system}.ghc.aeson.version' '"2.1.2.1"' 'aeson version wrong after gen-overrides'

    sed -i 's/2\.1/5.8/' flake.nix
    error_target="Please run 'nix run .#gen-overrides' again."
    check_match_err 'nix eval .#legacyPackages.${pkgs.system}.ghc.aeson.version' $error_target 'Wrong error before gen-overrides'
  '';
}
