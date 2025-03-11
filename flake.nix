{
  description = "A run-time configuration template substitution module for Nix Home Manager";

  inputs = { };

  outputs =
    { self, ... }:
    {
      homeManagerModules = import ./modules self.outputs;
      lib = import ./lib;
    };
}
