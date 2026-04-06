# Dotfiles

Personal configuration files managed with [**doti**](https://github.com/volcmen/doti).

## Structure

```
home/           Mirrors $HOME — all config files live here
  .config/        ~/.config/ configs (hypr, kitty, fish, etc.)
  .bashrc         Root-level dotfiles
  .local/         ~/.local/ files
```

## Setup

```bash
git clone https://github.com/volcmen/configs.git ~/Development/personal/configs
```

Install [doti](https://github.com/volcmen/doti), then initialize:

```bash
cd ~/Development/personal/configs
doti init
```

See the [doti repo](https://github.com/volcmen/doti) for full documentation.
