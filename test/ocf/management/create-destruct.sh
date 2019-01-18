#!/usr/bin/env bash

curdir=$(dirname $(readlink -f "$BASH_SOURCE"))
rootdir=$(readlink -f $curdir/../../..)
source $rootdir/test/common/autotest_common.sh

rpc_py=$rootdir/scripts/rpc.py

function bdev_check_claimed()
{
       if $($rpc_py get_bdevs -b "$@" | jq '.[0].claimed'); then
               return 0;
       else
               return 1;
       fi
}

$rootdir/app/iscsi_tgt/iscsi_tgt &
spdk_pid=$!

trap "killprocess $spdk_pid; exit 1" SIGINT SIGTERM EXIT

waitforlisten $spdk_pid

$rpc_py construct_malloc_bdev 101 512 -b Malloc0
$rpc_py construct_malloc_bdev 101 512 -b Malloc1

$rpc_py construct_ocf_bdev PartCache wt Malloc0 NonExisting

if ! bdev_check_claimed Malloc0; then
	>&2 echo "Base device expected to be claimed now"
	exit 1
fi

$rpc_py delete_ocf_bdev PartCache
if bdev_check_claimed Malloc0; then
	>&2 echo "Base device is not expected to be claimed now"
	exit 1
fi

$rpc_py construct_ocf_bdev FullCache wt Malloc0 Malloc1

if ! (bdev_check_claimed Malloc0 && bdev_check_claimed Malloc1); then
	>&2 echo "Base devices expected to be claimed now"
	exit 1
fi

$rpc_py delete_ocf_bdev FullCache
if bdev_check_claimed Malloc0 && bdev_check_claimed Malloc1; then
	>&2 echo "Base devices are not expected to be claimed now"
	exit 1
fi

$rpc_py construct_ocf_bdev HotCache wt Malloc0 Malloc1

if ! (bdev_check_claimed Malloc0 && bdev_check_claimed Malloc1); then
	>&2 echo "Base devices expected to be claimed now"
	exit 1
fi

$rpc_py delete_malloc_bdev Malloc0

if bdev_check_claimed Malloc1; then
	>&2 echo "Base device is not expected to be claimed now"
	exit 1
fi

status=$($rpc_py get_bdevs)
gone=$(echo $status | jq 'map(select(.name == "HotCache")) == []')
if [[ $gone == false ]]; then
	>&2 echo "OCF bdev is expected to unregister"
	exit 1
fi

# check if shutdown of running CAS bdev is ok
$rpc_py construct_ocf_bdev PartCache wt NonExisting Malloc1

trap - SIGINT SIGTERM EXIT

killprocess $spdk_pid
