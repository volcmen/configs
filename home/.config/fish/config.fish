if status is-interactive
    # Commands to run in interactive sessions can go here

    starship init fish | source
    zoxide init fish | source

    # Only auto-start zellij inside kitty sessions.
    if set -q KITTY_PID
        set -gx ZELLIJ_AUTO_EXIT true
        eval (zellij setup --generate-auto-start fish | string collect)
    end

    function y
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        command yazi $argv --cwd-file="$tmp"
        if read -z cwd <"$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
            builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
    end

    # eza
    alias ls 'eza --icons'
    alias tree 'eza --tree --icons'

    alias cat 'bat --plain'
    # alias grep rg
    alias cd z
    alias find fd

    # Shorthands
    alias nv nvim
    alias lg lazygit
    alias clauded "claude --dangerously-skip-permissions"
end

# No greeting
set -g fish_greeting
