{ config, lib, ... }:
with builtins;
with lib;
let

  hpackFile = conf:
  toFile "package.yaml" (toJSON (removeAttrs conf ["passthru"]));

  withCabal = pkgs: conf: name: src: let
    cabal = "${name}.cabal";
  in pkgs.runCommand "${name}-gen-cabal" {} ''
  cp -r ${src} $out
  chmod u+w $out
  cd $out
  rm -f package.yaml
  cp ${hpackFile conf} package.yaml
  if [[ -e ${cabal} ]]
  then
    chmod u+w ${cabal}
  fi
  ${config.internal.basicGhc.hpack}/bin/hpack --force
  rm -f package.yaml
  '';

  depPkg = n:
  if isAttrs n
  then n.name
  else head (splitString " " n);

  simpleCabalDrvWith = conf: { pkgs, self, hsLib, ... }: pname: pkg:
  let
    attr = n:
    if hasAttr n conf
    then conf.${n}
    else throw "The Cabal config for '${pname}' is missing the mandatory attribute '${n}'.";

    dep = n:
    if hasAttr n self
    then self.${n}
    else throw "The Cabal config for '${pname}' has a dependency on the nonexistent package '${n}'.";

    depspec = n:
    if n == pname
    then []
    else [(dep (depPkg n))];

    deps = c: concatMap depspec (c.dependencies or []);

  in self.callPackage ({mkDerivation}: mkDerivation ({
    inherit pname;
    src = withCabal pkgs conf pname pkg.src;
    version = attr "version";
    license = attr "license";
    libraryHaskellDepends = deps (conf.library or {});
    executableHaskellDepends = concatMap deps (attrValues (conf.executables or {}));
    testHaskellDepends = concatMap deps (attrValues (conf.tests or {}));
  } // conf.passthru or {})) {};

  simpleCabalDrv = api: pname:
  simpleCabalDrvWith config.hpack.internal.packages.${pname} api pname;

in {
  inherit withCabal simpleCabalDrv;
}
