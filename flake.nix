{
  inputs = { };

  outputs =
    { ... }:
    {
      homeManagerModules.default = import ./nix/hm-module.nix;
    };
}
