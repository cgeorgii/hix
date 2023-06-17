{ lib, }:
with lib;
let

  listOC = oc:
  if isDerivation oc
  then throw "not implemented"
  else if isList oc
  then oc
  else if oc ? multi
  then oc.multi
  else if oc ? single
  then [oc.single]
  else throw "Bad value for listOC: ${toString (attrNames oc)}";

  composeOC = cur: prev: {
    multi = listOC cur ++ listOC prev;
  };

  defaults = {
    pregen = {
      enable = false;
      src = null;
      impl = _: _: "no pregen";
    };
  };

  mkOC = conf: {
    single = defaults // conf;
    __functor = composeOC;
  };

  showSpec = spec: {
    inherit (spec) name desc meta;
  };

  show = specs: builtins.toJSON (if specs ? multi then map showSpec specs.multi else [(showSpec specs.single)]);

  collectOptions = specs: map (s: { ${s.name} = s.meta; }) (filter (s: s.type == "option") specs);

# ----------------------------------------------------------------------------------------------------------------------

  compile = specs: let

    check = acc: spec: specs:
    if spec.type == "decl"
    then acc // { decl = spec; }
    else if spec.type == "transform"
    then spin (acc // { trans = acc.trans ++ [spec]; }) specs
    else if spec.type == "option"
    then spin (acc // { options = acc.options // { ${s.name} = s.meta; }; }) specs
    else throw "invalid spec type '${spec.type}'";

    spin = acc: specs:
      if specs == []
      then acc
      else check acc (head specs) (tail specs);

  in spin { decl = null; trans = []; options = {}; } (listOC specs);

# ----------------------------------------------------------------------------------------------------------------------

  reifyComp = args: comp: let

    inherit (args) pkg;
    inherit (comp) decl;

    drv =
      if decl == null
      then args.super.${pkg} or null
      else decl.impl args comp.options;

    noDecl = throw ''
    The override for '${pkg}' does not declare a derivation and the default package set does not contain '${pkg}'!
    '';

    apply = drv: trans:
    trans.impl drv args comp.options;

    transformed = foldl apply drv comp.trans;

    final =
      if comp.trans == []
      then drv
      else
      if drv == null
      then noDecl
      else transformed;

  in final;

  reify = args: specs: reifyComp args (compile specs);

# ----------------------------------------------------------------------------------------------------------------------

  call = name: f: args: options: f (args // { inherit options; });

  finalDecl = specs:
  findFirst (a: a.type == "decl") null specs;

  runPregen = args: options: spec: let
  in if spec.pregen.enable then spec.pregen.impl spec.meta (args // { inherit options; }) else null;

  reifyPregen = args: specs: let
    norm = listOC specs;
    spec = finalDecl norm;
    options = collectOptions norm;
  in if spec == null then null else runPregen args options spec;

  transform = name: desc: meta: f: mkOC {
    inherit name desc meta;
    type = "transform";
    impl = drv: call name (args: f meta args drv);
  };

  decl = name: desc: meta: f: mkOC {
    inherit name desc meta;
    type = "decl";
    impl = call name (f meta);
  };

  option = name: desc: meta: mkOC {
    inherit name desc meta;
    type = "option";
    impl = meta;
  };

  pregen = src: impl: old: old // { single = old.single // {  pregen = { enable = true; inherit src impl; }; }; };

in {
  inherit transform decl option pregen listOC show compile reifyComp reify reifyPregen;
  transform_ = name: f: transform name name {} (_: _: f);
}
