{
  description = "hix test project";
  inputs.hix.url = "github:tek/hix?ref=0.5.6";
  outputs = {hix, ...}: hix.lib.auto ({config, ...}: {
    envs = {
      one.env = { number = 1; };
      two.env = { number = 2; };
      three.env = { number = 3; };
    };

    packages.root = {
      src = ./.;
      executable.env = config.envs.two;
    };

    commands.number = {
      env = config.envs.one;
      command = ''
      echo $number
      '';
      component = true;
    };

  });
}
