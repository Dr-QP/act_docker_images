#!/bin/bash
# shellcheck disable=SC2174

set -Eeuxo pipefail

printf "\n\t🐋 Build started 🐋\t\n"

# Remove '"' so it can be sourced by sh/bash
sed 's|"||g' -i "/etc/environment"

. /etc/os-release

node_arch() {
  case "$(uname -m)" in
    'aarch64') echo 'arm64' ;;
    'x86_64') echo 'x64' ;;
    'armv7l') echo 'armv7l' ;;
    *) exit 1 ;;
  esac
}

ImageOS=ubuntu$(echo "${VERSION_ID}" | cut -d'.' -f 1)
AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
ACT_TOOLSDIRECTORY=/opt/acttoolcache
{
  echo "IMAGE_OS=$ImageOS"
  echo "ImageOS=$ImageOS"
  echo "LSB_RELEASE=${VERSION_ID}"
  echo "AGENT_TOOLSDIRECTORY=${AGENT_TOOLSDIRECTORY}"
  echo "RUN_TOOL_CACHE=${AGENT_TOOLSDIRECTORY}"
  echo "DEPLOYMENT_BASEPATH=/opt/runner"
  echo "USER=$(whoami)"
  echo "RUNNER_USER=$(whoami)"
  echo "ACT_TOOLSDIRECTORY=${ACT_TOOLSDIRECTORY}"
} | tee -a "/etc/environment"

mkdir -m 0777 -p "${AGENT_TOOLSDIRECTORY}"
chown -R 1001:1000 "${AGENT_TOOLSDIRECTORY}"
mkdir -m 0777 -p "${ACT_TOOLSDIRECTORY}"
chown -R 1001:1000 "${ACT_TOOLSDIRECTORY}"

mkdir -m 0777 -p /github
chown -R 1001:1000 /github

printf "\n\t🐋 Installing packages 🐋\t\n"
packages=(
  ssh
  gawk
  curl
  jq
  wget
  sudo
  gnupg-agent
  ca-certificates
  software-properties-common
  apt-transport-https
  libyaml-0-2
  zstd
  zip
  unzip
  xz-utils
  python3-pip
  python3-venv
  pipx
)

apt-get -yq update
apt-get -yq install --no-install-recommends --no-install-suggests "${packages[@]}"

ln -s "$(which python3)" "/usr/local/bin/python"

add-apt-repository ppa:git-core/ppa -y
apt-get update
apt-get install -y git

git --version

git config --system --add safe.directory '*'

wget https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh -qO- | bash
apt-get update
apt-get install -y git-lfs

LSB_OS_VERSION="${VERSION_ID//\./}"
echo "LSB_OS_VERSION=${LSB_OS_VERSION}" | tee -a "/etc/environment"

wget -qO "/imagegeneration/toolset.json" "https://raw.githubusercontent.com/actions/virtual-environments/main/images/ubuntu/toolsets/toolset-${LSB_OS_VERSION}.json" || echo "File not available"
wget -qO "/imagegeneration/LICENSE" "https://raw.githubusercontent.com/actions/virtual-environments/main/LICENSE"

if [ "$(uname -m)" = x86_64 ]; then
  wget -qO "/usr/bin/jq" "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
  chmod +x "/usr/bin/jq"
fi

printf "\n\t🐋 Updated apt lists and upgraded packages 🐋\t\n"

printf "\n\t🐋 Creating ~/.ssh and adding 'github.com' 🐋\t\n"
mkdir -m 0700 -p ~/.ssh
{
  ssh-keyscan github.com
  ssh-keyscan ssh.dev.azure.com
} >>/etc/ssh/ssh_known_hosts

printf "\n\t🐋 Installed base utils 🐋\t\n"

printf "\n\t🐋 Installing docker cli 🐋\t\n"
if [[ "${VERSION_ID}" == "18.04" ]]; then
  echo "deb https://packages.microsoft.com/ubuntu/${VERSION_ID}/multiarch/prod ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/microsoft-prod.list
else
  echo "deb https://packages.microsoft.com/ubuntu/${VERSION_ID}/prod ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/microsoft-prod.list
fi
wget -q https://packages.microsoft.com/keys/microsoft.asc
gpg --dearmor <microsoft.asc >/etc/apt/trusted.gpg.d/microsoft.gpg
apt-key add - <microsoft.asc
rm microsoft.asc
apt-get -yq update
apt-get -yq install --no-install-recommends --no-install-suggests moby-cli moby-engine iptables moby-buildx moby-compose

printf "\n\t🐋 Installed moby-cli 🐋\t\n"
docker -v

printf "\n\t🐋 Installed moby-buildx 🐋\t\n"
docker buildx version
IFS=' ' read -r -a NODE <<<"$NODE_VERSION"
for ver in "${NODE[@]}"; do
  curl -sL https://deb.nodesource.com/setup_${ver}.x -o nodesource_setup.sh
  sudo bash nodesource_setup.sh
  rm "nodesource_setup.sh"

  # The NodeSource nodejs package contains both the node binary and npm, so you don’t need to install npm separately.
  apt-get install -y -q --no-install-recommends nodejs
  npm install -g yarn
done

case "$(uname -m)" in
  'aarch64')
    scripts=(
      yq
    )
    ;;
  'x86_64')
    scripts=(
      yq
    )
    ;;
  'armv7l')
    scripts=(
      yq
    )
    ;;
  *) exit 1 ;;
esac

for SCRIPT in "${scripts[@]}"; do
  printf "\n\t🧨 Executing %s.sh 🧨\t\n" "${SCRIPT}"
  "/imagegeneration/installers/${SCRIPT}.sh"
done

printf "\n\t🐋 Cleaning image 🐋\t\n"
apt-get clean
rm -rf /var/cache/* /var/log/* /var/lib/apt/lists/* /tmp/* || echo 'Failed to delete directories'

printf "\n\t🐋 Cleaned up image 🐋\t\n"
