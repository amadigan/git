#!/bin/zsh
# SPDX-License-Identifier: CC0-1.0

# localpkg package script for git
lp_pkg[name]="git"
lp_pkg[repo]="${GITHUB_REPOSITORY}" # evaluated at build time
lp_pkg[package]="git.tar.xz"
lp_pkg[release]="${RELEASE_ID}"
lp_pkg[hashalg]="sha256"

if [[ -n "${lp_pkg[release]}" && -f "dist/${lp_pkg[package]}" ]]; then
	lp_log "Including package hash"
	lp_pkg[package_hash]="$(lp_hash_file "${lp_pkg[hashalg]}" "dist/${lp_pkg[package]}")"
else
	lp_log "No package hash available release=${lp_pkg[release]} file=dist/${lp_pkg[package]}"
fi

lp_postinstall() {
	builtin mkdir -p "${LOCALPKG_PREFIX}/etc/profile.d"
	lp_installed_files+=("etc/profile.d/git.sh")

	# dynamically generate a one-line script setting GIT_EXEC_PATH correctly
	# run in sub-shell to avoid polluting the environment
	(
		typeset -gx GIT_EXEC_PATH="${LOCALPKG_PREFIX}/libexec/git-core"
		typeset -p GIT_EXEC_PATH > "${LOCALPKG_PREFIX}/etc/profile.d/git.sh"
		command "${LOCALPKG_PREFIX}/bin/git" config --global credential.helper osxkeychain
	)
}
