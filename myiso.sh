#!/bin/sh

#------------------------------------------------------------------------------
# Checking arguments:
#------------------------------------------------------------------------------

if [ $# -ne 1 ]; then echo "Usage: `basename $0` [1|2|3|4|5|6]"; exit; fi

set -e

#------------------------------------------------------------------------------
# Variables:
#------------------------------------------------------------------------------

arch='x86_64'
iso="CentOS-6.0-${arch}-minimal.iso"
url="http://sunsite.rediris.es/mirror/CentOS/6.0/isos/${arch}/${iso}"
mnt='/mnt/CentOS'
tmp='/tmp/CentOS'

pkg="${tmp}/Packages"
dat="${tmp}/repodata"
isl="${tmp}/isolinux"

packages="ruby libselinux-ruby augeas-libs"

#------------------------------------------------------------------------------
# kickstart.cfg
#------------------------------------------------------------------------------

kickstart="install\n
text\n
cdrom\n
lang en_US.UTF-8\n
keyboard es\n
network --device eth0 --bootproto dhcp\n
rootpw  password\n
firewall --disabled\n
authconfig --enableshadow --passalgo=sha512 --enablefingerprint\n
selinux --disabled\n
services --disabled auditd,fcoe,ip6tables,iptables,iscsi,iscsid,lldpad,netfs,nfslock,rpcbind,rpcgssd,rpcidmapd,udev-post,lvm2-monitor\n
timezone --utc Europe/Madrid\n
bootloader --location=mbr --driveorder=sda --append=\"crashkernel=auto rhgb quiet\"\n
clearpart --all --drives=sda\n
ignoredisk --only-use=sda\n
part /boot --fstype=ext4 --size 200\n
part pv.0 --grow --size=1\n
volgroup vg0 --pesize=4096 pv.0\n
logvol / --fstype=ext4 --name=lv0 --vgname=vg0 --size=2048 --grow --maxsize=5120\n
%packages --nobase\n
puppet\n
%post\n
sed -i 's/timeout=./timeout=0/' /boot/grub/grub.conf\n
sed -i 's/ rhgb//' /boot/grub/grub.conf\n
echo \"91.121.159.192 puppet\" >> /etc/hosts\n
%end\n"

#------------------------------------------------------------------------------
# isolinux.cfg
#------------------------------------------------------------------------------

isolinux="default kickstart\n
\n
label kickstart\n
  menu label Kickstart\n
  kernel vmlinuz\n
  append ks=file:/kickstart.cfg initrd=initrd.img\n"

#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------

case "$1" in

    #-------------------------------------------------
    # Retrieve, mount and rsync the ISO w/o the RPMs:
    #-------------------------------------------------

    1) test -f ${iso} || wget ${url}
       test -d ${mnt} || mkdir -p ${mnt}
       grep -q "${mnt}" /proc/mounts || mount -o loop ${iso} ${mnt}
       rsync -a --delete --exclude="*.rpm" --exclude="*.TBL" --delete-excluded ${mnt}/ ${tmp}/
       ;;

    #------------------------------------------
    # Retrieve the updated core group of RPMs:
    #------------------------------------------

    2) test -f /tmp/myiso.conf || cp /etc/yum.conf /tmp/myiso.conf
       if [ ${arch} == 'x86_64' ]; then grep -q "^exclude=\*\.i?86$" /tmp/myiso.conf || echo "exclude=*.i?86" >> /tmp/myiso.conf; fi
       grep "mandatory" ${dat}/*minimal*.xml | awk -F '[<|>]' '{print $3}' | xargs repotrack -c /tmp/myiso.conf -p ${pkg} ${packages}
       ;;

    #------------------------------
    # Retrieve puppet client RPMs:
    #------------------------------

    3) test -f ${pkg}/ruby-augeas-0.3.0-1.el6.${arch}.rpm || wget http://yum.puppetlabs.com/el/6/dependencies/${arch}/ruby-augeas-0.3.0-1.el6.${arch}.rpm -P ${pkg}
       test -f ${pkg}/ruby-shadow-1.4.1-13.el6.${arch}.rpm || wget http://yum.puppetlabs.com/el/6/dependencies/${arch}/ruby-shadow-1.4.1-13.el6.${arch}.rpm -P ${pkg}
       test -f ${pkg}/facter-1.6.1-1.el6.noarch.rpm || wget http://yum.puppetlabs.com/el/6/products/${arch}/facter-1.6.1-1.el6.noarch.rpm -P ${pkg}
       test -f ${pkg}/puppet-2.7.5-1.el6.noarch.rpm || wget http://yum.puppetlabs.com/el/6/products/${arch}/puppet-2.7.5-1.el6.noarch.rpm -P ${pkg}
       ;;

    #---------------------------------
    # Create the repository metadata:
    #---------------------------------

    4) mv ${dat}/*minimal*.xml ${dat}/minimal.xml
       find ${dat}/* ! -name minimal.xml -delete
       createrepo --database --unique-md-filenames -g ${dat}/minimal.xml -o ${tmp} ${tmp}
       ;;

    #-----------------------
    # Inject kickstart.cfg:
    #-----------------------

    5) cd ${isl}
       gunzip initrd.img --suffix .img
       mkdir cpio-initrd; cd cpio-initrd
       cpio -id < ../initrd
       echo -e ${kickstart} > kickstart.cfg
       find . | cpio --create --format='newc' > ../initrd
       gzip --suffix .img ../initrd
       cd ..; rm -rf cpio-initrd
       echo -e ${isolinux} > isolinux.cfg
       ;;

    #----------------------
    # Build the final ISO:
    #----------------------

    6) mkisofs -l -J -R -r -T -o /media/sf_shared/boot.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table ${tmp}
       sync
       ;;
esac
