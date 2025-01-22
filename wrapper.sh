#!/bin/bash

# sanity checks
if ! [ -d grml_build ] ; then
  echo "Error: grml_build doesn't exist, executing outside deployment-iso directory?" >&1
  exit 1
fi

if [ "$(basename "$(pwd)")" != "deployment-iso" ] ; then
  echo "Error: you need to run this inside the deployment-iso directory." >&1
  exit 1
fi

source_list_path='etc/apt/sources.list.d/sipwise.list'
mkdir -p "${source_list_path}"
repo_addr="deb https://deb.debian.org/debian bookworm main"
echo "${repo_addr}" > "${source_list_path}/SIPWISE"

# get the puppet public key, so no need to download it in deployment.sh
puppet_key='puppet.gpg'
wget -O "${puppet_key}" http://apt.puppetlabs.com/DEB-GPG-KEY-puppetlabs

keyring_file_name='sipwise-keyring-bootstrap.gpg'
wget -O "${keyring_file_name}" https://deb.sipwise.com/spce/sipwise.gpg

# Workarounds to execute docker without privileged mode
cat > "$(pwd)"/grml_build/adjust_fai.sh << EOF
#!/bin/bash

if ! [ -r /.dockerenv ] ; then
  echo "INFO: Not running inside docker, skipping docker workarounds."
  exit 0
else
  echo "INFO: Running inside docker environment"
fi

if ! findmnt -o+PROPAGATION /proc/sysrq-trigger >/dev/null ; then
  echo "INFO: Running in privileged environment"
else
  echo "INFO: Running in unprivileged environment"
fi

if unshare --pid --fork --kill-child --mount-proc chroot / ls &>/dev/null ; then
  echo "INFO: unshare seems to work, *not* applying ROOTCMD workaround for FAI"
else
  echo "INFO: unshare not working, applying ROOTCMD workaround for FAI"
  sed -i 's/ROOTCMD="unshare.*/ROOTCMD="chroot \$FAI_ROOT"/' /usr/sbin/fai
fi

echo "Finished execution of \$0"
EOF
chmod 775 "$(pwd)"/grml_build/adjust_fai.sh

fai_config='/code/grml-live/etc/grml/fai/config'
keyring_path="${fai_config}/files/etc/apt/trusted.gpg.d/${keyring_file_name}/SIPWISE"
puppet_key_path="${fai_config}/files/root/${puppet_key}/PUPPETLABS"
iso_image_name="grml-sipwise-${osversion}-$(date +%Y%m%d_%H%M%S).iso"
declare -a fai_debootstrap_opts=()
fai_debootstrap_opts+=('--exclude=info,tasksel,tasksel-data')
fai_debootstrap_opts+=("--keyring=${keyring_path}")

# starting with Debian/bookworm we need merged-/usr
case "${osversion}" in
  buster|bullseye)
    fai_debootstrap_opts+=('--include=aptitude')
    fai_debootstrap_opts+=("--no-merged-usr")
    echo "Building for ${osversion}, not enabling merged-/usr"
    ;;
  *)
    fai_debootstrap_opts+=('--include=aptitude,usrmerge')
    echo "Building for ${osversion}, enabling merged-/usr"
    ;;
esac

build_command=''
build_command+="/grml/adjust_fai.sh"
build_command+=" && cp '/deployment-iso/grml_build/package_config/SIPWISE' '${fai_config}/package_config/SIPWISE'"
build_command+=" && cp '/deployment-iso/${source_list_path}/SIPWISE' '${fai_config}/files/${source_list_path}/'"
build_command+=" && cp /deployment-iso/templates/scripts/keys/${keyring_file_name} '${keyring_path}'"
case "${release}" in
  [2-3].*|mr[3-6].*|mr7.[0-4]*)
    echo "No need to add puppet key for release ${release}"
  ;;
  *)
    build_command+=" && cp '/deployment-iso/grml_build/10-gpgkey' '${fai_config}/scripts/PUPPETLABS/'"
    build_command+=" && cp '/deployment-iso/${puppet_key}' '${puppet_key_path}'"
  ;;
esac
build_command+=" && GRML_NAME=grml64-small"
build_command+=" FAI_ARGS='--verbose'"
build_command+=" FAI_DEBOOTSTRAP='${osversion} https://deb.debian.org/debian'"
build_command+=" FAI_DEBOOTSTRAP_OPTS='${fai_debootstrap_opts[*]}'"
build_command+=" LIVE_CONF=/code/grml-live/etc/grml/grml-live.conf"
build_command+=" SCRIPTS_DIRECTORY=/code/grml-live/scripts"
build_command+=" GRML_FAI_CONFIG=/code/grml-live/etc/grml/fai"
build_command+=" ./grml-live"
build_command+=" -s '${osversion}'"
build_command+=" -a amd64"
build_command+=" -i '${iso_image_name}'"
build_command+=" -c GRMLBASE,SIPWISE,AMD64,PUPPETLABS"
build_command+=" -t /code/grml-live/templates/"
build_command+=" -o /grml/"
build_command+=" -r 'grml-sipwise-${osversion}'"
build_command+=" -v '${release}'"
build_command+=" -F"
build_command+=" -V"
build_command+=" && cd /grml/grml_isos/"
build_command+=" && sha1sum '${iso_image_name}' > '${iso_image_name}.sha1'"
build_command+=" && md5sum  '${iso_image_name}' > '${iso_image_name}.md5'"

echo "System information:"
uname -a
lsb_release -a
docker --version
dpkg -l | grep docker

echo "Build command is:"
echo "${build_command}"

docker run --rm \
  --cap-add=SYS_ADMIN \
  --security-opt apparmor=unconfined \
  -v "$(pwd)":/deployment-iso/ \
  -v "$(pwd)/grml_build/":/grml/ \
  grml-sipwise \
  /bin/bash -c "${build_command}"
