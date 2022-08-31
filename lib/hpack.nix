{ pkgs, ghc, verbose, paths, packages, }:
with builtins;
let

  packageCall = n: p:
  if hasAttr n packages
  then "synthetic ${n} ${p} ${toFile "package.yaml" (toJSON packages.${n})}"
  else "regular ${n} ${p}";

  packageCalls =
    pkgs.lib.mapAttrsToList packageCall paths;

in pkgs.writeScript "hpack.zsh" ''
  #!${pkgs.zsh}/bin/zsh
  setopt err_exit no_unset

  base=''${1-''$PWD}

  run()
  {
    ${ghc.hpack}/bin/hpack ${if verbose then "" else "1>/dev/null"}
  }

  regular()
  {
    local name=$1 rel=$2
    dir="$base/$rel"
    pushd $dir
    ${if verbose then ''echo ">>> $dir"'' else ""}
    if [[ -f package.yaml ]]
    then
      run
    else
      echo "no package.yaml in $dir"
    fi
    popd
  }

  synthetic()
  {
    local name=$1 rel=$2 file=$3
    dir="$base/$rel"
    pushd $dir
    ${if verbose then ''echo ">>> $dir"'' else ""}
    remove="$dir/package.yaml"
    cp $file package.yaml
    error() {
      ${if verbose then "cat $file" else ""}
      rm -f $remove
    }
    trap error ZERR
    trap "rm -f $remove" EXIT
    run
    popd
  }

  ${concatStringsSep "\n" packageCalls}
''
