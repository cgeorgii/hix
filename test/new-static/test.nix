{ pkgs }:
{
  test = builtins.toFile "new-static-test" ''
    mkdir root
    cd ./root
    nix run "path:$hix_dir#new" -- --name 'red-panda'
    nix run .#gen-cabal
    check_match 'nix run .#ghci -- -p red-panda -t main <<< :quit' 'passed 1 test' 'Running tests in generated project failed'
    check_match 'nix run' 'Hello red-panda' 'App in generated project failed'
  '';
}
