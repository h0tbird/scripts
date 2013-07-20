#!/bin/bash

#------------------------------------------------------------------------------
# ./myami.sh \
# --arch i686 \
# --bucket centos6-32bit \
# --location EU \
# --region eu-west-1 \
# --size 1024 \
# --user xxxxxxxxxx \
# --cert /path/to/my/cert \
# --key /path/to/my/key \
# --akey yyyyyyyyyy \
# --skey zzzzzzzzzz \
# --sshk /path/to/my/pub/ssh/key
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Halt on any error:
#------------------------------------------------------------------------------

set -e

#------------------------------------------------------------------------------
# Parse the command-line:
#------------------------------------------------------------------------------

while [ $# -gt 0 ]; do

    case $1 in

        --arch)        arch[0]=$2;                              shift 2 ;;
        --timezone)    timezone=$2;                             shift 2 ;;
        --locale)      locale=$2;                               shift 2 ;;
        --charmap)     charmap=$2;                              shift 2 ;;
        --imgdir)      imgdir=$2;                               shift 2 ;;
        --bucket)      bucket=$2;                               shift 2 ;;
        --location)    location=$2;                             shift 2 ;;
        --region)      region=$2;                               shift 2 ;;
        --volume)      volume=$2;                               shift 2 ;;
        --size)        size=$2;                                 shift 2 ;;
        --user)        user=$2;                                 shift 2 ;;
        --cert)        cert=$2;                                 shift 2 ;;
        --key)         key=$2;                                  shift 2 ;;
        --akey)        akey=$2;                                 shift 2 ;;
        --skey)        skey=$2;                                 shift 2 ;;
        --sshk)        sshk=$2;                                 shift 2 ;;
	*)             echo "$0: Unrecognized option: $1" >&2;  exit 1;

    esac
done

#------------------------------------------------------------------------------
# Required and default parameters:
#------------------------------------------------------------------------------

true ${arch[0]:?} \
     ${timezone:="Europe/Madrid"} \
     ${locale:=en_US} \
     ${charmap:=UTF-8} \
     ${imgdir:=/tmp/ami} \
     ${bucket:?} \
     ${location:?} \
     ${region:?} \
     ${size:=1024} \
     ${user:?} \
     ${cert:?} \
     ${key:?} \
     ${akey:?} \
     ${skey:?} \
     ${sshk:?}

#------------------------------------------------------------------------------
# Argument validation:
#------------------------------------------------------------------------------

case ${arch[0]} in

    'i686')   arch[1]='i386'; arch[2]='32'

              case $region in

                  'us-east-1') aki='aki-b6aa75df';;
                  'us-west-1') aki='aki-f57e26b0';;
                  'eu-west-1') aki='aki-75665e01';;

                  *) echo "${0}: Unrecognized --region ${region}" >&2; exit 1;

              esac
              ;;

    'x86_64') arch[1]='x86_64'; arch[2]='64'

              case $region in

                  'us-east-1') aki='aki-88aa75e1';;
                  'us-west-1') aki='aki-f77e26b2';;
                  'eu-west-1') aki='aki-71665e05';;

                  *) echo "${0}: Unrecognized --region ${region}" >&2; exit 1;

              esac
              ;;

    *) echo "${0}: Unrecognized --arch ${arch[0]}" >&2; exit 1;

esac

#------------------------------------------------------------------------------
# Report:
#------------------------------------------------------------------------------

clear; echo
echo Build system
echo ------------
echo
echo -e arch:"\t\t$(uname -m)"
echo -e imgdir:"\t\t${imgdir}"
echo
echo Target system
echo -------------
echo
echo -e arch:"\t\t${arch[0]}"
echo -e timezone:"\t${timezone}"
echo -e locale:"\t\t${locale}"
echo -e charmap:"\t${charmap}"
echo -e size:"\t\t${size}"
echo
echo Amazon EC2
echo ----------
echo
echo -e user:"\t\t${user}"
echo -e cert:"\t\t$(basename ${cert})"
echo -e key:"\t\t$(basename ${key})"
echo -e bucket:"\t\t${bucket}"
echo -e location:"\t${location}"
echo -e region:"\t\t${region}"
echo; sleep 2

#------------------------------------------------------------------------------
# Environment:
#------------------------------------------------------------------------------

export EC2_HOME=/usr/local/ec2/apitools
export JAVA_HOME=/usr/java/default
export PATH=$PATH:$EC2_HOME/bin

#------------------------------------------------------------------------------
# Create a file to host the AMI. Make and mount the root file system:
#------------------------------------------------------------------------------

image=${imgdir}/base; mkdir -p ${image}
dd if=/dev/zero of=${image}.fs bs=1M count=${size}
mke2fs -F -j -t ext4 ${image}.fs
mount -o loop ${image}.fs ${image}

#------------------------------------------------------------------------------
# Populate /dev, /etc, /proc, /var, /boot, /mnt with a minimal set of files:
#------------------------------------------------------------------------------

mkdir -p ${image}/proc
mkdir -p ${image}/etc
mkdir -p ${image}/var/lib/rpm
mkdir -p ${image}/var/log
mkdir -p ${image}/etc/ec2
mkdir -p ${image}/boot/grub
mkdir -p ${image}/mnt/vol1

touch ${image}/var/log/yum.log; chmod 600 ${image}/var/log/yum.log
touch ${image}/etc/mtab; chmod 644 ${image}/etc/mtab

for i in console null zero urandom; do /sbin/MAKEDEV -d ${image}/dev -x ${i}; done
mount -t proc none ${image}/proc

#------------------------------------------------------------------------------
# Create the fstab file within the /etc directory. Do it before you run YUM
# or some packages will complain:
#------------------------------------------------------------------------------

cat << EOF > ${image}/etc/fstab
/dev/xvde1              /                       ext4    defaults       1 1
none                    /dev/pts                devpts  gid=5,mode=620 0 0
none                    /dev/shm                tmpfs   defaults       0 0
none                    /proc                   proc    defaults       0 0
none                    /sys                    sysfs   defaults       0 0
/dev/xvde2              /mnt/vol1               ext4    defaults       0 0
/dev/xvde3              swap                    swap    defaults       0 0
EOF

chmod 644 ${image}/etc/fstab

#------------------------------------------------------------------------------
# Install centos-release package wich contains YUM repos configuration files.
# $releasever and $basearch are determined within the chrooted environment so
# we must ensure to have enough context:
#------------------------------------------------------------------------------

setarch ${arch[0]} rpm --root ${image} --initdb
curl -L -o /tmp/temp.rpm "http://sunsite.rediris.es/mirror/CentOS/6.4/os/${arch[1]}/Packages/centos-release-6-4.el6.centos.10.${arch[0]}.rpm"
setarch ${arch[0]} rpm --nosignature --root ${image} -ivh --nodeps /tmp/temp.rpm
rm -rf /tmp/temp.rpm

#------------------------------------------------------------------------------
# Install the core operating system and its kernel:
#------------------------------------------------------------------------------

setarch ${arch[0]} yum --nogpgcheck --installroot=${image} -y groupinstall Core
setarch ${arch[0]} yum --nogpgcheck --installroot=${image} -y install kernel
setarch ${arch[0]} chroot ${image} yum -y clean all
setarch ${arch[0]} rm -f ${image}/var/lib/rpm/__db*
setarch ${arch[0]} rpm --root ${image} --rebuilddb

#------------------------------------------------------------------------------
# Setup grub:
#------------------------------------------------------------------------------

kernel=`/bin/basename ${image}/boot/vmlinuz*`
ramdisk=`/bin/basename ${image}/boot/initramfs*`

cat << EOF > ${image}/boot/grub/menu.lst
default 0
timeout 0
title CentOS
root (hd0)
kernel /boot/${kernel} ro root=/dev/xvde1 rd_NO_PLYMOUTH
initrd /boot/${ramdisk}
EOF

#------------------------------------------------------------------------------
# Install Amazon EC2 API tools:
#------------------------------------------------------------------------------

curl -L -o "${image}/tmp/ec2-api-tools.zip" "http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip"
unzip ${image}/tmp/ec2-api-tools.zip -d ${image}/usr/local/ec2
ln -s ec2-api-tools-1.5.2.4 ${image}/usr/local/ec2/apitools
rm -rf ${image}/tmp/ec2-api-tools.zip

#------------------------------------------------------------------------------
# Install Amazon EC2 AMI tools:
#------------------------------------------------------------------------------

curl -L -o "${image}/tmp/temp.rpm" "https://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.noarch.rpm"
setarch ${arch[0]} yum --nogpgcheck --installroot=${image} -y install ${image}/tmp/temp.rpm
rm -rf ${image}/tmp/temp.rpm

#------------------------------------------------------------------------------
# Timezone, locale and charmap setup:
#------------------------------------------------------------------------------

setarch ${arch[0]} chroot ${image} cp /usr/share/zoneinfo/${timezone} /etc/localtime
setarch ${arch[0]} chroot ${image} localedef -c --inputfile=${locale} --charmap=${charmap} ${locale}.${charmap}

#------------------------------------------------------------------------------
# Configure network:
#------------------------------------------------------------------------------

cat << EOF > ${image}/etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

chmod 644 ${image}/etc/sysconfig/network

cat << EOF > ${image}/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=yes
PEERDNS=yes
IPV6INIT=no
EOF

chmod 644 ${image}/etc/sysconfig/network-scripts/ifcfg-eth0

#------------------------------------------------------------------------------
# Configure on-boot services:
#------------------------------------------------------------------------------

services=`setarch ${arch[0]} chroot ${image} chkconfig --list | grep '3:on' | awk '{print $1}'`
for i in ${services}; do setarch ${arch[0]} chroot ${image} chkconfig ${i} off; done

services='crond iptables network rsyslog sshd'
for i in ${services}; do setarch ${arch[0]} chroot ${image} chkconfig ${i} on; done

#------------------------------------------------------------------------------
# Authorized ssh keys:
#------------------------------------------------------------------------------

mkdir ${image}/root/.ssh
chmod 700 ${image}/root/.ssh
cat ${sshk} >> ${image}/root/.ssh/authorized_keys
chmod 600 ${image}/root/.ssh/authorized_keys

#------------------------------------------------------------------------------
# Sync and umount:
#------------------------------------------------------------------------------

sync; sync; sync
umount -l ${image}/proc
umount -d ${image}

#------------------------------------------------------------------------------
# ec2-bundle-image:
#------------------------------------------------------------------------------

mkdir ${image}-bundle

ec2-bundle-image \
-r ${arch[1]} \
-u ${user} \
-i ${image}.fs \
-k ${key} \
-c ${cert} \
--kernel ${aki} \
-d ${image}-bundle

#------------------------------------------------------------------------------
# ec2-upload-bundle:
#------------------------------------------------------------------------------

ec2-upload-bundle \
-b ${bucket} \
-m ${image}-bundle/base.fs.manifest.xml \
-a ${akey} \
-s ${skey} \
--location ${location}

#------------------------------------------------------------------------------
# ec2-register:
#------------------------------------------------------------------------------

ec2-register \
-K ${key} \
-C ${cert} \
-n "CentOS 6 ${arch[2]}bit" \
--region ${region} \
--kernel ${aki} \
${bucket}/base.fs.manifest.xml
