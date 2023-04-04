{global, util, ...}:
{name, config, lib, ...}:
with lib;
let

  envConfig = config;

  serviceModule = import ./service.nix { inherit lib global; };

  envServiceModule = import ./env-service.nix { inherit lib global; };

  ghcModule = import ./ghc.nix { inherit global util; };

  vmLib = import ../lib/vm.nix { inherit (global) pkgs; };

  waitSeconds = toString config.wait;

  waitScript = ''
  running=0
  echo ">>> Waiting ${waitSeconds} seconds for VM to boot..." >&2
  timeout=$(( $SECONDS + ${waitSeconds} ))
  while (( $SECONDS < $timeout ))
  do
    pong=$(${global.pkgs.socat}/bin/socat -T 1 - TCP:localhost:${toString (config.basePort + 1)} <<< 'ping' 2>&1)
    if [[ $pong == 'running' ]]
    then
      running=1
      break
    else
      sleep 0.1
    fi
  done
  if [[ $running == 0 ]]
  then
    echo ">>> VM wasn't ready after ${waitSeconds} seconds." >&2
    exit 1
  fi
  '';

  buildInputs = let
    isNotLocal = p: !(p ? pname && elem p.pname global.internal.packageNames);
    bInputs = p: p.buildInputs ++ p.propagatedBuildInputs;
    localDeps = g: builtins.filter isNotLocal (concatMap bInputs (map (p: g.${p}) global.internal.packageNames));
  in
  config.buildInputs ++
  optional config.hls.enable config.hls.package ++
  optional config.ghcid.enable config.ghcid.package ++
  [(config.ghc.ghc.ghcWithPackages (ghc: optionals config.localDeps (localDeps ghc) ++ map (n: ghc.${n}) config.haskellPackages))]
  ;

  exportShellVars = vars:
  optionalString (!(util.empty vars)) "export ${toShellVars config.env}";

  preamble = ''
    quitting=0
    quit() {
      if [[ $quitting == 0 ]]
      then
        quitting=1
        if [[ -n ''${1-} ]]
        then
          echo ">>> Terminated by signal $1" >&2
        fi
        ${config.exit-pre}
        ${optionalString config.vm.enable config.vm.exit}
        ${config.exit}
        # kill zombie GHCs
        ${global.pkgs.procps}/bin/pkill -9 -x -P 1 ghc || true
      fi
      if [[ -n ''${1-} ]]
      then
        exit 1
      fi
    }
    trap "quit INT" INT
    trap "quit TERM" TERM
    trap "quit KILL" KILL
    trap quit EXIT
    ${exportShellVars config.env}
    export PATH="${makeBinPath buildInputs}:$PATH"
    export env_args
    ${config.setup-pre}
    ${optionalString config.vm.enable config.vm.setup}
    ${optionalString (config.vm.enable && config.wait > 0) waitScript}
    ${config.setup}
  '';

  runner = global.pkgs.writeScript "env-${config.name}-runner.bash" ''
  #!${global.pkgs.bashInteractive}/bin/bash
   ${config.code}
   $@
  '';

  setupVm = ''
  ${vmLib.ensure config.vm}
  '';

  exitVm = ''
  ${vmLib.kill config.vm}
  '';

  servicePort = { guest, host }:
  { host.port = config.basePort + host; guest.port = guest; };

  servicePorts = ports: {
    virtualisation.vmVariant.virtualisation.forwardPorts = map servicePort ports;
  };

  vmConfig = {
    virtualisation.vmVariant.virtualisation = {
      diskImage = config.vm.image;
      diskSize = 4096;
    };
  };

  nixosDefaults = servicePorts [{ guest = 22; host = 22; }] // {
    services.openssh = {
      enable = true;
      permitRootLogin = "yes";
    };
    users.mutableUsers = true;
    users.users.root.password = "";
    networking.firewall.enable = false;
    documentation.nixos.enable = false;
    system.stateVersion = "22.05";
  };

  serviceConfig = service:
  [service.nixos-base service.nixos (servicePorts service.ports)];

  combinedConfig =
    [vmConfig] ++
    optional config.defaults nixosDefaults ++
    concatMap (s: serviceConfig s.resolve) (attrValues config.internal.resolvedServices)
    ;

  resolveServiceModule = {name, config, ...}: let
    service = envConfig.services.${name};
  in {
    options = with types; {
      name = mkOption {
        description = mdDoc "";
        type = str;
        default = name;
      };

      resolve = mkOption {
        description = mdDoc "";
        type = submoduleWith {
          modules = optionals (name != "‹name›") ([
            serviceModule
            { inherit (service) enable; }
          ] ++
          optional (hasAttr name global.services) global.services.${name} ++
          optionals (hasAttr name global.internal.services) [
            global.internal.services.${name}
            service.config
          ]);
        };
        default = {};
      };
    };
  };

  ghc = config.ghc.ghc;

  extraPackages = genAttrs global.output.extraPackages (n: ghc.${n});

  localPackages = genAttrs global.internal.packageNames (n: ghc.${n} // { inherit ghc; });

in {
  options = with types; {

    enable = mkEnableOption (mdDoc "this env");

    name = mkOption {
      description = mdDoc "Env name";
      type = str;
      default = name;
    };

    services = mkOption {
      description = mdDoc "Services for this env";
      type = attrsOf (submodule envServiceModule);
      default = {};
    };

    env = mkOption {
      description = mdDoc "Environment variables";
      type = attrsOf (either int str);
      default = {};
    };

    ghc = mkOption {
      description = mdDoc "";
      type = submodule ghcModule;
      default = {};
    };

    overrides = mkOption {
      type = util.types.cabalOverrides;
      default = [];
      description = mdDoc ''
      TODO
      '';
    };

    buildInputs = mkOption {
      description = mdDoc "";
      type = listOf package;
      default = [];
    };

    haskellPackages = mkOption {
      description = mdDoc "";
      type = listOf str;
      default = [];
    };

    localDeps = mkOption {
      description = mdDoc "Add dependencies of local packages.";
      type = bool;
      default = true;
    };

    setup-pre = mkOption {
      description = mdDoc "Commands to run before the service VM has started.";
      type = str;
      default = "";
    };

    setup = mkOption {
      description = mdDoc "Commands to run after the service VM has started.";
      type = str;
      default = "";
    };

    exit-pre = mkOption {
      description = mdDoc "Command to run before the service VM is shut down.";
      type = str;
      default = "";
    };

    exit = mkOption {
      description = mdDoc "Command to run when the env exits.";
      type = str;
      default = "";
    };

    code = mkOption {
      description = mdDoc "";
      type = str;
      default = preamble;
    };

    shell = mkOption {
      description = mdDoc ''
      The shell derivation for this environment, starting the service VM in the `shellHook`.

      ::: {.note}
      If this shell is used with `nix develop -c`, the exit hook will never be called and the VM will not be shut down.
      Use a command instead for this purpose.
      :::
      '';
      type = package;
      default = global.pkgs.stdenv.mkDerivation {
        inherit (config) name buildInputs;
        shellHook = config.code;
      };
    };

    runner = mkOption {
      description = mdDoc "";
      type = path;
      default = runner;
    };

    basePort = mkOption {
      description = mdDoc "The number as a base for ports in this env's VM, like ssh getting `basePort + 22`.";
      type = port;
      default = 20000;
    };

    defaults = mkOption {
      description = mdDoc "Whether to use the common NixOS options for VMs.";
      type = bool;
      default = true;
    };

    wait = mkOption {
      description =
        mdDoc "Wait for the VM to complete startup within the given number of seconds. 0 disables the feature.";
      type = int;
      default = 30;
    };

    ghcid = {
      enable = mkEnableOption (mdDoc "GHCid for this env") // { default = true; };

      package = mkOption {
        description = mdDoc "The package for GHCid, defaulting to the one from the env's GHC without overrides.";
        type = package;
        default = config.ghc.vanillaGhc.ghcid;
      };
    };

    hls = {
      enable = mkEnableOption (mdDoc "HLS for this env") // { default = true; };

      package = mkOption {
        description = mdDoc "The package for HLS, defaulting to the one from the env's GHC without overrides.";
        type = package;
        default = config.ghc.vanillaGhc.haskell-language-server;
      };
    };

    hide = mkOption {
      description = mdDoc "Skip this env for user-facing actions, like command exposition in `apps`.";
      type = bool;
      default = false;
    };

    derivations = mkOption {
      # description = mdDoc ''
      # The derivations for the local Cabal packages using this env's GHC, as well as the [](#opt-extraPackages).
      # '';
      description = mdDoc ''
      The derivations for the local Cabal packages using this env's GHC, as well as the TODO
      '';
      type = lazyAttrsOf package;
      default = localPackages // extraPackages;
    };

    vm = {

      enable = mkEnableOption (mdDoc "the service VM for this env");

      name = mkOption {
        description = mdDoc "Name of the VM, used in the directory housing the image file.";
        type = str;
        default = config.name;
      };

      dir = mkOption {
        description = mdDoc "";
        type = str;
        default = "/tmp/hix-vm/$USER/${config.vm.name}";
      };

      pidfile = mkOption {
        type = str;
        description = mdDoc "The file storing the qemu process' process ID.";
        default = "${config.vm.dir}/vm.pid";
      };

      image = mkOption {
        type = str;
        description = mdDoc "The path to the image file.";
        default = "${config.vm.dir}/vm.qcow2";
      };

      headless = mkOption {
        description = mdDoc ''
        VMs are run without a graphical connection to their console.
        For debugging purposes, this option can be disabled to show the window.
        '';
        type = bool;
        default = true;
      };

      setup = mkOption {
        description = mdDoc "Commands for starting the VM.";
        type = str;
      };

      exit = mkOption {
        description = mdDoc "Commands for shutting down the VM.";
        type = str;
      };

      derivation = mkOption {
        description = mdDoc "The VM derivation";
        type = path;
      };

    };

    internal = {

      overridesInherited = mkOption {
        type = util.types.cabalOverrides;
        description = mdDoc "The inherited overrides used for this env, like local packages and global overrides.";
        default = global.internal.overridesLocal;
      };

      # TODO simplify this
      resolvedServices = mkOption {
        description = mdDoc "";
        type = attrsOf (submodule resolveServiceModule);
        default = mapAttrs (_: _: {}) config.services;
      };

    };

  };

  config = {

    enable = mkDefault true;

    services.hix-internal-env-wait.enable = config.wait > 0;

    ghc.overrides = mkDefault (util.concatOverrides [config.internal.overridesInherited config.overrides]);

    vm = {

      enable = mkDefault (length (attrNames config.services) > (if config.wait > 0 then 1 else 0));

      derivation = mkDefault (
        let nixosArgs = {
          system = "x86_64-linux";
          modules = combinedConfig;
        };
        in (lib.nixosSystem nixosArgs).config.system.build.vm
        );

        setup = mkDefault setupVm;
        exit = mkDefault exitVm;

      };

  };
}
