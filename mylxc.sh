#!/bin/sh

#------------------------------------------------------------------------------
# Initialization:
#------------------------------------------------------------------------------

yumconf="[main]\n\
cachedir=/var/cache/yum/\$basearch/\$releasever\n\
keepcache=0\n\
debuglevel=2\n\
logfile=/var/log/yum.log\n\
exactarch=1\n\
obsoletes=1\n\
gpgcheck=1\n\
plugins=1\n\
installonly_limit=5\n\
bugtracker_url=http://bugs.centos.org/set_project.php?project_id=16&ref=http://bugs.centos.org/bug_report_page.php?category=yum\n\
distroverpkg=centos-release\n\
exclude=*.i?86"

set -e
echo -e ${yumconf} > /tmp/yum.conf
target=$(mktemp -d --tmpdir $(basename $0).XXXXXX)

#------------------------------------------------------------------------------
# Setup the needed devices:
#------------------------------------------------------------------------------

mkdir -m 755 "${target}"/dev
mknod -m 600 "${target}"/dev/console c 5 1
mknod -m 600 "${target}"/dev/initctl p
mknod -m 666 "${target}"/dev/full c 1 7
mknod -m 666 "${target}"/dev/null c 1 3
mknod -m 666 "${target}"/dev/ptmx c 5 2
mknod -m 666 "${target}"/dev/random c 1 8
mknod -m 666 "${target}"/dev/tty c 5 0
mknod -m 666 "${target}"/dev/tty0 c 4 0
mknod -m 666 "${target}"/dev/urandom c 1 9
mknod -m 666 "${target}"/dev/zero c 1 5

#------------------------------------------------------------------------------
# Install the core system:
#------------------------------------------------------------------------------

yum \
-c /tmp/yum.conf \
--installroot="${target}" \
--setopt=tsflags=nodocs \
--setopt=group_package_types=mandatory \
-y groupinstall Core

#------------------------------------------------------------------------------
# Setup networking:
#------------------------------------------------------------------------------

cat > "${target}"/etc/sysconfig/network <<EOF
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

#------------------------------------------------------------------------------
# Minimize total size:
#------------------------------------------------------------------------------

yum \
-c /tmp/yum.conf \
--installroot="${target}" \
-y clean all

rm -rf "$target"/usr/{{lib,share}/locale,{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive}
rm -rf "$target"/usr/share/{man,doc,info,gnome/help}
rm -rf "$target"/usr/share/cracklib
rm -rf "$target"/usr/share/i18n
rm -rf "$target"/sbin/sln
rm -rf "$target"/etc/ld.so.cache
rm -rf "$target"/var/cache/ldconfig/*

#------------------------------------------------------------------------------
# Generate the tar file:
#------------------------------------------------------------------------------

tar \
--numeric-owner \
-cf centos.tar \
-C $target .

#------------------------------------------------------------------------------
# Cleanup:
#------------------------------------------------------------------------------

rm -rf $target
rm -f /tmp/yum.conf
