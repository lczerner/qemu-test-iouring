#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

SUPPORTED_ARCH="x86_64 ppc64"
CONFIG_FILE="./config.local"
TOOL=$0

usage() {
	echo "Usage: $TOOL [-h] [-n] [-d] [-c] [-a ARCH] [-I IMG] [-r REPO] [-N NVME]"
	echo "	-h		Print this help"
	echo "	-C CONFIG	Specify custom configuration file. This option"
	echo "			can only be specified once. (Default \"$CONFIG_FILE\")"
	echo "	-a ARCH		Specify architecture to run (default: x86_64)."
	echo "			Supported: $SUPPORTED_ARCH"
	echo "	-I IMG		OS image with Fedora, Centos or Rhel. Can be"
	echo "			existing file, or http(s) url."
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
	echo "	-p PKG		RPM package to install in guest"
	echo ""
	echo "Example: ./$TOOL -a ppc64 -r test.repo -c -I fedora.img -N nvme.img"
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

test_reg_file() {
	[ -z "$1" ] && error "File not specified"
	if [ ! -f "$1" ]; then
		error "\"$1\" does not exist"
	fi
}

check_util()
{
	[ -n "$TEST_DEBUG" ] && return

	local util=$1
	command -v $util > /dev/null 2>&1 || error "Required utility \"$util\" is not found"
}

create_image()
{
	[ -n "$NVME_IMG" ] && return

	NVME_IMG=$(mktemp)
	NVME_CREATED=1
	[ -n "$TEST_DEBUG" ] && return
	truncate -s${NVME_SIZE} $NVME_IMG || error "Fallocate \"$NVME_IMG\""
}

copy_image()
{
	[ "$COPY_IMG" != "1" ] && return
	[ -n "$TEST_DEBUG" ] && return

	local live_img="${IMG}.live"
	cp --force $IMG $live_img || error "Copying image"
	IMG=$live_img
}

initialize_image()
{
	[ "$IMG_INIT" != "1" ] && return
	[ -n "$TEST_DEBUG" ] && return

	virt-sysprep -a $IMG --root-password password:root \
		$CREATE_DIR \
		$COPY_IN \
		--mkdir $GUEST_LOG_DIR \
		--edit '/etc/sysconfig/selinux:s/^SELINUX=.*/SELINUX=disabled/' \
		--write /etc/modprobe.d/nvme.conf:"options nvme poll_queues=4" \
		--append-line $GUEST_RC_LOCAL:"/bin/bash -c '$GUEST_TEST > $GUEST_LOG 2>&1' &" \
		--write $GUEST_RC_LOCAL:"#!/bin/bash
$GUEST_TEST >> $GUEST_LOG 2>&1 &" \
		--chmod $RC_LOCAL_MODE:$GUEST_RC_LOCAL \
		|| error "virt-sysprep failed"
}

run_x86_64()
{
	[ -n "$TEST_DEBUG" ] && return

	qemu-system-x86_64 -enable-kvm -m $GUEST_MEMORY -smp $GUEST_CPUS \
		-cpu host -drive format=qcow2,index=0,if=virtio,file=$IMG \
		-drive file=$NVME_IMG,if=none,id=D22,format=raw \
		-device nvme,drive=D22,serial=1234 \
		-nographic
}

run_ppc64()
{
	[ -n "$TEST_DEBUG" ] && return

	qemu-system-ppc64 -M pseries-5.1 -m $GUEST_MEMORY -smp $GUEST_CPUS \
		-drive format=qcow2,index=0,if=virtio,file=$IMG \
		-drive file=$NVME_IMG,if=none,id=D22,format=raw \
		-device nvme,drive=D22,serial=1234 \
		-nographic
}

copy_out_results()
{
	[ -n "$TEST_DEBUG" ] && return

	local outdir="${RESULT_DIR}/$(date +%Y-%m-%d_%H:%M)_$ARCH"
	mkdir -p $outdir

	virt-copy-out -a $IMG $GUEST_LOG_DIR $outdir || error "Copying results failed"
}

exit_cleanup()
{
	if [ -n "$NVME_CREATED" ]; then
		[ -n "$NVME_IMG" ] && rm -f $NVME_IMG
	fi
}

# Set default options
GUEST_LOG_DIR="/root/logs"
GUEST_DIR="./guest"
GUEST_TEST="/root/$(basename $GUEST_DIR)/runtest.sh"
GUEST_LOG="$GUEST_LOG_DIR/output.log"
GUEST_RPM_DIR="/root/rpms"
GUEST_REPO_DIR="/etc/yum.repos.d/"
GUEST_RC_LOCAL="/etc/rc.d/rc.local"
GUEST_LIBURING_CONFIG="${GUEST_DIR}/liburing.config"

CREATE_DIR=""
RC_LOCAL_MODE="0700"
NVME_SIZE="1G"
RESULT_DIR="./results"

# Set default options that can be
# specified in config file
ARCH="x86_64"
IMG_INIT=1
COPY_IMG=0
COPY_IN=""
LIBURING_TEST_EXCLUDE=""
IMG="https://ewr.edge.kernel.org/fedora-buffet/fedora/linux/releases/32/Cloud/x86_64/images/Fedora-Cloud-Base-32-1.6.x86_64.qcow2"
NVME_IMG=""
GUEST_LIBURING_GIT="git://git.kernel.dk/liburing -b master"
GUEST_CPUS=4
GUEST_MEMORY=2048

# To avoid hassle with overwriting specified commandline option with the
# options from config file, just search of the -C option here, set the
# CONFIG_FILE and ignore that option later
set_config=0
for opt in "$@"; do
	if [ "$opt" == "-C" ]; then
		set_config=1
		continue
	elif [ "$set_config" -eq 1 ]; then
		test_reg_file $opt
		CONFIG_FILE=$opt
		break
	fi
done
set_config=0

# Load configuration file
[ -f "$CONFIG_FILE" ] && . $CONFIG_FILE

# Copy in guest dir
COPY_IN="--copy-in $GUEST_DIR:/root $COPY_IN"

# Parse options
while getopts "ha:dr:I:ncN:e:p:C:" option; do
	case $option in
	h)
		usage; exit 0
		;;
	a)
		test_arch $OPTARG
		ARCH=$OPTARG
		;;
	n)
		IMG_INIT=0
		;;
	r)
		test_reg_file $OPTARG
		COPY_IN="--copy-in $OPTARG:$GUEST_REPO_DIR $COPY_IN"
		IMG_INIT=1
		;;
	I)
		IMG=$OPTARG
		;;
	d)
		RC_LOCAL_MODE="0600"
		IMG_INIT=1
		;;
	c)
		COPY_IMG=1
		;;
	N)
		NVME_IMG=$OPTARG
		;;
	e)
		LIBURING_TEST_EXCLUDE="$OPTARG $LIBURING_TEST_EXCLUDE"
		;;
	p)
		CREATE_DIR="--mkdir $GUEST_RPM_DIR"
		test_reg_file $OPTARG
		COPY_IN="--copy-in $OPTARG:$GUEST_RPM_DIR $COPY_IN"
		;;
	C)
		[ "$set_config" -eq 1 ] && error "You can only specify CONFIG once"
		set_config=1
		;;
	*)
		error "Unrecognized option \"$option\""
		;;
	esac
done

# Check for required utilities
check_util truncate
check_util virt-sysprep
check_util qemu-system-x86_64
check_util qemu-system-ppc64
check_util wget
check_util virt-copy-out

# Download OS image if needed
# Is it http or https link ?
echo $IMG | grep -E '^(http|https)://' > /dev/null 2>&1
if [ $? -eq 0 ]; then
	wget -q --show-progress --no-check-certificate -N $IMG
	[ $? -ne 0 ] && error "Downloading OS image failed"
	IMG=$(basename $IMG)
fi
[ -e "$IMG" ] || error "Valid OS image must be specified"

# Create nvme image if one was not provided
create_image

[ -e "$NVME_IMG" ] || error "Nvme image must be specified"

# Print options
printf "Architecture:\t\t${ARCH}\n"
printf "OS Image:\t\t${IMG}\n"
printf "NVME Image\t\t${NVME_IMG}\n"
printf "/etc/rc.local mode:\t${RC_LOCAL_MODE}\n"
printf "Initialize image:\t${IMG_INIT}\n"
printf "Copy image:\t\t${COPY_IMG}\n"
printf "COPY_IN:\t\t${COPY_IN}\n"
printf "Exclude tests:\t\t${LIBURING_TEST_EXCLUDE}\n"
printf "Config file:\t\t${CONFIG_FILE}\n"
printf "Liburing repository:\t${GUEST_LIBURING_GIT}\n"
printf "Guest memory:\t\t${GUEST_MEMORY}\n"
printf "Guest CPUs:\t\t${GUEST_CPUS}\n"

# Copy the image and run on the copy instead
copy_image

# Create configuration for liburing test
sed -n 's/^[[:space:]]*LIBURING_//p' $CONFIG_FILE > $GUEST_LIBURING_CONFIG

# Setup the configuration for the test in guest
if [ -n "$GUEST_LIBURING_GIT" ]; then
	echo "GUEST_LIBURING_GIT=\"$GUEST_LIBURING_GIT\"" >> $GUEST_DIR/config.local
fi
echo "RPM_DIR=\"$GUEST_RPM_DIR\"" >> $GUEST_DIR/config.local

# Prepare the image
initialize_image

# Run the qemu and test
case $ARCH in
	x86_64)
		run_x86_64
		;;
	ppc64)
		run_ppc64
		;;
	*)
		error "Unsupported architecture \"$ARCH\""
		;;
esac

# Copy out restult logs
copy_out_results
