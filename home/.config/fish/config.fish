# Keep managed user tools ahead of system fallbacks without duplicating PATH
# entries in nested fish sessions (for example, kitty -> zellij -> fish).
set --export BUN_INSTALL "$HOME/.bun"
fish_add_path --path --move --prepend \
    /opt/homebrew/bin \
    "$HOME/.local/bin" \
    "$BUN_INSTALL/bin" \
    "$HOME/.opencode/bin" \
    "$HOME/.lmstudio/bin"

if status is-interactive
    if command -q starship
        starship init fish | source
    end

    if command -q zoxide
        zoxide init fish | source
    end

    # Only auto-start zellij inside kitty sessions.
    if set -q KITTY_PID; and command -q zellij
        set -gx ZELLIJ_AUTO_EXIT true
        eval (zellij setup --generate-auto-start fish | string collect)
    end

    function y
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        command yazi $argv --cwd-file="$tmp"
        if read -z cwd <"$tmp"; and test "$cwd" != "$PWD"; and test -d "$cwd"
            builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
    end

    # Modern replacements.
    alias ls "eza --icons"
    alias tree "eza --tree --icons"
    alias cat "bat --plain"
    alias cd z
    alias find fd

    # Shorthands.
    alias nv nvim
    alias lg lazygit
    alias clauded "claude --agent controller --model fable --effort medium --dangerously-skip-permissions"
end

# No greeting.
set -g fish_greeting
