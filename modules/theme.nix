outputs:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (builtins) attrNames isString pathExists;
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  inherit (lib.asserts) assertMsg;
  inherit (lib.attrsets)
    attrByPath
    filterAttrs
    mapAttrs
    mapAttrs'
    mapAttrsToList
    mergeAttrsList
    optionalAttrs
    ;
  inherit (lib.lists)
    findFirst
    flatten
    length
    unique
    ;
  inherit (lib.strings) concatLines;

  mkNullable =
    options:
    mkOption {
      type = types.nullOr (
        types.submodule {
          inherit options;
        }
      );
      default = null;
    };
in
{
  options.polymorph = {
    darkman = {
      enable = mkEnableOption "darkman support for polymorph theme module.";

      enableActivationScript = mkOption {
        type = types.bool;
        description = "Wether to automatically restart darkman on home activation";
        default = true;
      };

      dark = mkOption {
        type = types.str;
        apply =
          x:
          assert assertMsg (
            x == null || (config.polymorph.morph ? "${x}")
          ) "Could not find morph `${x}` for dark variant.";
          x;
        description = "Morph to apply on dark mode activation";
        default = "dark";
      };

      light = mkOption {
        type = types.str;
        apply =
          x:
          assert assertMsg (
            x == null || (config.polymorph.morph ? "${x}")
          ) "Could not find morph `${x}` for light variant.";
          x;
        description = "Morph to apply on dark mode activation";
        default = "light";
      };
    };

    theme = mkOption {
      type =
        with types;
        attrsOf (submodule {
          options = {
            cursorTheme = mkNullable {
              name = mkOption { type = str; };
              size = mkOption { type = ints.positive; };
            };

            font = mkNullable {
              name = mkOption { type = str; };
              size = mkOption { type = ints.positive; };
            };

            iconTheme = mkNullable {
              name = mkOption { type = str; };
            };

            theme = mkNullable {
              name = mkOption { type = str; };
            };

            packages = mkOption {
              type = listOf package;
              description = "Packages required for this variant (themes, icons, cursors, ...)";
              default = [ ];
            };
          };
        });
      description = "Theme properties to apply to morphs.";
      default = { };
    };
  };

  config =
    let
      cfg = config.polymorph;

      resolveCursor =
        let
          mkCursor =
            x:
            optionalAttrs (x.context.cursorTheme != null) (
              let
                package = findFirst (
                  y: pathExists "${y}/share/icons/${x.context.cursorTheme.name}"
                ) null x.settings.packages;
              in
              optionalAttrs (package != null) { "${x.context.cursorTheme.name}" = package; }
            );
        in
        x:
        (outputs.lib.resolveMorph cfg.morph
          {
            inherit (x) follows;
            cursor = mkCursor x;
          }
          (
            parent: current: {
              cursor = mkCursor parent // current.cursor;
            }
          )
        ).cursor;

      resolvePackages =
        x:
        unique (
          (outputs.lib.resolveMorph cfg.morph x (
            parent: current: {
              settings.packages =
                attrByPath [ "settings" "packages" ] [ ] parent
                ++ attrByPath [ "settings" "packages" ] [ ] current;
            }
          )).settings.packages
        );

      cursor = mergeAttrsList (mapAttrsToList (_: resolveCursor) cfg.morph);
      packages = unique (flatten (mapAttrsToList (_: resolvePackages) cfg.morph));
    in
    mkIf (cfg.enable || length (attrNames cfg.theme) > 0) {
      assertions = [
        {
          assertion = !config.gtk.enable;
          message = "polymorph theme module conflicts with gtk module";
        }
        {
          assertion = isNull config.home.pointerCursor;
          message = "polymorph theme module conflicts with home pointer cursor module";
        }
      ];

      polymorph = {
        file = [
          ".gtkrc-2.0"
          ".icons/default/index.theme"
          "${config.xdg.configHome}/gtk-3.0/settings.ini"
          "${config.xdg.configHome}/gtk-4.0/settings.ini"
          "${config.xdg.dataHome}/icons/default/index.theme"
        ];

        morph = mapAttrs (n: v: {
          extraScripts = pkgs.writeShellScript "polymorph-theme-${n}" (
            concatLines (
              (mapAttrsToList
                (
                  n: v:
                  ''${getExe pkgs.dconf} write /org/gnome/desktop/interface/${n} "${
                    if isString v then "'${v}'" else toString v
                  }"''
                )
                (
                  optionalAttrs (v.cursorTheme != null) {
                    cursor-size = v.cursorTheme.size;
                    cursor-theme = v.cursorTheme.name;
                  }
                  // optionalAttrs (v.font != null) {
                    font-name = "${v.font.name} ${toString v.font.size}";
                  }
                  // optionalAttrs (v.iconTheme != null) {
                    icon-theme = v.iconTheme.name;
                  }
                  // optionalAttrs (v.theme != null) {
                    gtk-theme = v.theme.name;
                  }
                )
              )
            )
          );

          context = filterAttrs (n: _: n != "packages") v;
          settings.packages = v.packages;
        }) cfg.theme;
      };

      home = {
        activation.restartDarkman = mkIf (with cfg.darkman; enable && enableActivationScript) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if [ -z "''${DRY_RUN:-}" ]; then
              if ${pkgs.systemd}/bin/systemctl --user is-active --quiet darkman.service; then
                echo "Restarting darkman...";
                ${pkgs.systemd}/bin/systemctl --user restart darkman.service
              fi
            fi
          ''
        );

        file =
          {
            ".gtkrc-2.0".text = ''
              {{- if ne .cursorTheme nil }}
              gtk-cursor-theme-name = "{{ .cursorTheme.name }}"
              gtk-cursor-theme-size = {{ .cursorTheme.size }}
              {{- end }}
              {{- if ne .font nil }}
              gtk-font-name = "{{ .font.name }} {{ .font.size }}"
              {{- end }}
              {{- if ne .iconTheme nil }}
              gtk-icon-theme-name = "{{ .iconTheme.name }}"
              {{- end }}
              {{- if ne .theme nil }}
              gtk-theme-name = "{{ .theme.name }}"
              {{- end }}
            '';

            ".icons/default/index.theme".text = ''
              {{- if ne .iconTheme nil }}
              [Icon Theme]
              Comment=Variant Cursor Theme
              Inherits={{ .cursorTheme.name }}
              Name=Default
              {{- end }}
            '';
          }
          // mapAttrs' (n: v: {
            name = ".icons/${n}";
            value.source = v;
          }) cursor;

        inherit packages;

        sessionVariables = {
          XCURSOR_PATH = "$XCURSOR_PATH\${XCURSOR_PATH:+:}${config.xdg.dataHome}/icons";
        };
      };

      xdg = {
        configFile =
          let
            settings = ''
              [Settings]
              {{- if ne .cursorTheme nil }}
              gtk-cursor-theme-name={{ .cursorTheme.name }}
              gtk-cursor-theme-size={{ .cursorTheme.size }}
              {{- end }}
              {{- if ne .font nil }}
              gtk-font-name={{ .font.name }} {{ .font.size }}
              {{- end }}
              {{- if ne .iconTheme nil }}
              gtk-icon-theme-name={{ .iconTheme.name }}
              {{- end }}
              {{- if ne .theme nil }}
              gtk-theme-name={{ .theme.name }}
              {{- end }}
            '';
          in
          {
            "gtk-3.0/settings.ini".text = settings;
            "gtk-4.0/settings.ini".text = settings;
          };

        dataFile =
          {
            "icons/default/index.theme".text = ''
              {{- if ne .iconTheme nil }}
              [Icon Theme]
              Comment=Variant Cursor Theme
              Inherits={{ .cursorTheme.name }}
              Name=Default
              {{- end }}
            '';
          }
          // mapAttrs' (n: v: {
            name = "icons/${n}";
            value.source = v;
          }) cursor
          // optionalAttrs cfg.darkman.enable {
            "dark-mode.d/polymorph-theme".source = cfg.activate.${cfg.darkman.dark};
            "light-mode.d/polymorph-theme".source = cfg.activate.${cfg.darkman.light};
          };
      };

      services = {
        xsettingsd.enable = true;
      };
    };
}
