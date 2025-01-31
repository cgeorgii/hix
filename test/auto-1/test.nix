{ pkgs }:
{
  test = builtins.toFile "auto-1-test" ''
    cd ./root
    nix flake update

    nix build .#root1
    output=$(result/bin/run)

    if [[ $output != 'string' ]]
    then
      fail "Running the main package produced the wrong output:\n$output"
    fi
  '';
}
