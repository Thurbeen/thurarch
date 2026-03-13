export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

zstyle ':omz:update' mode auto      # update automatically without asking

# Bitwarden SSH agent — only if socket exists
if [[ -S "$HOME/.bitwarden-ssh-agent.sock" ]]; then
  export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
fi

# Open directories in Dolphin
if command -v dolphin &>/dev/null; then
  open()(
    dolphin --new-window "$@" 1>/dev/null 2>/dev/null &
  )
fi
