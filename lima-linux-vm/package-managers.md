# Linux Package Managers

Reference for the package managers used across the supported Lima VM templates. Each template maps to a specific distro and its native tooling.

| Template      | Distro        | Package Manager |
|---------------|---------------|-----------------|
| `alpine.yaml` | Alpine Linux  | `apk`           |
| `arch.yaml`   | Arch Linux    | `pacman`        |
| `debian.yaml` | Debian        | `apt`           |
| `fedora.yaml` | Fedora        | `dnf`           |
| `ubuntu.yaml` | Ubuntu        | `apt`           |

---

## apk — Alpine Linux

Alpine uses `apk` (Alpine Package Keeper). It is minimal, fast, and purpose-built for musl/busybox environments. Note that Alpine's package set is smaller than mainstream distros — some packages may be missing or named differently.

### Update package index

```sh
apk update
```

### Upgrade installed packages

```sh
apk upgrade
```

### Update index and upgrade in one step

```sh
apk update && apk upgrade
```

### Install a package

```sh
apk add <package>
```

### Install without caching to disk (useful in minimal/CI environments)

```sh
apk add --no-cache <package>
```

### Remove a package

```sh
apk del <package>
```

### Remove a package and its unused dependencies

```sh
apk del --purge <package>
```

### Search for a package

```sh
apk search <term>
```

### Show information about a package

```sh
apk info <package>
```

### List installed packages

```sh
apk info
```

### List files owned by a package

```sh
apk info -L <package>
```

### Find which package owns a file

```sh
apk info --who-owns /path/to/file
```

### Clean local cache

```sh
apk cache clean
```

---

## pacman — Arch Linux

Arch uses `pacman`. It manages both official repository packages and locally built packages. Most operations require `sudo`. The AUR (Arch User Repository) is not handled by `pacman` directly — AUR helpers like `yay` or `paru` wrap `pacman` and add AUR support.

### Sync package database

```sh
sudo pacman -Sy
```

### Full system upgrade (sync + upgrade — always do both together)

```sh
sudo pacman -Syu
```

> **Note:** Never run `-Sy` without `-u`. Partial upgrades are unsupported and can break your system.

### Install a package

```sh
sudo pacman -S <package>
```

### Install without confirmation

```sh
sudo pacman -S --noconfirm <package>
```

### Remove a package

```sh
sudo pacman -R <package>
```

### Remove a package along with its unused dependencies

```sh
sudo pacman -Rs <package>
```

### Remove a package, its dependencies, and config files

```sh
sudo pacman -Rns <package>
```

### Search the sync database (remote)

```sh
pacman -Ss <term>
```

### Search installed packages (local)

```sh
pacman -Qs <term>
```

### Show detailed information about a package (remote)

```sh
pacman -Si <package>
```

### Show detailed information about an installed package

```sh
pacman -Qi <package>
```

### List all installed packages

```sh
pacman -Q
```

### List explicitly installed packages (not pulled in as dependencies)

```sh
pacman -Qe
```

### List files owned by an installed package

```sh
pacman -Ql <package>
```

### Find which package owns a file

```sh
pacman -Qo /path/to/file
```

### Remove orphaned packages (installed as deps, no longer needed)

```sh
sudo pacman -Rns $(pacman -Qtdq)
```

### Clean package cache (keep last 3 versions)

```sh
sudo paccache -r
```

### Clean all cached packages not currently installed

```sh
sudo pacman -Sc
```

---

## apt — Debian & Ubuntu

Both Debian and Ubuntu use `apt` (Advanced Package Tool). `apt` is the modern, user-facing frontend. `apt-get` and `apt-cache` are the older plumbing equivalents — still valid and sometimes preferred in scripts for their stable output format.

### Update package index

```sh
sudo apt update
```

### Upgrade all installed packages

```sh
sudo apt upgrade
```

### Full upgrade (may add/remove packages to satisfy dependencies)

```sh
sudo apt full-upgrade
```

### Update index and upgrade in one step

```sh
sudo apt update && sudo apt upgrade
```

### Install a package

```sh
sudo apt install <package>
```

### Install without confirmation

```sh
sudo apt install -y <package>
```

### Remove a package (keep config files)

```sh
sudo apt remove <package>
```

### Remove a package and its config files

```sh
sudo apt purge <package>
```

### Remove unused automatically-installed dependencies

```sh
sudo apt autoremove
```

### Remove unused dependencies and purge their configs

```sh
sudo apt autoremove --purge
```

### Search for a package

```sh
apt search <term>
```

### Show information about a package

```sh
apt show <package>
```

### List installed packages

```sh
apt list --installed
```

### List upgradable packages

```sh
apt list --upgradable
```

### Find which package provides a file

```sh
dpkg -S /path/to/file
```

### List files owned by an installed package

```sh
dpkg -L <package>
```

### Install a local .deb file

```sh
sudo apt install ./package.deb
```

### Clean downloaded package cache

```sh
sudo apt clean
```

### Remove only outdated cached packages

```sh
sudo apt autoclean
```

---

## dnf — Fedora

Fedora uses `dnf` (Dandified YUM), the successor to `yum`. It handles dependency resolution, GPG verification, and module streams. `dnf5` is the default in Fedora 41+ with a faster C++ rewrite; the commands are compatible.

### Update package metadata

```sh
sudo dnf check-update
```

### Upgrade all installed packages

```sh
sudo dnf upgrade
```

### Install a package

```sh
sudo dnf install <package>
```

### Install without confirmation

```sh
sudo dnf install -y <package>
```

### Remove a package

```sh
sudo dnf remove <package>
```

### Remove unused dependencies

```sh
sudo dnf autoremove
```

### Search for a package

```sh
dnf search <term>
```

### Show information about a package

```sh
dnf info <package>
```

### List all installed packages

```sh
dnf list --installed
```

### List available packages

```sh
dnf list --available
```

### List upgradable packages

```sh
dnf list --upgrades
```

### Find which package provides a file or command

```sh
dnf provides <file-or-command>
```

### List files owned by an installed package

```sh
rpm -ql <package>
```

### Find which package owns a file

```sh
rpm -qf /path/to/file
```

### Install a local .rpm file

```sh
sudo dnf install ./package.rpm
```

### List installed package groups

```sh
dnf group list --installed
```

### Install a package group

```sh
sudo dnf group install "<Group Name>"
```

### Clean metadata and cache

```sh
sudo dnf clean all
```

### View transaction history

```sh
dnf history
```

### Undo a previous transaction (e.g., rollback a bad install)

```sh
sudo dnf history undo <id>
```

---

## Quick Comparison

| Operation              | apk                        | pacman                  | apt                        | dnf                        |
|------------------------|----------------------------|-------------------------|----------------------------|----------------------------|
| Update index           | `apk update`               | `pacman -Sy`            | `apt update`               | `dnf check-update`         |
| Upgrade all            | `apk upgrade`              | `pacman -Syu`           | `apt upgrade`              | `dnf upgrade`              |
| Install                | `apk add <pkg>`            | `pacman -S <pkg>`       | `apt install <pkg>`        | `dnf install <pkg>`        |
| Remove                 | `apk del <pkg>`            | `pacman -R <pkg>`       | `apt remove <pkg>`         | `dnf remove <pkg>`         |
| Remove + deps          | `apk del --purge <pkg>`    | `pacman -Rs <pkg>`      | `apt autoremove`           | `dnf autoremove`           |
| Search                 | `apk search <term>`        | `pacman -Ss <term>`     | `apt search <term>`        | `dnf search <term>`        |
| Package info           | `apk info <pkg>`           | `pacman -Si <pkg>`      | `apt show <pkg>`           | `dnf info <pkg>`           |
| List installed         | `apk info`                 | `pacman -Q`             | `apt list --installed`     | `dnf list --installed`     |
| Who owns file          | `apk info --who-owns <f>`  | `pacman -Qo <f>`        | `dpkg -S <f>`              | `rpm -qf <f>`              |
| List package files     | `apk info -L <pkg>`        | `pacman -Ql <pkg>`      | `dpkg -L <pkg>`            | `rpm -ql <pkg>`            |
| Clean cache            | `apk cache clean`          | `pacman -Sc`            | `apt clean`                | `dnf clean all`            |
