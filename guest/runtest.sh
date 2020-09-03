#!/bin/bash

create_part_setup() {
cat << EOF
label: gpt
label-id: 88E12A0C-EA80-8A45-9A6F-205B50BF188D
device: /dev/nvme0n1
unit: sectors
first-lba: 2048
last-lba: 20971486

/dev/nvme0n1p1 : start=        2048, size=    10485760, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=A3BAF6A7-F7DB-9C40-9587-907CA7CD5949
/dev/nvme0n1p2 : start=    10487808, size=    10483679, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=68B8F075-B469-164F-90AC-9A740E7D8843
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
mkfs.ext4 -F $FS_DEV
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
