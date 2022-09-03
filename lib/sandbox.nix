{
  lib,
  bubblewrap,
  writeShellScriptBin,
  writeText,
  coreutils,
  bashInteractive,
}: emacs: {
  name ? "emacs-sandboxed",
  userEmacsDirectory ? null,
  extraBubblewrapOptions ? [],
  emacsArguments ? [],
  initFile ? null,
}: let
  load = file: "(load \"${file}\" nil t)\n";

  initEl =
    if initFile != null
    then initFile
    else
      writeText "init.el" (
        ''          ;; -*- lexical-binding: t; no-byte-compile: t; -*-
                  (setq custom-file (locate-user-emacs-file "custom.el"))
                  (when (file-exists-p custom-file)
                    (load custom-file nil t))

                  (setq use-package-ensure-function #'ignore)
        ''
        + lib.concatMapStrings load emacs.initFiles
      );

  emacsDirectoryOpts =
    if userEmacsDirectory == null
    then "--dir $HOME/.emacs.d"
    # user-emacs-directory may contain references to paths inside itself, so
    # it is better to create a symlink rather than to bind-mount it.
    else ''
      --bind ${userEmacsDirectory} ${userEmacsDirectory} \
      --symlink ${userEmacsDirectory} $HOME/.emacs.d \
    '';

  userEmacsDirectory' =
    if userEmacsDirectory == null
    then "$HOME/.emacs.d"
    else userEmacsDirectory;

  wrap = open: end: body: open + body + end;

  # lib.escapeShellArgs quotes each argument with single quotes. It is safe, but
  # I want to allow use of environment variables passed as arguments.
  quoteShellArgs = lib.concatMapStringsSep " " (wrap "\"" "\"");
in
  lib.extendDerivation true
  {
    passthru.exePath = "/bin/${name}";
  }
  (writeShellScriptBin name ''
    # If the first argument is an existing path, bind-mount it
    if [[ $# -gt 0 && -e "$1" ]]
    then
      f="$1"
      opts="--bind $f $f"
    else
      opts=""
    fi

    for var in XAUTHORITY
    do
      if [[ -v "$var" ]]
      then
        value="$(\$$var)"
        opts+=" --ro-bind \"$value\" \"$value\""
      fi
    done

    if [[ -v DISPLAY ]]
    then
      opts+=" --setenv DISPLAY $DISPLAY"
      if [[ $DISPLAY =~ ^:([[:digit:]]+) ]]
      then
        sock=/tmp/.X11-unix/X''${BASH_REMATCH[1]}
        opts+=" --ro-bind $sock $sock"
      fi
    fi

    set -x
    ( exec ${bubblewrap}/bin/bwrap \
        --dir "$HOME" \
        --proc /proc \
        --dev /dev \
        --dev-bind-try /dev/snd /dev/snd \
        --dev-bind-try /dev/video0 /dev/video0 \
        --dev-bind-try /dev/video1 /dev/video1 \
        --dev-bind /dev/dri /dev/dri \
        --ro-bind /nix /nix \
        --ro-bind /etc /etc \
        --ro-bind-try /bin /bin \
        --ro-bind-try /usr/bin/env /usr/bin/env \
        --bind-try "$HOME/.cache/fontconfig" "$HOME/.cache/fontconfig" \
        --tmpfs /run \
        --tmpfs /tmp \
        --ro-bind "$SHELL" "$SHELL" \
        --ro-bind-try "$HOME/.config/zsh/.zshenv" "$HOME/.config/zsh/.zshenv" \
        --ro-bind-try "$HOME/.config/zsh/.zshrc" "$HOME/.config/zsh/.zshrc" \
        --ro-bind-try "$HOME/.config/zsh/plugins" "$HOME/.config/zsh/plugins" \
        --ro-bind-try "$HOME/.zshenv" "$HOME/.zshenv" \
        --new-session \
        --die-with-parent \
        --unshare-all \
        --setenv PATH ${lib.makeBinPath [
      coreutils
      bashInteractive
    ]} \
        ${quoteShellArgs extraBubblewrapOptions} \
        ${emacsDirectoryOpts} \
        --ro-bind ${initEl} ${userEmacsDirectory'}/init.el \
        $opts \
        ${emacs}/bin/emacs ${quoteShellArgs emacsArguments} "$@"
      )
  '')
