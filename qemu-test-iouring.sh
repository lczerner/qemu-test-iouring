#!/bin/bash

SUPPORTED_ARCH="x86_64 ppc64le"
TOOL=$0

usage() {
	echo "Usage: $TOOL [-h] [-n] [-d] [-c] [-a ARCH] [-I IMG] [-r REPO]"
	echo "	-h		Print this help"
	echo "	-a ARCH		Specify architecture to run (default: x86_64)."
	echo "			Supported: $SUPPORTED_ARCH"
	echo "	-I IMG		Image to run with. Must be specified."
	echo "	-r REPO		Specify yum repository file to include in guest."
	echo "			Can be repeated to include multiple files and"
	echo "			implies image initialization."
	echo "	-n		Do not initialize the image with virt-sysprep"
	echo "	-d		Do not run liburing tests on startup. Implies"
	echo "			image initialization."
	echo "	-c		Do not run on specified image, but rather create"
	echo "			copy of it first."
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

# Set default options
GUEST_DIR="./guest"
GUEST_TEST="/root/$(basename $GUEST_DIR)/runtest.sh"
GUEST_LOG="/root/test.log"
COPY_IN="--copy-in $GUEST_DIR:/root"
REPO_DIR="/etc/yum.repos.d/"
ARCH="x86_64"
INIT=1
RC_LOCAL_MODE="0700"
COPY_IMG=0

# Parse options
while getopts "ha:dr:I:nc" option; do
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
	*)
		error "Unrecognized option \"$option\""
		;;
	esac
done

[ -e "$IMG" ] || error "Image must be specified"

printf "ARCH\t\t${ARCH}\n"
printf "IMG\t\t${IMG}\n"
printf "RC_LOCAL_MODE\t${RC_LOCAL_MODE}\n"
printf "INIT\t\t${INIT}\n"
printf "COPY IMAGE\t${COPY_IMG}\n"
printf "COPY_IN\t\t${COPY_IN}\n"

# Copy the image and run on the copy instead
if [ "$COPY_IMG" == "1" ]; then
	live_img="${IMG}.live"
	cp --force $IMG $live_img || error "Copying image"
	IMG=$live_img
fi

[ -e "$IMG" ] || error "Image must be specified"

# Prepare the image
if [ "$INIT" == "1" ]; then
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
		qemu-system-x86_64 -enable-kvm -m 8192 -smp 12 -cpu host -drive format=qcow2,index=0,if=virtio,file=$IMG -drive file=/dev/fedora_fs-i40c-06/nvme1,if=none,id=D22,format=raw -device nvme,drive=D22,serial=1234 -nographic
		;;
	ppc64le)
		qemu-system-ppc64 -M pseries-5.1 -m 8192 -smp 8 -drive format=qcow2,index=0,if=virtio,file=$IMG -drive file=/dev/fedora_fs-i40c-06/nvme2,if=none,id=D22,format=raw -device nvme,drive=D22,serial=1234 -nographic
		;;
	*)
		error "Unsupported architecture \"$ARCH\""
		;;
esac
