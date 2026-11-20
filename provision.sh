#!/usr/bin/env bash

SCRIPT_VERSION=1.0.0

SCRIPT_NAME=$(basename ${BASH_SOURCE[0]})
SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
SCRIPT_PATH=${BASH_SOURCE[0]}

function echo_usage()
{
	echo "${SCRIPT_NAME} - Version ${SCRIPT_VERSION}"
	echo ""
	echo "Provision a virtual machine."
	echo ""
	echo "Usage: ${SCRIPT_NAME} [options]"
	echo ""
	echo "      --help     Output this help information."
	echo "  -v, --version  Output the version."
}

# ANSI color escape sequences for use in echo_color().
BLACK='\e[30m'
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
WHITE='\e[37m'
RESET='\e[0m'

# Echo a color message.
# Echoing ANSI escape codes for color works, yet tput does not.
# This may be caused by tput not being able to determine the terminal type.
# Usage: echo_color color message
function echo_color()
{
	local color=${1}
	local message=${2}
	echo -e "${color}${message}${RESET}"
}

# Echo an informational message.
# Usage: echo_info message
function echo_info()
{
	local message=${1}
	echo_color ${CYAN} "${message}"
}

# Echo a warning message.
# Usage: echo_warning message
function echo_warning()
{
	local message=${1}
	echo_color ${YELLOW} "${message}"
}

# Echo an error message.
# Usage: echo_error message
function echo_error()
{
	local message=${1}
	echo_color ${RED} "${SCRIPT_NAME}: Error: ${message}"
}

# Echo an error message and exit.
# Usage: echo_error_and_exit message
function echo_error_and_exit()
{
	local message=${1}
	echo_error "${message}"
	exit 1
}

# Set the mode, user, and group of a file or directory.
# Usage: set_mode_user_group mode user group file_or_dir
function set_mode_user_group()
{
	local mode=${1}
	local user=${2}
	local group=${3}
	local file_or_dir=${4}
	echo_info "Setting mode for ${file_or_dir} to ${mode} ..."
	sudo chmod ${mode} ${file_or_dir}
	echo_info "Setting user and group for ${file_or_dir} to ${user}:${group} ..."
	sudo chown ${user}:${group} ${file_or_dir}
}

# Create a directory, if it does not exist.
# If created, then set the mode, user, and group of the new directory.
# Usage: create_dir_with_mode_user_group mode user group dir
function create_dir_with_mode_user_group()
{
	local mode=${1}
	local user=${2}
	local group=${3}
	local dir=${4}
	[ -d ${dir} ] && return
	echo_info "Creating ${dir} ..."
	sudo mkdir -p ${dir}
	set_mode_user_group ${mode} ${user} ${group} ${dir}
}

# Check if a program exists and is executable by this user.
# Echo an error message and exit the script if the program does not exist or is not executable by this user.
# Usage: check_program program
function check_program()
{
	local program=${1}
	echo_info "Checking for program '${program}' ..."
	local full_path=$(which ${program})
	if [ -z "${full_path}" ]; then
		echo_error_and_exit "Cannot find '${program}'."
	fi
	echo_info "Found program '${program}' at '${full_path}'."
	if [ ! -x "${full_path}" ]; then
		echo_error_and_exit "'${full_path}' is not executable."
	fi
}

# Attempt a command up to four times; one initial attempt followed by three reties.
# Attempts are spaced 15 seconds apart.
# Echo an error message and exit the script if the command fails after all retries.
# Usage: retry_if_fail command args
function retry_if_fail()
{
	echo_info "Attempting command: '${*}'"
	${*}
	if [ ${?} -ne 0 ]; then
		local max_retries=3
		local retry=1
		local retry_wait=15
		while [ ${retry} -le ${max_retries} ]; do
			echo_warning "'${*}' failed. Will retry in ${retry_wait} seconds."
			sleep ${retry_wait}
			echo_info "Retrying '${*}' (${retry} of ${max_retries}) ..."
			${*} && break
			retry=$[$retry + 1]
		done
		if [ ${retry} -gt ${max_retries} ]; then
			echo_error_and_exit "'${*}' failed after $[$max_retries + 1] attempts."
		fi
	else
		echo_info "'${*}' succeeded."
	fi
}

# Modes for provisioned directory and file assets.
# This will keep things private.
# Along with other things, these modes are also used for private keys and credentials.
ASSET_DIR_MODE=u+rwx,go-rwx
ASSET_FILE_MODE=u+rw-x,go-rwx
ASSET_SCRIPT_MODE=u+rwx,go-rwx

# Parse the options using GNU getopt.
# On Mac OS X and FreeBSD, you have to install GNU getopt separately.
GETOPT_SHORT_OPTIONS="v"
GETOPT_LONG_OPTIONS="help,version"
PARSED_ARGS=$(getopt -o ${GETOPT_SHORT_OPTIONS} -l ${GETOPT_LONG_OPTIONS} -n ${SCRIPT_NAME} -- "${@}")
return_code=${?}
if [ ${return_code} -ne 0 ]; then
	echo_error_and_exit "getopt returned ${return_code}" >&2
fi

# Re-index positional arguments to match parsed structure.
# The quotes around "${PARSED_ARGS}" are necessary.
eval set -- "${PARSED_ARGS}"

# Parse the command line arguments.
while true; do
	case "${1}" in
		--help)
			echo_usage
			exit 0
			;;
		-v | --version)
			echo "${SCRIPT_VERSION}"
			exit 0
			;;
		--)
			shift
			break
			;;
	esac
done
if [ ${#} -gt 0 ]; then
	while [ ${#} -gt 0 ]; do
		echo_error "Invalid argument -- '${1}'" >&2
		shift
	done
	exit 1
fi

echo_info "Script: ${SCRIPT_PATH}"
echo_info "Current user: $(whoami)"
echo_info "Home directory: ${HOME}"
echo_info "Current directory: $(pwd)"

DEV_SYS_HOME_DIR=$(eval echo ~${DEV_SYS_USER})
echo_info "DEV_SYS user: ${DEV_SYS_USER}"
echo_info "DEV_SYS group: ${DEV_SYS_GROUP}"
echo_info "DEV_SYS home directory: ${DEV_SYS_HOME_DIR}"

# Make installations non-interactive.
DEBIAN_FRONTEND_VAR="DEBIAN_FRONTEND=noninteractive"
export ${DEBIAN_FRONTEND_VAR}
APT_GET_OPTIONS="--yes --option Dpkg::Options::=--force-confdef --option Dpkg::Options::=--force-confold"

# Do not buffer Python stdout.
export PYTHONUNBUFFERED=TRUE

# Create the dev-sys assets directory.
ASSETS_DIR=${DEV_SYS_HOME_DIR}/.dev-sys
create_dir_with_mode_user_group ${ASSET_DIR_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${ASSETS_DIR}

echo_info "Checking dependencies ..."
check_program ssh
check_program ssh-keygen
check_program ssh-keyscan

# Create the SSH directory.
SSH_DIR=${DEV_SYS_HOME_DIR}/.ssh
create_dir_with_mode_user_group ${ASSET_DIR_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${SSH_DIR}

# Create the SSH keys used to run commands as the dev-sys user.
SSH_KEY_BASENAME=id_dev-sys
SSH_PRIVATE_KEY_FILE=${ASSETS_DIR}/${SSH_KEY_BASENAME}
SSH_PUBLIC_KEY_FILE=${ASSETS_DIR}/${SSH_KEY_BASENAME}.pub
if [ ! -f ${SSH_PRIVATE_KEY_FILE} ]; then
	echo_info "Creating new SSH keys for use by dev-sys ..."
	ssh-keygen -C ${SSH_KEY_BASENAME} -f ${SSH_PRIVATE_KEY_FILE} -N ""
	set_mode_user_group ${ASSET_FILE_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${SSH_PRIVATE_KEY_FILE}
	set_mode_user_group ${ASSET_FILE_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${SSH_PUBLIC_KEY_FILE}
fi
SSH_PUBLIC_KEY_CONTENTS=$(cat ${SSH_PUBLIC_KEY_FILE})
SSH_AUTHORIZED_KEYS_FILE=${SSH_DIR}/authorized_keys
if [ ! -f ${SSH_AUTHORIZED_KEYS_FILE} ]; then
	touch ${SSH_AUTHORIZED_KEYS_FILE}
	set_mode_user_group ${ASSET_FILE_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${SSH_AUTHORIZED_KEYS_FILE}
fi
grep -Fx "${SSH_PUBLIC_KEY_CONTENTS}" ${SSH_AUTHORIZED_KEYS_FILE} > /dev/null
if [ ${?} -ne 0 ]; then
	echo_info "Adding the dev-sys SSH public key to ${SSH_AUTHORIZED_KEYS_FILE} ..."
	echo "${SSH_PUBLIC_KEY_CONTENTS}" >> ${SSH_AUTHORIZED_KEYS_FILE}
fi

# Adds 127.0.0.1 to the known_hosts file.
# This will avoid prompts when Ansible uses SSH to provison the local host.
SSH_KNOWN_HOSTS_FILE=${HOME}/.ssh/known_hosts
if [ ! -f ${SSH_KNOWN_HOSTS_FILE} ]; then
	echo_info "Creating ${SSH_KNOWN_HOSTS_FILE} ..."
	touch ${SSH_KNOWN_HOSTS_FILE}
	chmod u+rw-x,go+r-wx ${SSH_KNOWN_HOSTS_FILE}
fi
ssh-keygen -F 127.0.0.1 -f ${SSH_KNOWN_HOSTS_FILE} > /dev/null 2>&1
if [ ${?} -ne 0 ]; then
	echo_info "Adding the local host's SSH fingerprint to ${SSH_KNOWN_HOSTS_FILE} ..."
	ssh-keyscan -H 127.0.0.1 >> ${SSH_KNOWN_HOSTS_FILE} || exit 1
fi

echo_info "Checking SSH connectivity to the local host ..."
ssh ${DEV_SYS_USER}@127.0.0.1 -i ${SSH_PRIVATE_KEY_FILE} echo Success || exit 1

INSTALLATION_MANIFEST_FILE=${ASSETS_DIR}/installation-manifest.txt

if [ ! -f ${INSTALLATION_MANIFEST_FILE} ]; then
	echo_info "Creating ${INSTALLATION_MANIFEST_FILE} ..."
	touch ${INSTALLATION_MANIFEST_FILE}
	set_mode_user_group ${ASSET_FILE_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${INSTALLATION_MANIFEST_FILE}
fi

echo_info "Running apt-get update ..."
retry_if_fail sudo ${DEBIAN_FRONTEND_VAR} apt-get update ${APT_GET_OPTIONS}

echo_info "Running apt-get upgrade ..."
retry_if_fail sudo ${DEBIAN_FRONTEND_VAR} apt-get upgrade ${APT_GET_OPTIONS}

echo_info "Installing or updating software-properties-common ..."
retry_if_fail sudo ${DEBIAN_FRONTEND_VAR} apt-get install software-properties-common ${APT_GET_OPTIONS}

which git > /dev/null 2>&1
if [ ${?} -ne 0 ]; then
	echo_info "Installing git ..."
	retry_if_fail sudo ${DEBIAN_FRONTEND_VAR} apt-get install git ${APT_GET_OPTIONS}

	echo_info "Adding git to ${INSTALLATION_MANIFEST_FILE} ..."
	echo git >> ${INSTALLATION_MANIFEST_FILE}
fi

# If ANSIBLE_DEV_SYS_DIR is set, then assume that ansible-dev-sys is being managed by the host.
if [ ! -z "${ANSIBLE_DEV_SYS_DIR}" ]; then
	ANSIBLE_DEV_SYS_MANAGED_EXTERNALLY=true
else
	ANSIBLE_DEV_SYS_DIR=${ASSETS_DIR}/ansible-dev-sys
	ANSIBLE_DEV_SYS_MANAGED_EXTERNALLY=false
fi

# Save the ansible-dev-sys variables into a script for later use.
ANSIBLE_DEV_SYS_VARS_SCRIPT=${ASSETS_DIR}/ansible-dev-sys-vars.sh
echo_info "Creating ${ANSIBLE_DEV_SYS_VARS_SCRIPT} ..."
cat << EOF >| ${ANSIBLE_DEV_SYS_VARS_SCRIPT}
#!/usr/bin/env bash
ANSIBLE_DEV_SYS_DIR=${ANSIBLE_DEV_SYS_DIR}
ANSIBLE_DEV_SYS_MANAGED_EXTERNALLY=${ANSIBLE_DEV_SYS_MANAGED_EXTERNALLY}
EOF
if [ ! -z "${ANSIBLE_DEV_SYS_VERSION}" ]; then
	echo "ANSIBLE_DEV_SYS_VERSION=${ANSIBLE_DEV_SYS_VERSION}" >> ${ANSIBLE_DEV_SYS_VARS_SCRIPT}
fi
set_mode_user_group ${ASSET_SCRIPT_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${ANSIBLE_DEV_SYS_VARS_SCRIPT}

# If BASH_ENVIRONMENT_DIR is set, then assume that bash-environment is being managed by the host.
if [ ! -z "${BASH_ENVIRONMENT_DIR}" ]; then
	BASH_ENVIRONMENT_MANAGED_EXTERNALLY=true
else
	BASH_ENVIRONMENT_DIR=${ASSETS_DIR}/bash-environment
	BASH_ENVIRONMENT_MANAGED_EXTERNALLY=false
fi

# Save the bash-environment variables into a script for later use.
BASH_ENVIRONMENT_VARS_SCRIPT=${ASSETS_DIR}/bash-environment-vars.sh
echo_info "Creating ${BASH_ENVIRONMENT_VARS_SCRIPT} ..."
cat << EOF >| ${BASH_ENVIRONMENT_VARS_SCRIPT}
#!/usr/bin/env bash
BASH_ENVIRONMENT_DIR=${BASH_ENVIRONMENT_DIR}
BASH_ENVIRONMENT_MANAGED_EXTERNALLY=${BASH_ENVIRONMENT_MANAGED_EXTERNALLY}
EOF
if [ ! -z "${BASH_ENVIRONMENT_VERSION}" ]; then
	echo "BASH_ENVIRONMENT_VERSION=${BASH_ENVIRONMENT_VERSION}" >> ${BASH_ENVIRONMENT_VARS_SCRIPT}
fi
set_mode_user_group ${ASSET_SCRIPT_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${BASH_ENVIRONMENT_VARS_SCRIPT}

# If ansible-dev-sys does not exist, then temporarily clone it and get a copy of its dev-sys.sh.
if [ ! -d ${ANSIBLE_DEV_SYS_DIR} ]; then
	# Temporarily clone ansible-dev-sys.
	TMP_ANSIBLE_DEV_SYS_DIR=${ASSETS_DIR}/tmp-ansible-dev-sys
	ANSIBLE_DEV_SYS_URL=https://github.com/neilluna/ansible-dev-sys.git
	echo_info "Cloning ${ANSIBLE_DEV_SYS_URL} to ${TMP_ANSIBLE_DEV_SYS_DIR} ..."
	retry_if_fail git clone ${ANSIBLE_DEV_SYS_URL} ${TMP_ANSIBLE_DEV_SYS_DIR}
	if [ ! -z "${ANSIBLE_DEV_SYS_VERSION}" ]; then
		pushd ${TMP_ANSIBLE_DEV_SYS_DIR} > /dev/null
		echo_info "Switching to branch ${ANSIBLE_DEV_SYS_VERSION} ..."
		git checkout ${ANSIBLE_DEV_SYS_VERSION} || exit 1
		popd > /dev/null
	fi

	# Copy dev-sys.sh from the temporary ansible-dev-sys clone to the assets directory.
	TMP_ANSIBLE_DEV_SYS_SCRIPT=${TMP_ANSIBLE_DEV_SYS_DIR}/dev-sys.sh
	TMP_ASSETS_DEV_SYS_SCRIPT=${ASSETS_DIR}/dev-sys.sh
	echo_info "Copying ${TMP_ANSIBLE_DEV_SYS_SCRIPT} to ${TMP_ASSETS_DEV_SYS_SCRIPT} ..."
	cp -f ${TMP_ANSIBLE_DEV_SYS_SCRIPT} ${TMP_ASSETS_DEV_SYS_SCRIPT}
	DEV_SYS_SCRIPT=${TMP_ASSETS_DEV_SYS_SCRIPT}

	# Remove the temporarily ansible-dev-sys clone.
	echo_info "Removing ${TMP_ANSIBLE_DEV_SYS_DIR} ..."
	rm -rf ${TMP_ANSIBLE_DEV_SYS_DIR}
else
	DEV_SYS_SCRIPT=${ANSIBLE_DEV_SYS_DIR}/dev-sys.sh
fi
set_mode_user_group ${ASSET_SCRIPT_MODE} ${DEV_SYS_USER} ${DEV_SYS_GROUP} ${DEV_SYS_SCRIPT}

# Run dev-sys.sh.
SSH_COMMAND="ssh ${DEV_SYS_USER}@127.0.0.1 -i ${SSH_PRIVATE_KEY_FILE} ${DEV_SYS_SCRIPT} ${ANSIBLE_DEV_SYS_TAGS}"
echo_info "Running ${DEV_SYS_SCRIPT} as ${DEV_SYS_USER} ..."
${SSH_COMMAND} || exit 1

if [ ! -z "${TMP_ASSETS_DEV_SYS_SCRIPT}" ]; then
	# Echo a leading newline to separate this echo from the output of dev-sys.sh.
	echo_info "\nRemoving ${TMP_ASSETS_DEV_SYS_SCRIPT} ..."
	rm -f ${TMP_ASSETS_DEV_SYS_SCRIPT}
fi

exit 0
