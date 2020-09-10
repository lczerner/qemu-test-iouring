#!/bin/bash

LOG_DIR="/root/logs"
mkdir -p $LOG_DIR
INSTALL_LOG="$LOG_DIR/install"
LIBURING_LOG="$LOG_DIR/liburing"

create_part_setup() {
cat << EOF
/dev/nvme0n1p1 : start=2048, size=1024000
/dev/nvme0n1p2 : start=1026048, size=1024000
EOF
}

message() {
	echo "IO_URING_TEST: $@" | tee /dev/kmsg
}

stop_test() {
	message "$@"
	poweroff
	exit
}

# Update the machine and install required packages if necessary
# Return 0 on success and 1 on failure
install_packages() {
	# If we failed before user had a chance to change things
	# so let's try again. Remove the log files.
	rm -f ${INSTALL_LOG}.*

	# Packages to install
	local packages="git make gcc e2fsprogs parted coreutils"

	message "Updating kernel"
	dnf -y update kernel
	message "Installing packages"
	dnf -y install $packages || return 1
	message "Installing custom rpms"
	if [ -d "$RPM_DIR" ]; then
		dnf -y install --skip-broken $RPM_DIR/*.rpm || return 1
		# If you want to install customer kernel Fedora is so dumb
		# it needs to be specifically said to boot that kernel
		# as well. This is the best way I know of ATM. (sigh)
		grub2-set-default 0
	fi
	return 0
}

SCRIPT_DIR=$(dirname $0)
CONFIG_FILE="$SCRIPT_DIR/config.local"
NVME=/dev/nvme0n1
TEST_DIR=/mnt
FS_DEV=${NVME}p1
TEST_DEV=${NVME}p2
UNAME=$(uname -a)
GUEST_LIBURING_GIT="git://git.kernel.dk/liburing"

[ ! -d "$TEST_DIR" ] && mkdir -r $TEST_DIR

if [ ! -b $NVME ]; then
	stop_test "ERROR: Nvme device \"$NVME\" does not exist!"
fi

# Load configuration
[ -f "$CONFIG_FILE" ] && . $CONFIG_FILE

# Print out configuration
echo "SCRIPT_DIR = $SCRIPT_DIR"
echo "CONFIG_FILE = $CONFIG_FILE"
echo "GUEST_LIBURING_GIT = $GUEST_LIBURING_GIT"
echo "TEST_EXCLUDE = $TEST_EXCLUDE"

# This is for the liburing test so export it
export TEST_EXCLUDE

message "START"
message "$UNAME"

# Wait for network
while ! ping -w2 -c1 1.1.1.1; do
	message "Network unavailable"
	sleep 1
done

# Skip if installation was already done
if [ ! -f "${INSTALL_LOG}.done" ]; then
	install_packages 2>&1 | tee ${INSTALL_LOG}.log
	if [ $? -ne 0 ]; then
		mv ${INSTALL_LOG}.log ${INSTALL_LOG}.failed
		stop_test "ERROR: Installation failed"
	else
		mv ${INSTALL_LOG}.log ${INSTALL_LOG}.done
		message "Installation done. Rebooting"
		reboot
	fi
fi

message "modprobe"
umount $TEST_DIR
modprobe -r nvme
modprobe nvme || stop_test "ERROR: Modprobe nvme failed"
sleep 1
sync

# Clear partitions
message "Clear partitions"
dd if=/dev/zero of=$NVME bs=1M count=1
partprobe $NVME
sleep 2
sync

# Create partition
message "Create partitions"
create_part_setup > nvme.part
sfdisk $NVME < nvme.part || stop_test "ERROR: Creating partitions failed"
sleep 2
sync

# Create fs
message "Create filesystem"
mke2fs -t ext4 -F $FS_DEV
mount $FS_DEV $TEST_DIR || stop_test "ERROR: Mounting fs failed"


# Clone liburing
message "Get liburing"
cd $TEST_DIR
git clone $GUEST_LIBURING_GIT liburing
cd $TEST_DIR/liburing
./configure && make -j8 || stop_test "ERROR: Building liburing failed"

# Prepare config
echo "TEST_FILES=${TEST_DEV}" > test/config.local

# Remove logs from previous run
rm -f ${LIBURING_LOG}.*

# Run the test
message "Run test"
make runtests 2>&1 | tee ${LIBURING_LOG}.log
dmesg > ${LIBURING_LOG}.dmesg 2>&1

cd /root

# Done
umount $TEST_DIR
message "$UNAME"
stop_test "DONE"
