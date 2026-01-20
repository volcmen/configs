# My Dotfiles

Welcome to my personal configuration files repository. These dotfiles are managed using [chezmoi](https://www.chezmoi.io/), a powerful and secure dotfile manager.

## Contents

This repository contains configurations

## Installation

### 1. Install `chezmoi`

If you haven't already, install `chezmoi` using your package manager.

**Arch Linux:**
```bash
sudo pacman -S chezmoi
```

### 2. Initialize and Apply

To apply these dotfiles to your system, run:

```bash
chezmoi init --apply https://github.com/volcmen/configs.git

```
If you have already cloned this repo manually:
```bash
chezmoi init
chezmoi apply
```

## Usage

Here are some common `chezmoi` commands to manage your dotfiles:

### Apply changes
Pull the latest changes from the repo and apply them to your home directory:
```bash
chezmoi update
```

### Edit a config file
To edit a file (e.g., `~/.config/kitty/kitty.conf`), don't edit it directly. Instead, use:
```bash
chezmoi edit ~/.config/kitty/kitty.conf
```
This opens the file in the source directory. When you save and exit, `chezmoi` will verify the changes.

### Apply specific changes
After editing, apply the changes to your actual home directory:
```bash
chezmoi apply
```

### Add a new file
To start tracking a new file:
```bash
chezmoi add ~/.bashrc
```

### See differences
Check what has changed between your home directory and the source state:
```bash
chezmoi diff
```

### Open a shell in the source directory
```bash
chezmoi cd
```

## Documentation

For more advanced usage, check out the [chezmoi user guide](https://www.chezmoi.io/user-guide/).
