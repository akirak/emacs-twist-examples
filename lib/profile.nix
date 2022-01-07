{ emacsTwist
, lib
, cmake
, gcc
, libvterm-neovim
, inventories
# Profile-specific
, emacsPackage
, initFiles
, lockDir
}:
with builtins;
(emacsTwist {
  inherit initFiles;
  inherit emacsPackage;
  inherit lockDir;
  inherit inventories;
  inputOverrides = import ./inputs.nix { inherit lib; };
}).overrideScope' (_: super: {
  elispPackages = super.elispPackages.overrideScope' (eself: esuper: {
    slime = esuper.slime.overrideAttrs (old: {
      preBuild = ''
        mkdir lib
        cp hyperspec.el lib
      '';
    });

    vterm = esuper.vterm.overrideAttrs (old: {
      # Based on the configuration in nixpkgs available at the following URL:
      # https://github.com/NixOS/nixpkgs/blob/af21d41260846fb9c9840a75e310e56dfe97d6a3/pkgs/applications/editors/emacs/elisp-packages/melpa-packages.nix#L483
      nativeBuildInputs = [ cmake gcc ];
      buildInputs = old.buildInputs ++ [ libvterm-neovim ];
      cmakeFlags = [
        "-DEMACS_SOURCE=${super.emacs.src}"
      ];
      preBuild = ''
      cmake
      make
      install -m444 -t . ../*.so
      install -m600 -t . ../*.el
      cp -r -t . ../etc
      rm -rf {CMake*,build,*.c,*.h,Makefile,*.cmake}
    '';
    });

    pdf-tools = esuper.pdf-tools.overrideAttrs (old: {
      preBuild = ''
        mkdir build
      '';
    });
  });
})
