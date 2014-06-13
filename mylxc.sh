#!/bin/sh

#------------------------------------------------------------------------------
# Initialization:
#------------------------------------------------------------------------------

yumconf="[main]\n\
reposdir=/dev/null\n\
cachedir=/var/cache/yum/\$basearch/\$releasever\n\
keepcache=0\n\
debuglevel=2\n\
logfile=/var/log/yum.log\n\
exactarch=1\n\
obsoletes=1\n\
gpgcheck=1\n\
plugins=1\n\
installonly_limit=5\n\
distroverpkg=centos-release\n\
exclude=*.i?86\n\n"

repos="[centos-qa-03]\n\
name=CentOS Open QA – c7.00.03\n\
baseurl=http://buildlogs.centos.org/c7.00.03/\n\
enabled=1\n\
gpgcheck=0\n\
\n\
[centos-qa-04]\n\
name=CentOS Open QA – c7.00.04\n\
baseurl=http://buildlogs.centos.org/c7.00.04/\n\
enabled=1\n\
gpgcheck=0"

set -e
echo -e "${yumconf}${repos}" > /tmp/yum.conf
target=$(mktemp -d --tmpdir $(basename $0).XXXXXX)

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
# Minimal core:
#------------------------------------------------------------------------------

core_packages='audit basesystem bash biosdevname coreutils cronie curl dhclient e2fsprogs filesystem glibc hostname initscripts iproute iprutils iputils kbd less man-db ncurses openssh-clients openssh-server parted passwd plymouth policycoreutils procps-ng rootfiles rpm rsyslog selinux-policy-targeted setup shadow-utils sudo systemd util-linux vim-minimal yum'

#------------------------------------------------------------------------------
# Install the core system:
#------------------------------------------------------------------------------

yum \
-c /tmp/yum.conf \
--installroot="${target}" \
--setopt=tsflags=nodocs \
--setopt=group_package_types=mandatory \
-y install $core_packages

#------------------------------------------------------------------------------
# Setup networking:
#------------------------------------------------------------------------------

cat > ${target}/etc/sysconfig/network <<EOF
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

#------------------------------------------------------------------------------
# Setup buildlogs repo:
#------------------------------------------------------------------------------

echo -e "${repos}" > ${target}/etc/yum.repos.d/centos-buildlogs.repo

#------------------------------------------------------------------------------
# Minimize total size:
#------------------------------------------------------------------------------

yum \
-c /tmp/yum.conf \
--installroot=${target} \
-y clean all

rm -rf ${target}/usr/{{lib,share}/locale,{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive}
rm -rf ${target}/usr/share/{man,doc,info,gnome/help}
rm -rf ${target}/usr/share/cracklib
rm -rf ${target}/usr/share/i18n
rm -rf ${target}/sbin/sln
rm -rf ${target}/etc/ld.so.cache
rm -rf ${target}/var/cache/ldconfig/*

#------------------------------------------------------------------------------
# Generate a tar file and import it:
#------------------------------------------------------------------------------

tar \
--numeric-owner \
-c -C $target . | \
docker import - h0tbird/centos-7-qa:latest

#------------------------------------------------------------------------------
# Cleanup:
#------------------------------------------------------------------------------

rm -rf $target
rm -f /tmp/yum.conf
