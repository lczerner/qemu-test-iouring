#!/bin/bash

SUPPORTED_ARCH="x86_64 ppc64le"
CONFIG_FILE="./local.config"
TOOL=$0

usage() {
	echo "Usage: $TOOL [-h] [-n] [-d] [-c] [-a ARCH] [-I IMG] [-r REPO] [-N NVME]"
	echo "	-h		Print this help"
	echo "	-a ARCH		Specify architecture to run (default: x86_64)."
	echo "			Supported: $SUPPORTED_ARCH"
	echo "	-I IMG		OS image with Fedora, Centos or Rhel. Must"
	echo "			be specified."
	echo "	-N NVME		Nvme image to run on. It needs to be at least"
	echo "			1GB in size."
	echo "	-r REPO		Specify yum repository file to include in guest."
	echo "			Can be repeated to include multiple files and"
	echo "			implies image initialization."
	echo "	-n		Do not initialize the image with virt-sysprep"
	echo "	-d		Do not run liburing tests on startup. Implies"
	echo "			image initialization."
	echo "	-c		Do not run on specified image, but rather create"
	echo "			copy of it first."
	echo "	-e		Exclude test. Can be repeated to exclude"
	echo "			multiple tests."
	echo ""
	echo "Example: ./$TOOL -a ppc64le -r test.repo -c -I fedora.img -N nvme.img"
}

error() {
	printf "ERROR $TOOL: $@!\n\n"
	usage
	exit 1
}

test_arch() {
	[ -z "$1" ] && error "Architecture not specified"
	echo $SUPPORTED_ARCH | grep -w $1 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		error "\"$1\" is not supported architecture"
	fi
}

test_img() {
	[ -z "$1" ] && error "Image not specified"
	if [ ! -e "$1" ]; then
		error "\"$1\" does not exist"
	fi
}

test_reg_file() {
	[ -z "$1" ] && error "File not specified"
	if [ ! -f "$1" ]; then
		error "\"$1\" does not exist"
	fi
}

check_util()
{
	local util=$1
	command -v $util > /dev/null 2>&1 || error "Required utility \"$util\" is not found"
}

# Check for required utilities
check_util truncate
check_util virt-sysprep
check_util qemu-system-x86_64
check_util qemu-system-ppc64

# Set default options
GUEST_DIR="./guest"
GUEST_TEST="/root/$(basename $GUEST_DIR)/runtest.sh"
GUEST_LOG="/root/test.log"
COPY_IN_GUEST="--copy-in $GUEST_DIR:/root"
COPY_IN=""
REPO_DIR="/etc/yum.repos.d/"
ARCH="x86_64"
IMG_INIT=1
RC_LOCAL_MODE="0700"
COPY_IMG=0
EXCLUDE_TEST=""

# Load configuration
[ -f "$CONFIG_FILE" ] && . $CONFIG_FILE

# Update the options based on configuration
COPY_IN="$COPY_IN $COPY_IN_GUEST"


# Parse options
while getopts "ha:dr:I:ncN:e:" option; do
	case $option in
	h)
		usage; exit 0
		;;
	a)
		test_arch $OPTARG
		ARCH=$OPTARG
		;;
	n)
		INIT=0
		;;
	r)
		test_reg_file $OPTARG
		COPY_IN="$COPY_IN --copy-in $OPTARG:$REPO_DIR"
		INIT=1
		;;
	I)
		test_img $OPTARG
		IMG=$OPTARG
		;;
	d)
		RC_LOCAL_MODE="0600"
		INIT=1
		;;
	c)
		COPY_IMG=1
		;;
	N)
		test_img $OPTARG
		NVME_IMG=$OPTARG
		;;
	e)
		EXCLUDE_TEST="$EXCLUDE_TEST $OPTARG"
		;;
	*)
		error "Unrecognized option \"$option\""
		;;
	esac
done

# Create nvme image if one was not provided
if [ ! -e "$NVME_IMG" ]; then
	NVME_IMG=$(mktemp)
	truncate -s1G $NVME_IMG || error "Fallocate \"$NVME_IMG\""
fi

[ -e "$IMG" ] || error "Image must be specified"
[ -e "$NVME_IMG" ] || error "Nvme image must be specified"

# Print options
printf "ARCH\t\t${ARCH}\n"
printf "IMG\t\t${IMG}\n"
printf "RC_LOCAL_MODE\t${RC_LOCAL_MODE}\n"
printf "INIT\t\t${INIT}\n"
printf "COPY IMAGE\t${COPY_IMG}\n"
printf "COPY_IN\t\t${COPY_IN}\n"
printf "EXCLUDE_TEST\t${EXCLUDE_TEST}\n"

# Copy the image and run on the copy instead
if [ "$COPY_IMG" == "1" ]; then
	live_img="${IMG}.live"
	cp --force $IMG $live_img || error "Copying image"
	IMG=$live_img
fi

[ -e "$IMG" ] || error "Image must be specified"

# Setup the configuration for the test in guest
echo "EXCLUDE_TEST=\"$EXCLUDE_TEST\"" > $GUEST_DIR/local.config

# Prepare the image
if [ "$IMG_INIT" == "1" ]; then
	virt-sysprep -a $IMG --root-password password:root \
		$COPY_IN \
		--write /etc/modprobe.d/nvme.conf:"options nvme poll_queues=4" \
		--append-line /etc/rc.local:"/bin/bash -c '$GUEST_TEST > $GUEST_LOG 2>&1' &" \
		--chmod $RC_LOCAL_MODE:/etc/rc.local \
		|| exit 1
fi

# Run the qemu and test
case $ARCH in
	x86_64)
		qemu-system-x86_64 -enable-kvm -m 8192 -smp 12 -cpu host -drive format=qcow2,index=0,if=virtio,file=$IMG -drive file=$NVME_IMG,if=none,id=D22,format=raw -device nvme,drive=D22,serial=1234 -nographic
		;;
	ppc64le)
		qemu-system-ppc64 -M pseries-5.1 -m 8192 -smp 8 -drive format=qcow2,index=0,if=virtio,file=$IMG -drive file=$NVME_IMG,if=none,id=D22,format=raw -device nvme,drive=D22,serial=1234 -nographic
		;;
	*)
		error "Unsupported architecture \"$ARCH\""
		;;
esac
