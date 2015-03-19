#!/bin/bash

# Written by Stephen Fromm <sfromm nero net>
# (C) 2011-2012 University of Oregon
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.

TMPFILE=`mktemp /tmp/gnt-cluster-verify.XXXXXX || exit 1`
LOG="/tmp/gnt-cluster-verify-$(date '+%FT%T').log"
STATUS_FILE="/var/run/gnt-cluster-verify-status"
RCPT="root@localhost"
SUBJECT="Ganeti cluster verify error $(date '+%FT%T')"
USER=$(id -u)
PID_FILE="/var/run/ganeti/ganeti-masterd.pid"
MASTERD='ganeti-masterd'
PATH="/usr/sbin:/sbin:$PATH"
JOB_SUMMARY="CLUSTER_VERIFY CLUSTER_VERIFY_CONFIG CLUSTER_VERIFY_GROUP"
export PATH

__check_report() {
    local arg=$1
    local result=0
    result=$(grep $arg ${TMPFILE} | grep -v EINSTANCEBADNODE | wc -l)
    echo $result
    return 0
}

__last_state() {
    local result=0
    if [ -e ${STATUS_FILE} ]; then
        result=$(cat ${STATUS_FILE})
    fi
    echo $result
}

__state() {
    local arg=$1
    echo ${arg} > ${STATUS_FILE}
    chmod 644 ${STATUS_FILE}
}

__bad_state() {
    local arg=$1
    local last=$(__last_state)
    __state $arg
    mv -f ${TMPFILE} ${LOG}
    if [ ${last} -gt 0 ]; then
        return 0
    fi
    chmod go+r ${LOG}
    (
        echo "To: ${RCPT}"
        echo "Subject: ${SUBJECT}"
        echo ""
        cat ${LOG}
        echo ""
        echo "Log preserved as ${LOG}"
    ) | sendmail -t
    return $?
}

__archive_job() {
    local id=''
    local status=''
    local job=''
    local ret=0
    local n=''
    for n in $JOB_SUMMARY ; do
        __maybe_start_master
        gnt-job list | grep -w $n | tail -n 1 | \
            while read id status job; do
                if [ $status == 'success' -a -n "$id" ]; then
                    gnt-job archive $id
                    ret=$?
                    logger -t gnt-cluster-verify -p daemon.notice "Archived job $id - $job $status"
                fi
            done
    done
    return $ret
}

__maybe_start_master() {
    local needs_restart=0
    local line p pid
    if [ ! -e $PID_FILE ]; then
        needs_restart=1
    else
        while : ; do
            read line
            [ -z "$line" ] && break
            for p in $line ; do
                [ -z "${p//[0-9]/}" -a -d "/proc/$p" ] && pid="$pid $p"
            done
        done < "$PID_FILE"

        if [ -n "$pid" ]; then
            needs_restart=0
        else
            needs_restart=2 # "Program is dead and /var/run pid file exists"
        fi
    fi
    if [ $needs_restart -ne 0 ]; then
        service ganeti restart $MASTERD > /dev/null 2>&1
        logger -t gnt-cluster-verify -p daemon.notice "Restarted $MASTERD"
        sleep 2
    fi
}

if ! type -p gnt-cluster >/dev/null; then
    echo "Cannot find gnt-cluster command.  Unable to proceed."
    exit 1
fi

if [ "$USER" -ne 0 ]; then
    echo "Must be run as root"
    exit 1
fi

MASTER=$(gnt-cluster getmaster)

if [ "${MASTER}" != "${HOSTNAME}" ]; then
    __state 0
    exit 0
fi

__maybe_start_master

gnt-cluster verify --error-codes >${TMPFILE} 2>&1
RESULT=$?

if [ ${RESULT} -ne 0 ]; then
    __bad_state ${RESULT}
else
    WARN=$(__check_report WARN)
    NODE_ERRORS=$(__check_report ERROR:ENODE)
    INST_ERRORS=$(__check_report ERROR:EINSTANCE)
    if [ "${NODE_ERRORS}" -gt 0 ]; then
        __bad_state ${NODE_ERRORS}
    elif [ "${INST_ERRORS}" -gt 0 ]; then
        __bad_state ${INST_ERRORS}
    else
        __state 0
    fi
fi
__archive_job
rm -f ${TMPFILE}
exit 0
