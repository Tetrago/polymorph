outputs:
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
  inherit (lib.strings) concatLines optionalString;
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

            context = mkOption {
              type = attrsOf anything;
              description = "Values to be provided to the template engine.";
              default = { };
            };

            settings = mkOption {
              type = attrs;
              description = "Extra data to be added to morphs.";
              default = { };
            };

            extraScripts = mkOption {
              type = coercedTo anything (x: [ x ]) (coercedTo (listOf anything) (map toString) (listOf str));
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

      resolveMorph =
        x:
        outputs.lib.resolveMorph cfg.morph x (
          parent: current: {
            context = recursiveUpdate parent.context current.context;
            extraScripts = parent.extraScripts ++ current.extraScripts;
          }
        );

      files = attrNames (filterAttrs (_: v: v.enable) cfg.file);
      morphs = mapAttrs (_: resolveMorph) cfg.morph;

      mkSubstitution =
        n: v:
        pkgs.stdenvNoCC.mkDerivation rec {
          name = "polymorph-${n}";

          dontUnpack = true;

          src = pkgs.writeText "${name}.json" (toJSON v.context);

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
                ${optionalString (file.executable != null && file.executable) "chmod +x ./${file.target}"}
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
                cp -f ${mkSubstitution n v}/${path} $HOME/${path}
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
