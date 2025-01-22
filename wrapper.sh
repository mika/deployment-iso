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

# old:
#fai_config='/code/grml-live/etc/grml/fai/config'
# new:
fai_config='/code/grml-live/config/'
outside_fai_config="${PWD}/grml_build/config/"

# get the puppet public key, so no need to download it in deployment.sh
puppet_key='puppet.gpg'
wget -O "${outside_fai_config}/files/root/${puppet_key}/PUPPETLABS" http://apt.puppetlabs.com/DEB-GPG-KEY-puppetlabs

# write apt sources
source_list_path='etc/apt/sources.list.d/sipwise.list'
repo_addr="deb https://deb.sipwise.com/spce/mr12.5.1/ bookworm main"
debian_bootstrap_url="https://debian.sipwise.com/debian/"
echo "${repo_addr}" > "${outside_fai_config}files/${source_list_path}/SIPWISE"

iso_image_name="grml-sipwise-${osversion}-$(date +%Y%m%d_%H%M%S).iso"

build_command=''
build_command+=" cp -rv /grml/config/ /code/grml-live/"
build_command+=" && GRML_NAME=grml64-small"
build_command+=" CHROOT_OUTPUT=/root/grml_chroot"
build_command+=" FAI_DEBOOTSTRAP='${osversion} ${debian_bootstrap_url}'"
build_command+=" LIVE_CONF=/code/grml-live/etc/grml/grml-live.conf"
build_command+=" GRML_FAI_CONFIG=${fai_config}"
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
  -v "$(pwd)":/deployment-iso/ \
  -v "$(pwd)/grml_build/":/grml/ \
  grml-sipwise \
  /bin/bash -c "${build_command}"
