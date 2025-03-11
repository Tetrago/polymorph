# polymorph

polymorph is a Nix Home Manager module that uses [gomplate](https://github.com/hairyhenderson/gomplate) to allow dynamic runtime templating for home files.    **...wait what?**

## Rationale

polymorph allows for changing configuration files and executing scripts at runtime in a dynamic and easy-to-use way that Nix just is not built for (and rightfully so). This streamlines the process for making any configuration changes that need to occur while the system is running and not at build time. Notably, for run-time theme changing to allow swapping out style values in configuration files at any point in time.

And since we're using a template engine, we can continue to use preexisting modules that take in string values instead of re-inventing the wheel for existing configuration files.

## Usage

In `flake.nix`:

```nix
{
    inputs = {
        polymorph = "https://github.com/tetrago/polymorph.git";
    };
}
```

In your home manager module:

```nix
{ polymorph, ... }:

{
    imports = [ polymorph.homeManagerModules.default ];
}
```

### Basic

polymorph divides up configuration sets into "morphs" that provide settings to the template engine (as well as any additional scripts needed to be executed).

```nix
polymorph.morph = {
    enable = true;

    dark.settings = {
        background = "#000000";
    };

    light.settings = {
        background = "#ffffff"; # Ahh! my eyes!
    };
};
```

Now, we can apply our configuration values to any existing strings. For example, in Hyprlock:

```nix
programs.hyprlock.settings = {
    background = [
        {
            color = "rgb({{ .background }})";
        }
    ];
};

# While it'd be great to evaluate all files, that would cause recursion issues.
polymorph.file = ["${config.xdg.configHome}/hypr/hyprlock.conf"];
# Make sure to reference the EXACT string used in the `home.file` entry.
```

We can also implement limited inheritance to use fallback values. This can be exceedingly in setting up dark and light mode theme variants.

```nix
polymorph.morph = {
    default.settings.text = "#222222";

    dark.follows = "default";
    light.follows = "default";
};
```

Finally, we can activate these morphs as we please.

```nix
polymorph.default = "dark"; # Will be applied during home activation.

home.file."enableDarkMode".source = config.polymorph.activate.dark;
```

### Theme

Included within the flake is a `theme` Home Manager module that is set-up to enable cursor and GTK theme switching using the morph system. Import the module:

```nix
{ polymorph, ... }:

{
    imports = [ polymorph.homeManagerModules.theme ];
}
```

Then setup your themes.

```nix
polymorph = {
    morph = {
        dark.follows = "common";
        light.follows = "common";
    };

    theme = {
        common = {
            font = {
                name = "Ubuntu Nerd Font";
                size = 11;
            };

            packages = with pkgs; [
                colloid-gtk-theme
                nerd-fonts.ubuntu
                phinger-cursors
                colloid-icon-theme
            ];
        };

        dark = {
            cursorTheme = {
                name = "phinger-cursors-dark";
                size = 24;
            };

            iconTheme.name = "Colloid-Dark";
            theme.name = "Colloid-Dark-Catppuccin";
        };

        light = {
            cursorTheme = {
                name = "phinger-cursors-light";
                size = 24;
            };

            iconTheme.name = "Colloid-Light";
            theme.name = "Colloid-Light-Catppuccin";
        };
    };
};
```

[darkman](https://gitlab.com/WhyNotHugo/darkman) support is included.

```nix
polymorph.darkman = {
    enable = true;
    dark = "dark"; # These are set as the default morphs to use
    light = "light";
};
```
