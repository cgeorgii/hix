{ config, lib, util, ... }:
{
  path ? ""
}:
with builtins;
with lib;
let

  inherit (config.internal) pkgs;

  mods = util.modulesRaw {} (util.modules ++ [{ system = config.system; } (import ../modules/system.nix)]);

  pathSegs = if path == "" then [] else splitString "." path;

  unlines = concatStringsSep "\n";

  indentLine = l: "  " + l;

  indent = map indentLine;

  concatMapAttrs = f: a: concatLists (mapAttrsToList f a);

  color = n: t: "\\e[" + toString n + "m" + t + "\\e[0m";

  colors = {
    attrset = "33";
    submodule = "32";
    option = "34";
  };

  desc = n: t: color n t + ": ";

  kvWith = col: name: value:
  [(desc col name + value)];

  kv =
  kvWith colors.option;

  sub = n:
  kv n "";

  zoom = segs: root: let
    get = p: f: config: let
      inner =
        if hasAttr p config
        then f config.${p}
        else throw ''
        No such config option: ${path}
        ${p} is not present in ${concatStringsSep ", " (attrNames config)}
        '';
    in
    { ${p} = inner; };
    spin = p: f: get p f;
  in foldr spin id segs root;

  listOrEmpty = f: cs: n:
  if cs == []
  then kv n "[]"
  else sub n ++ indent (map f cs);

  attrsOrEmpty = f: cs: n:
  if cs == {}
  then kv n "{}"
  else sub n ++ indent (concatMapAttrs f cs);

  renderPackage = p:
    if p ? pname
    then "${p.pname}-${p.version}"
    else p.name or "package";

  ghcDesc = g:
    if hasAttr "hix-name" g
    then " (Overrides for ${g.hix-name})"
    else "";

  renderers = {
    bool = b: if b then "true" else "false";
    str = s: ''"${s}"'';
    path = toString;
    separatedString = s: ''"${s}"'';
    unsignedInt16 = toString;
    package = renderPackage;
    nixpkgs = n: "nixpkgs source (${n.rev or "?"})";
    pkgs = _: "nixpkgs attrset";
    overlay = _: "overlay";
    cabal-overrides = _: "Cabal overrides";
    ghc = g: "Packages for GHC ${g.ghc.version}${ghcDesc g}";
  };

  renderGeneric = tpe: _:
  "<${tpe}>";

  stringifyOptionValue = c: tpe:
  (renderers.${tpe} or (renderGeneric tpe)) c;

  stringifySubmodule = c: n: a:
  [(desc colors.submodule n)] ++
  indent (stringifyModule c (a.getSubOptions []));

  stringifyElem = tpe: c:
  color 35 "* " + stringifyOptionValue c tpe;

  stringifyListOf = cs: n: a:
  listOrEmpty (stringifyElem a.nestedTypes.elemType.name) cs n;

  stringifyAttrOf = tpe: n: c:
  kv n (stringifyOptionValue c tpe);

  stringifyAttrsOf = cs: n: a: let
    tpe = a.nestedTypes.elemType;
  in
  attrsOrEmpty (n: c: stringifyOption c n tpe) cs n;

  stringifyAny = n: a:
    if isDerivation a
    then "<derivation>"
    else if isAttrs a
    then stringifyAttrsStrict a n null
    else if isFunction a
    then kv n "<function>"
    else kv n (toString a)
    ;

  stringifyAttrsStrict = cs: n: _:
  attrsOrEmpty stringifyAny cs n;

  stringifyEither = c: n: a:
  if a.nestedTypes.left.check c
  then stringifyOption c n a.nestedTypes.left
  else stringifyOption c n a.nestedTypes.right;

  nestedHandlers = {
    submodule = stringifySubmodule;
    listOf = stringifyListOf;
    attrsOf = stringifyAttrsOf;
    lazyAttrsOf = stringifyAttrsOf;
    attrs = stringifyAttrsStrict;
    either = stringifyEither;
  };

  stringifyOption = c: n: tpe:
  if hasAttr tpe.name nestedHandlers
  then nestedHandlers.${tpe.name} c n tpe
  else kv n (stringifyOptionValue c tpe.name);

  stringifyAttrs = c: n: a:
  [(desc colors.attrset n)] ++
  (if isDerivation a
  then ["<derivation>"]
  else indent (stringifyModule c a));

  stringifyValue = c: n: a:
  if n == "_module" || n == "internal" || n == "code" || n == "runner" || n == "devGhc"
  then []
  else if isAttrs a
  then
  if (a._type or "nothing") == "option"
  then stringifyOption c n a.type
  else stringifyAttrs c n a
  else stringifyAny n a;

  stringifyModule = c: m: concatMapAttrs (n: a: optionals (hasAttr n c) (stringifyValue c.${n} n a)) m;

  stringifyRoot = pkgs.writeText "project-options" (unlines (stringifyModule (zoom pathSegs mods.config) mods.options));

  palette = "Colors: ${concatStringsSep " | " (mapAttrsToList (flip color) colors)}";

in pkgs.writeScript "show-config" ''
  #!${pkgs.zsh}/bin/zsh
  print "${palette}"
  print ""
  while IFS='\n' read -r line; do echo -e $line; done <  ${stringifyRoot}
''
