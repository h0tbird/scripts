#!/bin/sh

#------------------------------------------------------------------------------
# Initialization:
#------------------------------------------------------------------------------

yumconf="[main]\n\
reposdir=/dev/null\n\
cachedir=/var/cache/yum/x86_64/7\n\
keepcache=0\n\
debuglevel=2\n\
logfile=/var/log/yum.log\n\
exactarch=1\n\
obsoletes=1\n\
gpgcheck=1\n\
plugins=1\n\
tsflags=nodocs\n\
group_package_types=mandatory\n\
installonly_limit=5\n\
distroverpkg=centos-release\n\
exclude=*.i?86\n\
exclude=kernel* *firmware os-prober gettext* freetype\n\n"

repos="[base]\n\
name=CentOS-7 - Base\n\
baseurl=http://mirror.centos.org/centos/7/os/x86_64/\n\
gpgkey=http://mirror.centos.org/centos/7/os/x86_64/RPM-GPG-KEY-CentOS-7\n\
\n\
[updates]
name=CentOS-7 - Updates\n\
baseurl=http://mirror.centos.org/centos/7/updates/x86_64/\n\
gpgkey=http://mirror.centos.org/centos/7/os/x86_64/RPM-GPG-KEY-CentOS-7\n"

packages="bind-utils hostname bash yum iputils iproute centos-release shadow-utils less"

set -e
echo -e "${yumconf}${repos}" > /tmp/yum.conf
target=`mktemp -d --tmpdir $(basename $0).XXXXXX`

#------------------------------------------------------------------------------
# Setup the needed devices:
#------------------------------------------------------------------------------

mkdir -m 755 ${target}/dev
mknod -m 600 ${target}/dev/console c 5 1
mknod -m 600 ${target}/dev/initctl p
mknod -m 666 ${target}/dev/full c 1 7
mknod -m 666 ${target}/dev/null c 1 3
mknod -m 666 ${target}/dev/ptmx c 5 2
mknod -m 666 ${target}/dev/random c 1 8
mknod -m 666 ${target}/dev/tty c 5 0
mknod -m 666 ${target}/dev/tty0 c 4 0
mknod -m 666 ${target}/dev/urandom c 1 9
mknod -m 666 ${target}/dev/zero c 1 5

#------------------------------------------------------------------------------
# Install the core system:
#------------------------------------------------------------------------------

yum \
-c /tmp/yum.conf \
--installroot="${target}" \
-y install $packages

#------------------------------------------------------------------------------
# Setup networking:
#------------------------------------------------------------------------------

mkdir -p ${target}/etc/sysconfig/network-scripts

cat > ${target}/etc/sysconfig/network <<EOF
NETWORKING=yes
NETWORKING_IPV6=no
HOSTNAME=localhost.localdomain
EOF

cat > ${target}/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=on
EOF

#------------------------------------------------------------------------------
# Set container /etc/yum.conf
#------------------------------------------------------------------------------

echo -e "${yumconf}" > ${target}/etc/yum.conf
sed -i '/reposdir/d' ${target}/etc/yum.conf

#------------------------------------------------------------------------------
# Minimize total size:
#------------------------------------------------------------------------------

yum \
-c /tmp/yum.conf \
--installroot=${target} \
-y clean all

rm -rf ${target}/usr/{{lib,share}/locale,{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive}
rm -rf ${target}/usr/share/{man,doc,info,gnome/help,cracklib,i18n}
rm -rf ${target}/sbin/sln
rm -rf ${target}/etc/ld.so.cache
rm -rf ${target}/var/cache/ldconfig/*

#------------------------------------------------------------------------------
# Generate a tar file and import it:
#------------------------------------------------------------------------------

tar \
--numeric-owner \
-c -C $target . | \
docker import - h0tbird/centos:`date +%Y%m%d`

#------------------------------------------------------------------------------
# Cleanup:
#------------------------------------------------------------------------------

rm -rf $target
rm -f /tmp/yum.conf
