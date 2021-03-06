#!/bin/sh
#
# $Id$
#
# Created 2017/11/26
# Author: Mike Ovsiannikov
#
# Copyright 2017 Quantcast Corporation. All rights reserved.
#
# This file is part of Kosmos File System (KFS).
#
# Licensed under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
# QFS fuse test.
#

set -e

myfs=${1-'127.0.0.1:20000'}
myfuseopt=${2-'rrw,create=S'}
mytestfilesize=${3-`expr 1024 \* 1024 \* 1`}
mytesruns=${4-2}
mytestfiles=${5-3}
mytf=${6-'qfs_fuse_test.data'}
mymnt=${7-"`pwd`/qfs_fuse_mnt"}
myfuseumount=${8-'fusermount -u'}
myfuselog=${9-'qfs_fuse.log'}

if [ x"$7" = x ]; then
    if fusermount -V >/dev/null 2>&1; then
        true
    else
        myfuseumount='umount'
    fi
fi

myfusebuilddir="`pwd`/src/cc/fuse"
if [ -d "$myfusebuilddir" ]; then
    PATH="$myfusebuilddir:$PATH"
    export PATH
fi

qfs_fuse -h > /dev/null 2>&1

mysha1()
{
    openssl sha1 "$1" | awk '{print $2}'
}

mytd="$mymnt/fusetest"
mkdir -p "$mymnt"
if [ -e "$mytf" ]; then
    true
else
    openssl rand -out "$mytf" $mytestfilesize
fi
mytestchksum=`mysha1 "$mytf"`
if mount | grep "$mymnt" > /dev/null; then
    mypid=
    true
else
    QFS_CLIENT_LOG_LEVEL=DEBUG qfs_fuse -f \
        "$myfs" "$mymnt" -o "$myfuseopt" > "$myfuselog" 2>&1 &
    mypid=$!
    i=0
    set +e
    until mount | grep "$mymnt" > /dev/null; do
        if kill -0 $mypid > /dev/null 2>&1; then
            true
        else
            wait "$mypid"
            status=$?
            tail "$myfuselog"
            echo "QFS $myfs fuse mount exited, status: $status" 1>&2
            exit 1
        fi
        if [ $i -gt 15 ]; then
            tail "$myfuselog"
            echo "QFS $myfs fuse mount wait timedout" 1>&2
            exit 1
        fi
        i=`expr $i + 1`
        sleep 1
    done
    set -e
    trap '$myfuseumount "$mymnt"; exit 1' EXIT INT
fi
df -h "$mymnt"
mkdir -p "$mytd"
mydu='du -bhs'
if $mydu "$myfuselog" >/dev/null 2>&1; then
    true
else
    mydu='du -hs'
fi
k=0
while [ $k -lt $mytesruns ]; do
    i=0
    while [ $i -lt $mytestfiles ] ; do
        myfname="$mytd/test.$i.data"
        cp "$mytf" "$myfname"
        i=`expr $i + 1`
        # ps -o vsize,size,rss,args $mypid
    done
    i=0
    while [ $i -lt $mytestfiles ] ; do
        myfname="$mytd/test.$i.data"
        ls -l "$myfname"
        curchk=`mysha1 "$myfname"`
        if [ x"$mytestchksum" = x"$curchk" ]; then
            true
        else
            echo "Test failure: $myfname: checksum mismatch:" \
                " $curchk expected  $mytestchksum" 1>&2
            exit 1
        fi
        i=`expr $i + 1`
    done
    $mydu "$mytd"
    k=`expr $k + 1`
done
df -h "$mymnt"
$myfuseumount "$mymnt"
trap '' EXIT INT
if [ x"$mypid" = x ]; then
    exit 0
fi
wait "$mypid"
status=$?
if [ $status -eq 0 ]; then
    echo "Passed test."
else
    echo "Test failed: exit status $status"
fi
exit "$status"
