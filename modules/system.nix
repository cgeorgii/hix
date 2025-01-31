{ lib, config, ... }:
with lib;
let

in {
  options = with types; {

    system = mkOption {
      type = str;
    };

    systemOutputs = mkOption {
      type = unspecified;
      readOnly = true;
    };

  };

  config.systemOutputs = config.output.final;
}
