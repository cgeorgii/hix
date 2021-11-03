# About

A set of tools for developing on a Haskell project with Nix build.
Provides out-of-the-box setup for package overrides, `ghcid`, `haskell-language-server`, [thax], and `cabal upload`.

**Warning** This is still under construction, subject to breaking changes, unstable, and very specific to the author's
workflow.

# Basic usage

The simplest possible flake looks like this:

```nix
{
  description = "Spaceship";
  inputs.hix.url = github:tek/hix;
  outputs = { hix, ... }: hix.flake { base = ./.; packages = { spaceship = ./.; }; };
}
```

This will configure a single Cabal library at the root of the project, to be built with:

```
nix build .#spaceship
```

# Configuration

The function `hix.flake` combines multiple steps:

* `hix.haskell` creates a `nixpkgs` overlay with Cabal overrides for local packages and dependencies
* `hix.tools` provides helpers for `ghcid`, HLS, `cabal upload`, `ctags` and `hpack`
* `hix.flakeOutputs` assembles an `outputs.<system>` set according to flake standards
* `hix.compatChecks` creates several additional copies of the GHC overlay for different versions
* `hix.systems` iterates over the target systems (default is `["x86_64-linux"]`)

These functions share some parameters, so they are listed independently.

## Basics

|Name|Default|Description|
|---|---|---|
|`system`||Passed to `nixpkgs`, usually provided by `flake-utils`, which is called by `hix.systems`.|
|`base`||Path to the project root, should be specified as `./.`.|
|`packages`||Local Cabal [packages](#packages).|
|`compiler`|`"ghc8107"`|The attribute name of the GHC package set to use for development.|
|`overrides`|`{}`|[Dependency Overrides](#dependency-overrides).|
|`cabal2nixOptions`|`""`|Passed to `callCabal2nix` for project packages.|
|`profiling`|`true`|Whether to enable library profiling for dependencies.|
|`nixpkgs`|`inputs.nixpkgs`|`nixpkgs` used for development. `inputs.nixpkgs` refers to `hix`'s flake inputs, which can also be overridden with: `inputs.hix.inputs.nixpkgs.url = github:nixos/nixpkgs`|
|`nixpkgsFunc`|`import nixpkgs`|Function variant of the previous parameter. The default imports the specified `nixpkgs` argument.|
|`overlays`|`[]`|Additional overlays passed verbatim to `nixpkgs`.|
|`compat`|`true`|Create flake checks for other GHC versions.|
|`compatVersions`|`["901" "8107" "884"]`|GHC versions for which compat checks should be created.|

## Packages

The `packages` parameter is a set mapping project names to file system paths.
The simplest configuration, for a project with one Cabal file at the root, is:

```nix
packages = {
  spaceship = ./.;
}
```

For multiple packages:

```nix
packages = {
  spaceship-core = ./packages/core;
  spaceship-api = ./packages/api;
}
```

This configuration is used by `hix.haskell` to create `cabal2nix` derivations for the packages, by the `ghcid`
helpers to configure the include paths, and by the `cabal upload` scripts.

## GHC Compatibility Checks

If the `compat` argument is `true`, the flake will have additional outputs named like `compat-901-spaceship-core`.
These derivations don't share the same overrides as the main (`dev`) project.
This allows testing the project with the default packages from the hackage snapshot that nixpkgs uses for this version.
Each of these versions can have their own overrides, as described in the next section.


# Dependency Overrides

The `overrides` parameter allows the project's dependencies to be customized.
Its canonical form is a set mapping GHC versions to a list of special override functions, with an extra attribute for
the development dependencies and one that is used for _all_ package sets:

```nix
overrides = {
  all = ...;
  dev = ...;
  ghc901 = ...;
  ghc8107 = ...;
};
```

If, instead of a set, a list of override functions, or a single function, is given, they are treated as if they had been
specified as `{ all = overrides; }`.

Override functions have similar semantics to regular nixpkgs extension functions (`self: super: {...}`), but they take
additional parameters and can create not only derivations, but also custom dependency specifications.
The general shape is:

```nix
overrides = {
  ghc901 = { self, super, hsLib, jailbreak, ... }: {
    name1 = hsLib.doJailbreak super.name1;
    name2 = jailbreak;
  };
};
```

The function's parameter is a set containing the usual `self` and `super` as well as several other tools, including
built-ins, like `nixpkgs.lib`, and a set of composable depspec combinators, like `jailbreak`.

Here the override for `name1` jailbreaks the package in the usual way, while `name2` uses the special combinator for the
same purpose.
Composing those combinators is simple:

```nix
overrides = {
  ghc901 = { profiling, jailbreak, hackage, ... }: {
    aeson = profiling (jailbreak (hackage "2.0.0.0" "shaxxxxx"));
    http-client = profiling jailbreak;
  };
};
```

In the first case, the `hackage` combinator _sets_ the derivation to the one using version `2.0.0.0` from Hackage (using
the attribute name as the package), while the second case uses `super.http-client`.
The combinators can be understood as creating a pipeline that is given the `super` derivation as the default, with each
stage able to change it.

## Built-in Depspec Combinators

All of these are in the attribute set passed to an override function.

|Name|Derivation|
|---|---|
|`hackage`| Takes a version and SHA hash, sets the derivation to be that version pulled directly from Hackage.|
|`source.root`| Creates a derivation by running `cabal2nix` on a directory.|
|`source.sub`| Like `source.root`, but takes an additional subdirectory.|
|`source.package`| Like `source.sub`, but prepends `packages/` to the subdirectory.|
|`drv`| Sets a verbatim derivation.|
|`keep`| Sets the derivation to `null`, effectively falling back to `super`.|

|Name|Transformation|
|---|---|
|`unbreak`| Allow packages marked as `broken`.|
|`jailbreak`| Disable Cabal dependency bounds.|
|`configure`| Add a Cabal configure flag.|
|`configures`| Add multiple Cabal configure flags. |
|`override`| Pass a function to `overrideCabal`.|
|`minimal`| Disable Haddock, benchmarks and tests, and unbreak.|
|`profiling`| Force profiling.|

|Name|Option|
|---|---|
|`option`| Takes a key and an arbitrary value. Used to set options for derivation combinators.|
|`noHpack`| Sets an option with key `cabal2nix` to `--no-hpack`, which will be read by `source.*` and passed to|
  `cabal2nix.`

## Creating Depspec Combinators

When evaluating the depspec, it is passed this state:

```nix
{
  drv = null;
  transform = id;
  options = {};
}
```

If `drv` is `null` in the result, it is replaced with `super.package`.
Then, the `transform` function is applied to it, which is composed from all the combinators like `jailbreak`.
`options` is an arbitrary set that can be used to modify other combinators.

A depspec combinator can be created with:

```nix
withHaddock =
  hix.util.spec.create ({ self, super, final, prev, pkg, hsLib, lib }: {
    transform = drv: hsLib.doHaddock (prev.transform drv);
  })
```

`self` and `super` reference the regular Haskell package sets, while `final` and `prev` reference the depspec.
`self` and `final` point to the state after all overrides have been applied, while `super` and `prev` contain the state
that the previous combinator produced.
`pkg` contains the package name, while `hsLib` and `lib` are `nixpkgs.haskell.lib` and `nixpkgs.lib`.

There is a shorter way to construct this combinator:

```nix
withHaddock =
  hix.util.spec.transform ({ hsLib, ... }: hsLib.doHaddock);
```

## Transitive Overrides

Overrides can be inherited from dependency flakes:

```nix
{
  inputs.dep1.url = github:me/dep1;

  outputs = { hix, dep1, ... }:
  hix.flake {
    base = ./.;
    paackages = ...;
    overrides = ...;
    deps = [dep1];
  };
}
```

The overrides defined in the flakes given in the `deps` argument will be folded into the current project's overrides,
with local overrides having higher precedence.
**Note** that this may lead to unexpected results if the dependencies don't use the same nixpkgs version.

# Tools

## `hpack`

These commands run `hpack` in each directory in `packages` (the first variant suppresses output):

```
nix run .#hpack
nix run .#hpack-verbose
```

It is possible to store the config files in a separate directory, configured by the `hpackDir` attribute to `flake`
(defaulting to `ops/hpack`).
If the file `${hpackDir}/<project-name>.yaml` exists, it will be copied to the project directory and removed after
running `hpack`.

Additionally, a shared directory, for use in `hpack` files with the `<<: !include shared/file.yaml` directive, may be
configured with the `hpackShared` parameter (defaulting to `shared`).
If the directory `${hpackDir}/${hpackShared}` exists, it will be linked to the project directory as well.

## `devShell` and `ghcid`

The project's local packages with all their dependencies are made available in the `devShell`, which can be entered with
`nix develop`.
In there, `cabal` commands work as expected.
Additionally, `ghcid` may be run with the proper configuration so that it watches all source files.

`ghcid` and `ghci` have several configuration options:

* `ghci.basicArgs`, default `["-Werror" "-Wall" "-Wredundant-constraints" "-Wunused-type-patterns" "-Widentities"]`:
  Passed directly to `ghci`.
* `ghci.extraArgs`, default `[]`: Passed directly to `ghci`.
* `ghci.options_ghc`, default `null`: If non-null, passed to `ghci` as `-optF`.
* `ghcid.commands`, default `_: {}`: A function taking `pkgs` and `ghc`, producing an attrset of attrsets.
  Each of those sets configure a [command](#commands).
* `ghcid.prelude`, default `true`: Whether to work around some issues with custom `Prelude`s.
* `ghcid.runConfig`, default `{}`: Extra configuration for all `ghcid` apps, like extra search paths.
* `ghcid.testConfig`, default `{}`: Extra configuration for the test command.

### Commands

```nix
{
  outputs = { hix, ... }:
  hix.flake {
    ghcid.commands = pkgs: {
      dev-api = {
        script = ''
          :load Spaceship.Api.Dev
          :import Spaceship.Api.Dev (runDevApi)
        '';
        test = "rundevApi";
        env.DEV_PORT = "8000";
      };
    };
  };
}
```

The `ghcid.commands` attrset is translated into flake apps that run a haskell function in `ghcid`:

```
nix run .#dev-api
```

## `haskell-language-server`

HLS can be started with:

```
nix develop -c haskell-language-server
```

## `hasktags`

To generate `ctags` for all dependencies and project packages:

```
nix run .#tags [<tags-file>]
```

`tags-file` defaults to `.tags`.

## `cabal upload`

To upload package candidates or publish to Hackage:

```
nix run .#candidates
nix run .#release
```

If the arg `versionFile` is given, the script will substitute the `version:` line in that `hpack` file after asking for
the next version.

[thax]: https://github.com/tek/thax
