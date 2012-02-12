#!/bin/bash

#------------------------------------------------------------------------------
# ./myami.sh \
# --arch x86_64 \
# --bucket base \
# --location EU \
# --size 768 \
# --user xxxxxxxxxx \
# --cert /etc/pki/ec2/my.cert \
# --key /etc/pki/ec2/my.key \
# --akey yyyyyyyyyy \
# --skey zzzzzzzzzz
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Command line sanity check and argument control:
#------------------------------------------------------------------------------

set -e

while [ $# -gt 0 ]; do

    case $1 in

        --arch)        arch=$2;                                 shift 2 ;;
        --timezone)    timezone=$2;                             shift 2 ;;
        --locale)      locale=$2;                               shift 2 ;;
        --charmap)     charmap=$2;                              shift 2 ;;
        --imgdir)      imgdir=$2;                               shift 2 ;;
        --bucket)      bucket=$2;                               shift 2 ;;
        --location)    location=$2;                             shift 2 ;;
        --volume)      volume=$2;                               shift 2 ;;
        --size)        size=$2;                                 shift 2 ;;
        --user)        user=$2;                                 shift 2 ;;
        --cert)        cert=$2;                                 shift 2 ;;
        --key)         key=$2;                                  shift 2 ;;
        --akey)        akey=$2;                                 shift 2 ;;
        --skey)        skey=$2;                                 shift 2 ;;
	*)             echo "$0: Unrecognized option: $1" >&2;  exit 1;

    esac
done

#------------------------------------------------------------------------------
# Required and default parameters:
#------------------------------------------------------------------------------

true ${arch:?} \
     ${timezone:="Europe/Madrid"} \
     ${locale:=en_US} \
     ${charmap:=UTF-8} \
     ${imgdir:=/tmp/ami} \
     ${bucket:?} \
     ${location:?} \
     ${size:=2048} \
     ${user:?} \
     ${cert:?} \
     ${key:?} \
     ${akey:?} \
     ${skey:?}

case $arch in
    i386|x86_64);;
    *)echo "${0}: Unrecognized --arch ${arch}" >&2; exit 1;
esac

case $location in
    EU|US);;
    *)echo "${0}: Unrecognized --location ${location}" >&2; exit 1;
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
echo -e arch:"\t\t${arch}"
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
echo; sleep 2

#------------------------------------------------------------------------------
# Environment:
#------------------------------------------------------------------------------

export EC2_HOME=/usr/local/ec2/apitools
export JAVA_HOME=/etc/alternatives/jre
export PATH=$PATH:$EC2_HOME/bin

#------------------------------------------------------------------------------
# Create a file to host the AMI and make and mount the root file system:
#------------------------------------------------------------------------------

image=${imgdir}/${bucket}; mkdir -p ${image}
dd if=/dev/zero of=${image}.fs bs=1M count=${size}
mke2fs -F -j -t ext4 ${image}.fs
mount -o loop ${image}.fs ${image}

#------------------------------------------------------------------------------
# Populate /dev, /etc, /proc, /var with a minimal set of files:
#------------------------------------------------------------------------------

mkdir -p ${image}/proc
mkdir -p ${image}/etc
mkdir -p ${image}/var/lib/rpm
mkdir -p ${image}/var/log
mkdir -p ${image}/etc/ec2

touch ${image}/var/log/yum.log; chmod 600 ${image}/var/log/yum.log
touch ${image}/etc/mtab; chmod 644 ${image}/etc/mtab

for i in console null zero; do /sbin/MAKEDEV -d ${image}/dev -x ${i}; done
mount -t proc none ${image}/proc

#------------------------------------------------------------------------------
# Create the fstab file within the /etc directory. Do it before you run yum
# or some packages will complain:
#------------------------------------------------------------------------------

cat << EOF > ${image}/etc/fstab
/dev/sda1               /                       ext4    defaults 1 1
none                    /dev/pts                devpts  gid=5,mode=620 0 0
none                    /dev/shm                tmpfs   defaults 0 0
none                    /proc                   proc    defaults 0 0
none                    /sys                    sysfs   defaults 0 0
/dev/sda2               /mnt                    ext4    defaults 1 2
/dev/sda3               swap                    swap    defaults 0 0
EOF

chmod 644 ${image}/etc/fstab

#------------------------------------------------------------------------------
# $releasever and $basearch are determined within the chrooted environment so
# we must ensure to have enough context:
#------------------------------------------------------------------------------

setarch ${arch} rpm --root ${image} --initdb
curl -L -o /tmp/temp.rpm "http://sunsite.rediris.es/mirror/CentOS/6.2/os/${arch}/Packages/centos-release-6-2.el6.centos.7.${arch}.rpm"
setarch ${arch} rpm --nosignature --root ${image} -ivh --nodeps /tmp/temp.rpm
rm -rf /tmp/temp.rpm

#------------------------------------------------------------------------------
# Install the core operating system:
#------------------------------------------------------------------------------

setarch ${arch} yum --nogpgcheck --installroot=${image} -y groupinstall Core
setarch ${arch} rpm --root ${image} --rebuilddb
setarch ${arch} chroot ${image} yum -y clean all

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
setarch ${arch} yum --nogpgcheck --installroot=${image} -y install ${image}/tmp/temp.rpm
rm -rf ${image}/tmp/temp.rpm

#------------------------------------------------------------------------------
# Timezone, locale and charmap setup:
#------------------------------------------------------------------------------

setarch ${arch} chroot ${image} cp /usr/share/zoneinfo/${timezone} /etc/localtime
setarch ${arch} chroot ${image} localedef -c --inputfile=${locale} --charmap=${charmap} ${locale}.${charmap}

#------------------------------------------------------------------------------
# Xen specific instructions:
#------------------------------------------------------------------------------

cat << EOF > ${image}/etc/ld.so.conf.d/libc6-xen.conf
hwcap 0 nosegneg
EOF

chmod 644 ${image}/etc/ld.so.conf.d/libc6-xen.conf
setarch ${arch} chroot ${image} ldconfig
rm -f ${image}/etc/event.d/tty[2-6]

#------------------------------------------------------------------------------
# Configure /etc/sysconfig/network-scripts/ifcfg-eth0:
#------------------------------------------------------------------------------

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
# Put the ssh key in place:
#------------------------------------------------------------------------------

mkdir ${image}/root/.ssh
chmod 700 ${image}/root/.ssh

cat << EOF > ${image}/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC29B/tSPPlRaoAVhUDHHosg2AyGsTEP8w6MMNzNbZiR6XS++WxPWDUrYGIsBx1ESIPkbsbyT77L6zuH8DgN+IuuPbWBUxqEr3/Tba96guaiwSbKYGf1v7CpPNQeGJNvflqZsn4JnJDXKvjuAvEUGLiSr3us9i/uEN7+7kU1MMzCZDxVb+0INeKRquge/FnQveAHVEGzJGEEPKOIQu5y1nl8/qS8KyaDz0XBM2CM2VjqWXqEPKGDQJtjK4n28JBvSOBBwUDGzXi/qmbDPSFjOmxDRB48JXQ+ywZca9pbph/o+JmdCirgOIpn0LKrxodNOSWUkn2islkZkpY6/cS5hi3 popapp
EOF

chmod 600 ${image}/root/.ssh/authorized_keys

#------------------------------------------------------------------------------
# Sync and umount:
#------------------------------------------------------------------------------

sync
umount -l ${image}/proc
umount -d ${image}

#------------------------------------------------------------------------------
# ec2-bundle-image:
#------------------------------------------------------------------------------

mkdir ${image}-bundle

ec2-bundle-image \
-r ${arch} \
-u ${user} \
-i ${image}.fs \
-k ${key} \
-c ${cert} \
-d ${image}-bundle

#------------------------------------------------------------------------------
# ec2-upload-bundle:
#------------------------------------------------------------------------------

ec2-upload-bundle \
-b ${bucket} \
-m ${image}-bundle/${bucket}.fs.manifest.xml \
-a ${akey} \
-s ${skey} \
--location ${location}

#------------------------------------------------------------------------------
# ec2-register:
#------------------------------------------------------------------------------

ec2-register \
-K ${key} \
-C ${cert} \
-n "CentOS 6 Core" \
${bucket}/${bucket}.fs.manifest.xml
