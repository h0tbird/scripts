#!/bin/sh

#------------------------------------------------------------------------------
# Checking arguments:
#------------------------------------------------------------------------------

if [ $# -ne 1 ]; then

    echo "Usage: `basename $0` [1|2|3|4|5]"
    echo
    echo " 1: Download, mount and rsync the ISO without the RPMs."
    echo " 2: Download the latest version of puppet and the core group of RPMs."
    echo " 3: Generate the repository metadata."
    echo " 4: Inject the kickstart.cfg file into the initrd.img bundle."
    echo " 5: Build the final ISO file."
    echo
    exit
fi

set -e

#------------------------------------------------------------------------------
# Variables:
#------------------------------------------------------------------------------

arch='x86_64'
release='6.2'
iso="CentOS-${release}-${arch}-minimal.iso"
url="http://sunsite.rediris.es/mirror/CentOS/${release}/isos/${arch}/${iso}"
mnt='/mnt/CentOS'
tmp='/tmp/CentOS'

pkg="${tmp}/Packages"
dat="${tmp}/repodata"
isl="${tmp}/isolinux"

#------------------------------------------------------------------------------
# yum.conf
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
exclude=*.i?86\n\
\n\
[puppet1]\n\
name=Puppetlabs Packages - \$basearch\n\
baseurl=http://yum.puppetlabs.com/el/6/products/\$basearch\n\
enabled=1\n\
gpgcheck=1\n\
gpgkey=http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs\n\
\n\
[puppet2]\n\
name=Puppetlabs Dependencies - \$basearch\n\
baseurl=http://yum.puppetlabs.com/el/6/dependencies/\$basearch\n\
enabled=1\n\
gpgcheck=1\n\
gpgkey=http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs"

#------------------------------------------------------------------------------
# puppet.conf
#------------------------------------------------------------------------------

puppet="[main]\n\
\n\
    confdir    = /etc/puppet\n\
    vardir     = /var/lib/puppet\n\
    logdir     = /var/log/puppet\n\
    rundir     = /var/run/puppet\n\
    ssldir     = \\\$vardir/ssl\n\
    pluginsync = true\n\
\n\
[agent]\n\
\n\
    classfile     = \\\$vardir/classes.txt\n\
    localconfig   = \\\$vardir/localconfig\n\
    graphdir      = \\\$vardir/state/graphs\n\
    graph         = true\n\
    factsignore   = .svn CVS .git *.markdown .*.swp\n\
    pluginsignore = .svn CVS .git *.markdown .*.swp\n\
\n\
[master]\n\
\n\
    modulepath = \\\$confdir/modules:\\\$confdir/roles\n\
"

#------------------------------------------------------------------------------
# kickstart.cfg
#------------------------------------------------------------------------------

kickstart="install\n\
text\n\
cdrom\n\
lang en_US.UTF-8\n\
keyboard es\n\
network --device eth0 --bootproto dhcp\n\
rootpw  password\n\
firewall --disabled\n\
authconfig --enableshadow --passalgo=sha512 --enablefingerprint\n\
selinux --disabled\n\
services --disabled auditd,fcoe,ip6tables,iptables,iscsi,iscsid,lldpad,netfs,nfslock,rpcbind,rpcgssd,rpcidmapd,udev-post,lvm2-monitor\n\
timezone --utc Europe/Madrid\n\
bootloader --location=mbr --driveorder=sda --append=\"crashkernel=auto rhgb quiet\"\n\
clearpart --all --drives=sda\n\
ignoredisk --only-use=sda\n\
part /boot --fstype=ext4 --size 200\n\
part pv.0 --grow --size=1\n\
volgroup vg0 --pesize=4096 pv.0\n\
logvol / --fstype=ext4 --name=lv0 --vgname=vg0 --size=2048 --grow --maxsize=5120\n\
%packages --nobase\n\
puppet\n\
%post\n\
sed -i 's/timeout=./timeout=0/' /boot/grub/grub.conf\n\
sed -i 's/ rhgb//' /boot/grub/grub.conf\n\
echo \"91.121.159.192 puppet\" >> /etc/hosts\n\
echo -e \"${puppet}\" > /etc/puppet/puppet.conf\n\
%end\n\
"

#------------------------------------------------------------------------------
# isolinux.cfg
#------------------------------------------------------------------------------

isolinux="default kickstart\n\
\n\
label kickstart\n\
  menu label Kickstart\n\
  kernel vmlinuz\n\
  append ks=file:/kickstart.cfg initrd=initrd.img\n\
"

#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------

case "$1" in

    #-------------------------------------------------
    # Download, mount and rsync the ISO w/o the RPMs:
    #-------------------------------------------------

    1) test -f ${iso} || wget ${url}
       test -d ${mnt} || mkdir -p ${mnt}
       grep -q "${mnt}" /proc/mounts || mount -o loop ${iso} ${mnt}
       rsync -a --delete --exclude="*.rpm" --exclude="*.TBL" --delete-excluded ${mnt}/ ${tmp}/
       ;;

    #-------------------------------------------------------------------
    # Download the latest version of puppet and the core group of RPMs:
    #-------------------------------------------------------------------

    2) echo -e ${yumconf} > /tmp/yum.conf
       grep "mandatory" ${dat}/*minimal*.xml | awk -F '[<|>]' '{print $3}' | xargs repotrack -c /tmp/yum.conf -p ${pkg} puppet
       ;;

    #-----------------------------------
    # Generate the repository metadata:
    #-----------------------------------

    3) mv ${dat}/*minimal*.xml ${dat}/minimal.xml
       find ${dat}/* ! -name minimal.xml -delete
       createrepo --database --unique-md-filenames -g ${dat}/minimal.xml -o ${tmp} ${tmp}
       ;;

    #-----------------------------------------------------------
    # Inject the kickstart.cfg file into the initrd.img bundle:
    #-----------------------------------------------------------

    4) cd ${isl}
       mkdir cpio-initrd; cd cpio-initrd
       xz -d ../initrd.img -c | cpio -id
       echo -e ${kickstart} > kickstart.cfg
       find . | cpio --create --format='newc' > ../initrd
       rm -f ../initrd.img; gzip --suffix .img ../initrd
       cd ..; rm -rf cpio-initrd
       echo -e ${isolinux} > isolinux.cfg
       ;;

    #---------------------------
    # Build the final ISO file:
    #---------------------------

    5) mkisofs -l -J -R -r -T -o /media/sf_shared/boot.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table ${tmp}
       sync
       ;;
esac
