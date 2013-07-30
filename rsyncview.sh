#!/bin/sh

#------------------------------------------------------------------------------
# Definitions:
#------------------------------------------------------------------------------

LOGDIR='/var/log/cobbler'
REPDIR='/var/www/cobbler/repo_mirror'

#------------------------------------------------------------------------------
# Sync one repo at a time:
#------------------------------------------------------------------------------

for i in `cobbler repo list`; do echo -n "$i:"

    # Initialize the log:
    LOGFILE="${LOGDIR}/reposync_${i}.log"
    echo -e "\n-------------------------------\n `date` \
    \n-------------------------------\n" >> $LOGFILE

    # Do the real stuff:
    cobbler reposync --only="${i}" >> $LOGFILE
    repoview -t $i $REPDIR/$i > /dev/null 2>&1

    # Column aligned report:
    len=`echo ${#i}`; let off=55-$len
    REP=`tail $LOGFILE | grep 'TASK'`; printf '%*s%s\n' $off "$REP"

done
