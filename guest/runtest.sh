#!/bin/bash

create_part_setup() {
cat << EOF
/dev/nvme0n1p1 : start=2048, size=1024000
/dev/nvme0n1p2 : start=1026048, size=1024000
EOF
}

message() {
	wall -n "IO_URING_TEST: $@"
}

NVME=/dev/nvme0n1
TEST_DIR=/mnt
FS_DEV=${NVME}p1
TEST_DEV=${NVME}p2
UNAME=$(uname -a)

[ ! -d "$TEST_DIR" ] && mkdir -r $TEST_DIR

if [ ! -b $NVME ]; then
	echo "Nvme device \"$NVME\" does not exist!"
	exit 1
fi

message "START"
message "$UNAME"

# Update the machine and install required packages if necessary
dnf group summary "Development tools" | grep "Installed Groups"
if [ $? -ne 0 ]; then
	message "Updating packages"
	dnf -y update
	message "Installing packages"
	dnf -y install wget vim
	dnf -y groupinstall 'Development tools'
	reboot
fi

message "modprobe"
umount $TEST_DIR
modprobe -r nvme
modprobe nvme || exit 1
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
sfdisk $NVME < nvme.part || exit 1
sleep 2
sync

# Create fs
message "Create filesystem"
mke2fs -t ext4 -F $FS_DEV
mount $FS_DEV $TEST_DIR || exit 1


# Clone liburing
message "Get liburing"
cd $TEST_DIR
git clone git://git.kernel.dk/liburing
cd $TEST_DIR/liburing
./configure && make -j8 || exit 1

# Prepare config
echo "TEST_FILES=${TEST_DEV}" > test/config.local

# Run the test
message "Run test"
make runtests
cd /root

# Done
message "$UNAME"
message "DONE"
umount $TEST_DIR
echo "TEST DONE"
exit 0
