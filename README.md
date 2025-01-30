# git for macOS

This project provides up to date builds of git for macOS. The build is based on the latest stable release of git from the official git repository.

Features:
- osxkeychain support
- Universal binaries for Apple Silicon and Intel architectures
- No external dependencies
- Signed binaries
- Signed and notarized installer package
- Fully automated GitHub Actions build and release process builds directly from the official git repository

## Packages

Two packages are provided, a .pkg installer and a .tar.xz archive. The installer package requires admin privileges and
installs git to `/usr/local/bin`. The archive can be extracted to any location and used without installation.

The .tar.xz archive contains the same files as isntalled by the package installer. The package installer can be replicated
by running the follow command on the archive (`git.tar.xz`):

```
sudo bsdtar -C /usr/local --strip-components 1 --exclude '*LICENSE'* --exclude '*README*' -xf git.tar.xz
```

git can also be installed to your local home folder using the installation script

```
curl -sL https://github.com/railyard-vm/git/releases/latest/download/git.localpkg | zsh -s
```

This extracts the archive to `~/.local` and ensures that `~/.local/bin` is in your PATH. It also sets `GIT_EXEC_PATH` appropriately for 
bash and zsh shells. 

## License

To avoid confusion, the GPL-2.0 license file from git is included in the root of this repository. The actual code that makes this build work is published
into the public domain. You can do whatever you want with it.	
