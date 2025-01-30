#!/bin/zsh
# SPDX-License-Identifier: CC0-1.0

typeset -g current_cmd=""
trap 'current_cmd="${ZSH_DEBUG_CMD}"' DEBUG
trap 'printf "Error: %s\n" "${current_cmd}"' ERR

typeset -g mods=(zsh/param/private zsh/files zsh/stat)
zmodload "${(@)mods}"

typeset -g cpus="$(sysctl -n hw.ncpu)"
typeset -g project_root="${ZSH_SCRIPT:a:h}"

source "${project_root}/build-props.sh"
[[ -f "${project_root}/build-props-local.sh" ]] && source "${project_root}/build-props-local.sh"

typeset -g git_ref="${GIT_VERSION:-HEAD}"
typeset -g git_dir="${project_root}/src/git.git"
typeset -g macos_version="${MACOS_VERSION:-13}"
typeset -g build_universal="${BUILD_UNIVERSAL:-0}"
typeset -g build_tar="${BUILD_TAR:-1}"
typeset -g build_pkg="${BUILD_PKG:-1}"
typeset -g build_man="${BUILD_MAN:-1}"
typeset -g build_version=""
typeset -gA build_tasks=()
typeset -g log_time_fmt='%D{%Y-%m-%dT%H:%M:%SZ}'

setopt err_return typeset_silent unset


log_error() {
	printf '%s ERROR %s\n' "${(%)log_time_fmt}" "${*}" >&2
	fail
}

log_info() {
	printf '%s INFO %s\n' "${(%)log_time_fmt}" "${*}" >&2
	return 0
}

prepare_tools() {
	if ! command -v brew &>/dev/null && [[ -x /opt/homebrew/bin/brew ]]; then
		eval "$(/opt/homebrew/bin/brew shellenv)" || log_error "Failed to initialize Homebrew"
	fi

	private -a tools=(asciidoc xmlto autoconf)
	private -a install=()

	for tool in "${tools[@]}"; do
		if ! command -v "${tool}" &>/dev/null; then
			install+=("${tool}")
		fi
	done

	if [[ ${#install[@]} -gt 0 ]]; then
		if [[ -n "${CI}" ]]; then
			command brew install "${(@)install}"
		else
			log_error "The following tools are required: ${(@)install}"
		fi
	fi
}

prepare_git() {
	if [[ ! -d "${git_dir}" ]]; then
		builtin mkdir -p "${git_dir:a:h}"
		git init --bare "${git_dir}"
		git -C "${git_dir}" remote add origin "${GIT_REPO}"
	fi

	git -C "${git_dir}" rev-parse --quiet --verify "${git_ref}^{object}" &>/dev/null ||\
	git -C "${git_dir}" rev-parse --quiet --verify "remotes/origin/${git_ref}^{object}" &>/dev/null ||\
	git -C "${git_dir}" fetch --tags origin "${git_ref}"
}

typeset -g intel_root="${project_root}/build/git-intel"

build_intel() {
	log_info "Building Intel version"
	export LDFLAGS="-arch x86_64 -mmacosx-version-min=${macos_version}"
	export CFLAGS="-arch x86_64 -mmacosx-version-min=${macos_version}"
	builtin rm -rf "${project_root}/src/intel" "${intel_root}"
	builtin mkdir -p "${project_root}/src/intel" "${intel_root}"

	git -C "${git_dir}" archive "${git_ref}" | bsdtar -xC "${project_root}/src/intel"
	builtin ln -nf "${project_root}/git.mak" "${project_root}/src/intel/config.mak"
	cd "${project_root}/src/intel"
	make configure
	./configure --prefix=/usr/local --with-gitconfig="/usr/local/etc/gitconfig"

	log_info "Building git for Intel"
	make DESTDIR="${intel_root}" -j ${cpus} all strip install 2>&1
	builtin mv "${intel_root}"/usr/local/* "${intel_root}"
	builtin rm -rf "${intel_root}/usr"
	cd contrib/credential/osxkeychain

	log_info "Building git-credential-osxkeychain for Intel"
	make 2>&1
	strip -x git-credential-osxkeychain 2>&1
	builtin ln -nf git-credential-osxkeychain "${intel_root}/libexec/git-core/" 2>&1
	log_info "Intel build complete"
	return 0
}

build_git() {
	log_info "Building git for ${CPUTYPE}"
	export LD_FLAGS="-mmacosx-version-min=${macos_version}"
	export CFLAGS="-mmacosx-version-min=${macos_version}"

	private dest="${project_root}/build/git"

	builtin rm -rf "${project_root}/src/git"
	builtin mkdir -p "${project_root}/src/git"

	log_info "Building in ${project_root}/src/git"
	git -C "${git_dir}" archive "${git_ref}" | bsdtar -xC "${project_root}/src/git"
	builtin ln -nf "${project_root}/git.mak" "${project_root}/src/git/config.mak"
	cd "${project_root}/src/git"

	builtin rm -rf "${dest}"
	builtin mkdir -p "${dest}"

	make configure 2>&1
	./configure --prefix=/usr/local --with-gitconfig="/usr/local/etc/gitconfig"

	log_info "Building git for ${CPUTYPE} to ${project_root}/build/git"
	make DESTDIR="${dest}" -j ${cpus} all strip install 2>&1
	log_info builtin mv "${dest}"/usr/local/* "${dest}"
	builtin mv "${dest}"/usr/local/* "${dest}" || log_error "Failed to move files"
	builtin rm -rf "${dest}/usr"
	cd contrib/credential/osxkeychain

	log_info "Building git-credential-osxkeychain for ${CPUTYPE}"
	make
	strip -x git-credential-osxkeychain
	builtin ln -nf git-credential-osxkeychain "${dest}/libexec/git-core/"
	log_info "git build complete"
}

build_man() {
	if command -v brew &>/dev/null; then
		typeset -gx XML_CATALOG_FILES="$(brew --prefix)/etc/xml/catalog"
		log_info "Using Homebrew XML catalog: ${XML_CATALOG_FILES}"
	else
		log_info "Homebrew is not installed"
	fi
	builtin rm -rf "${project_root}/src/man"
	builtin mkdir -p "${project_root}/src/man"
	command git -C "${git_dir}" archive "${git_ref}" | bsdtar -xC "${project_root}/src/man"
	builtin ln -nf "${project_root}/git.mak" "${project_root}/src/man/config.mak"
	cd "${project_root}/src/man"
	private dest="${project_root}/build/git-man"
	builtin rm -rf "${dest}"
	builtin mkdir -p "${dest}"
	make -j 8 man 2>&1
	make prefix="" DESTDIR="${dest}" install-man 2>&1
	builtin mkdir -p "${project_root}/build/git/share"
	builtin mv "${dest}/share/man" "${project_root}/build/git/share/"
	log_info "Man pages built"
	return 0
}

main() {
	trap 'cleanup 1' TERM INT
	typeset -gx BUILD_PARENT=$$
	private exit_code=0
	build || exit_code=$?
	cleanup $exit_code
}

cleanup() {
	if [[ ${#build_tasks} -ne 0 ]]; then
		kill ${(@v)build_tasks} &>/dev/null || true
		wait ${(@v)build_tasks} &>/dev/null || true
	fi

	if [[ "${1}" -eq 0 ]]; then
		log_info "Build completed successfully"
		exit 0
	else
		log_info "Build failed"
		exit "${1}"
	fi
}

fail() {
	builtin kill "${BUILD_PARENT}"
	trap - ERR
	return 1
}

run_async() {
	private bg_task
	if [[ -n "${2}" ]]; then
		( "${1}" > "${2}" ) &
	else
		( "${1}" ) &
	fi
	bg_task=$!
	build_tasks[${1}]="${bg_task}"
	log_info "Started ${1} with PID ${bg_task}"
}

wait_async() {
	private -a wait_tasks=()

	for job in "${@}"; do
		[[ ! -v build_tasks[${job}] ]] && log_error "Invalid job: ${job}"
		wait_tasks+=("${build_tasks[${job}]}")
		unset "build_tasks[${job}]"
	done

	wait ${(@)wait_tasks}
}

build() {
	cd "${project_root}"
	log_info "Fetching ${git_ref} from ${GIT_REPO}"
	run_async prepare_git
	prepare_tools
	wait_async prepare_git || log_error "Failed to fetch git"

	builtin mkdir -p "${project_root}/build"

	private git_ref_param="${git_ref}"

	git_ref="$(git -C "${git_dir}" rev-parse --quiet --verify "${git_ref_param}")" ||\
	git_ref="$(git -C "${git_dir}" rev-parse --quiet --verify "remotes/origin/${git_ref_param}")" ||\
	log_error "Unable to find ${git_ref_param} in ${GIT_REPO}"

	private tags="$(git -C "${git_dir}" tag --points-at "${git_ref}")"
	build_version=""

	if [[ -n "${tags}" ]]; then
		log_info "Building from "${GIT_REPO}" ${git_ref} (${tags})"
	else
		build_version="$(git -C "${git_dir}" describe --tags --always "${git_ref}")"
		log_info "Building from "${GIT_REPO}" ${git_ref}" untagged version "${build_version}"
	fi

	(( build_man )) && run_async build_man "${project_root}/build/build-man.log"
	(( build_universal )) && run_async build_intel "${project_root}/build/build-intel.log"

	( build_git ) > "${project_root}/build/build-git.log"
	if [[ -z "${build_version}" ]]; then
		source "${project_root}/src/git/GIT-VERSION-FILE"
		build_version="${GIT_VERSION}"
	fi

	log_info "built git-${build_version}"

	cd "${project_root}"

	if (( build_universal )); then
		log_info "Waiting for Intel version to complete..."
		wait_async build_intel || log_error "Failed to build Intel version"
	fi
	
	# key is the file path, value is colon-separated list of hard links to the file
	local -A package_files=()

	prepare_pkg

	if (( build_man )); then
		log_info "Waiting for manpages to complete..."
		wait_async build_man || log_error "Failed to build man pages"
	fi

	(( build_tar )) && run_async build_tar
	(( build_pkg )) && build_pkg

	if (( build_tar )); then
		log_info "Waiting for tarball to complete..."
		wait_async build_tar || log_error "Failed to build tarball"
	fi
}

prepare_pkg() {
	cd "${project_root}/build/git"

	private -a files=(**/*(N))
	private file target

	builtin mkdir -p etc
	builtin ln -nf "${project_root}/gitconfig" etc/gitconfig

	private -a bins=()

	for file in "${(@)files}"; do
		if [[ -L "${file}" ]]; then
			target="$(builtin stat +link "${file}")"
			target="${file:h}/${target}"
			target="${target:a}"
			target="${target#${PWD}/}"
			if [[ -n "${package_files[${target}]}" ]]; then
				package_files[${target}]="${file}:${package_files[${target}]}"
			else
				package_files[${target}]="${file}"
			fi
			builtin rm "${file}"
			continue
		fi
		
		if [[ ! -v package_files[${file}] ]]; then
			package_files[${file}]=""
		fi

		if [[ -x "${file}" && "$(file --brief --mime-type "${file}")" == "application/x-mach-binary" ]] ; then
			bins+=("${file}")
			if (( build_universal )); then
				log_info "Creating universal binary: ${file}"
				lipo -create -output "${file}.lipo" "${file}" "${intel_root}/${file}"
				builtin mv "${file}.lipo" "${file}"
			fi
		fi
	done
	
	if [[ -n "${CODE_SIGNING_IDENTITY}" ]]; then
		log_info "Signing binaries: ${(@)bins}"
		codesign --options runtime --force --sign "${CODE_SIGNING_IDENTITY}" "${(@)bins}"
	else
		log_info Binaries: "${(@)bins}"
	fi
}

build_tar() {
	log_info "Building tarball"
	builtin mkdir -p "${project_root}/build/tar"
	cd "${project_root}/build/tar"

	builtin ln -nf "${project_root}/src/git/COPYING" LICENSE

	private file linkstr
	private -a links

	for file linkstr in "${(@kv)package_files}"; do
		[[ -z "${linkstr}" ]] && continue

		# split linkstr on colon
		links+=(${(s/:/)linkstr})

		for link in "${(@)links}"; do
			builtin mkdir -p "${link:h}"
			builtin ln -nf "${project_root}/build/git/${file}" "${link}"
		done
	done

	cd "${project_root}/build"

	mkdir -p "${project_root}/dist"
	log_info "Creating git.tar.xz"
	command bsdtar --options xz:compression-level=9 -s "/^git/git-${build_version}/" -s "/^tar/git-${build_version}/" -cJf "${project_root}/dist/git.tar.xz" "git" "tar"
	log_info "git.tar.xz created"

	cd "${project_root}"
	if false && command -v localpkg &>/dev/null; then
		log_info "Executing $(command -v localpkg)"
		localpkg build -z localpkg.zsh dist/git.localpkg
	elif [[ -n "${LOCALPKG_URL}" ]]; then
		log_info "executing ${LOCALPKG_URL}"
		curl -sL "${LOCALPKG_URL}" | zsh -sb build -z localpkg.zsh dist/git.localpkg
	else
		log_info "localpkg not found, skipping"
	fi
}

build_pkg() {
	log_info "Building product installer"
	cd "${project_root}/build"

	builtin mkdir -p scripts

	{
		printf "#!/bin/zsh\n"
		printf "zmodload %s\n" "${mods[*]}"
		typeset -p 1 package_files
		typeset -p mods
		typeset -f uninstall_git
		printf "%s\n" "${"$(typeset -f postinstall)"##postinstall }"
		printf "exit\n"
	} > scripts/postinstall || log_error "Failed to create postinstall script"

	builtin chmod 755 scripts/postinstall
	mkdir -p "${project_root}/dist"
	
	log_info "Building component package"
	pkgbuild  --identifier "org.kernel.git" --version "${build_version}" \
	 --install-location "/usr/local" --root git --scripts scripts --min-os-version "${macos_version}" \
	  "${project_root}/build/git-component.pkg"

	private hostArch="${CPUTYPE}"

	if (( build_universal )); then
		hostArch="${hostArch},x86_64"
	fi

	mkdir -p resources
	builtin ln -nf "${project_root}/src/git/COPYING" resources/license.txt

	sed -e 's/GIT_VERSION/'"${build_version}"'/g' -e 's/MACOS_VERSION/g'"${macos_version}"'/' \
		-e 's/HOST_ARCH/'"${hostArch}"'/g' < "${project_root}/distribution.xml" > distribution.xml

	( gen_readme ) > resources/readme.html

	private -a build_args=(--distribution distribution.xml --package-path . --resources resources)

	if [[ -n "${PKG_SIGNING_IDENTITY}" ]]; then
		build_args+=(--sign "${PKG_SIGNING_IDENTITY}")
	fi

	log_info "Building distribution package"
	command productbuild "${(@)build_args}" "${project_root}/dist/git.pkg"

	if [[ -n "${APPLE_TEAM_ID}" && -n "${APPLE_ID}" && -n "${APPLE_ID_PASSWORD}" ]]; then
		log_info "Submitting to Apple notarization service"
		xcrun notarytool submit "${project_root}/dist/git.pkg" \
			--apple-id "${APPLE_ID}" --team-id "${APPLE_TEAM_ID}" \
			--password "${APPLE_ID_PASSWORD}" --wait && \
		xcrun stapler staple "${project_root}/dist/git.pkg"
	fi

	log_info "git.pkg created"
}

postinstall() {
	# this is the postinstall script for the .pkg installer
	typeset -g INSTALL_PREFIX="${INSTALL_PREFIX:=/usr/local}"
	private file target
	private -a targets

	for file target_str in "${(@kv)package_files}"; do
		[[ -z "${target_str}" ]] && continue

		targets=(${(s/:/)target_str})

		for target in "${(@)targets}"; do
			builtin mkdir -p "${INSTALL_PREFIX}/${target:h}"
			builtin ln -nf "${INSTALL_PREFIX}/${file}" "${INSTALL_PREFIX}/${target}"
		done
	done

	private uninstall="${INSTALL_PREFIX}/libexec/git-core/uninstall-git"

	builtin rm -f "${uninstall}"
	builtin mkdir -p "${uninstall:h}"

	{
		printf "#!/bin/zsh\n"
		printf "zmodload %s\n" "${mods[*]}"
		typeset -p 1 INSTALL_PREFIX package_files
		typeset -p mods
		printf "%s\n" "${"$(typeset -f uninstall_git)"##uninstall_git }"
		printf "exit\n"
	} > "${uninstall}"

	builtin chmod 755 "${uninstall}"
}

uninstall_git() {
	# this is the uninstall script for the .pkg installer
	private file target
	private -a targets
	private -aU topdirs=()

	# this is installed to /usr/local/libexec/git-core/uninstall-git
	typeset -g INSTALL_PREFIX="${ZSH_SCRIPT:a:h}/../.." # /usr/local

	for file target_str in "${(@kv)package_files}"; do
		topdirs+=("${file%/*}")

		[[ ! -f "${file}" ]] && continue

		printf "rm -f %s\n" "${INSTALL_PREFIX}/${file}"
		builtin rm -f "${INSTALL_PREFIX}/${file}"
	done

	for dir in "${(@u)topdirs}"; do
		command find "${INSTALL_PREFIX}/${dir}" -type d -mindepth 1 -depth -empty -delete
	done

	printf "rm -f %s\n" "${ZSH_SCRIPT}"
	builtin rm -f "${ZSH_SCRIPT}"
}

gen_readme() {
	printf '<!DOCTYPE html>\n<html>\n<head><style>body {font-family: sans-serif;}</style></head>\n<body>'
	printf '<h1>git %s for macOS</h1>\n' "${build_version}"
	
	if [[ -n "${GITHUB_REPOSITORY}" ]]; then
		printf '<p>For updates, please visit the <a href="https://github.com/%s/releases">GitHub repository</a></p>\n' "${GITHUB_REPOSITORY}"
	fi

	printf '<h2>Installation Notes</h2>\n'
	printf '<p>This package installs git to <code>/usr/local</code>. To uninstall, run <code>/usr/local/libexec/git-core/uninstall-git</code></p>\n'
	printf '<p>After installation, git --version should show:</p>\n'
	printf '<pre>'
	"${project_root}/build/git/bin/git" --version
	printf '</pre>\n'
	printf '<br /><br />\n'
	printf '<p>If it does not, you may need to update your <code>PATH</code> environment variable.</p>\n'

	if (( build_man )); then
		printf '<p>To view the git documentation, run <code>man git</code></p>\n'
	fi

	printf '</body>\n</html>\n'
}

main
exit
