{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (builtins) attrNames toJSON;
  inherit (lib)
    genAttrs
    mkEnableOption
    mkForce
    mkIf
    mkMerge
    mkOption
    recursiveUpdate
    types
    ;
  inherit (lib.asserts) assertMsg;
  inherit (lib.attrsets) filterAttrs mapAttrs;
  inherit (lib.lists) any;
  inherit (lib.strings) concatLines;
in
{
  options.polymorph = {
    enable = mkEnableOption "polymorph.";

    default = mkOption {
      type = with types; nullOr str;
      apply =
        x:
        assert assertMsg (
          x == null || config.polymorph.morph ? "${x}"
        ) ''Polymoprh cannot apply non-existent morph "${x}" as default'';
        x;
      description = "The name of the morph to apply during home activation.";
      default = null;
    };

    morph = mkOption {
      type =
        with types;
        attrsOf (submodule {
          options = {
            follows = mkOption {
              type = nullOr str;
              description = "A parent morph to inherit properties from. Will be overriden by local changes.";
              default = null;
            };

            settings = mkOption {
              type = attrsOf anything;
              description = "Values to be provided to the template engine.";
              default = { };
            };

            extraScripts = mkOption {
              type = coercedTo str (x: [ x ]) (listOf str);
              description = "Extra scripts to execute during morph activation.";
              default = [ ];
            };
          };
        });
      description = "Available morphs to activate with `config.polymorph.activate.\${name}`";
      default = { };
    };

    file = mkOption {
      type =
        with types;
        coercedTo (listOf str)
          (
            x:
            genAttrs x (_: {
              enable = true;
            })
          )
          (
            attrsOf (submodule {
              options = {
                enable = mkOption {
                  type = bool;
                  default = true;
                };
              };
            })
          );
      description = "The files to be managed by polymorph instead of home manager.";
      default = { };
    };

    activate = mkOption {
      type = types.attrsOf types.path;
      internal = true;
    };
  };

  config =
    let
      cfg = config.polymorph;

      resolveMorphRecursive =
        history: x:
        if x.follows == null then
          x
        else
          let
            parent =
              assert assertMsg (cfg.morph ? "${x.follows}") ''Could not follow morph "${x.follows}"'';
              assert assertMsg (any (
                y: y == x.follows
              ) history) ''Recursion detected in morph follow to "${x.follows}"'';
              cfg.morph.${x.follows};
          in
          resolveMorphRecursive (history ++ [ x.follows ]) {
            follows = parent.follows;
            settings = recursiveUpdate parent.settings x.settings;
            extraScripts = parent.extraScripts ++ x.extraScripts;
          };

      resolveMorph = resolveMorphRecursive [ ];

      files = attrNames (filterAttrs (_: v: v.enable) cfg.file);
      morphs = mapAttrs (_: resolveMorph) cfg.morph;

      mkSettings =
        n: v:
        pkgs.stdenvNoCC.mkDerivation rec {
          name = "polymorph-${n}";

          dontUnpack = true;

          src = pkgs.writeText "${name}.json" (toJSON v.settings);

          nativeBuildInputs = with pkgs; [
            gomplate
          ];

          buildPhase = concatLines (
            map (
              x:
              let
                file = config.home.file.${x};
              in
              ''
                mkdir -p ./$(dirname ${file.target})
                gomplate -c .=$src -f ${file.source} -o ./${file.target}
              ''
            ) files
          );

          installPhase = concatLines (
            map (
              x:
              let
                path = config.home.file.${x}.target;
              in
              ''
                mkdir -p $out/$(dirname ${path})
                cp ./${path} $out/${path}
              ''
            ) files
          );
        };

      mkActivateScript =
        n: v:
        pkgs.writeShellScript "polymorph-${n}-activate" (
          concatLines (
            (map (
              x:
              let
                path = config.home.file.${x}.target;
              in
              ''
                mkdir -p $HOME/$(dirname ${path})
                cp -f ${mkSettings n v}/${path} $HOME/${path}
              ''
            ) files)
            ++ v.extraScripts
          )
        );
    in
    mkIf cfg.enable {
      home = {
        activation.polymorph = mkIf (cfg.default != null) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] "run ${config.polymorph.activate.${cfg.default}}"
        );

        file = mkMerge (map (x: { ${x}.enable = mkForce false; }) files);
      };

      polymorph.activate = mapAttrs mkActivateScript morphs;
    };
}
