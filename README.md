# Run liburing tests on emulated nvme in qemu

Simple set of scripts to run liburing tests on different architectures.

## Usage

	Usage: ./qemu-test-iouring.sh [-h] [-n] [-d] [-c] [-a ARCH] [-I IMG] [-r REPO] [-N NVME]
		-h		Print this help
		-C CONFIG	Specify custom configuration file. This option
				can only be specified once. (Default "./config.local")
		-a ARCH		Specify architecture to run (default: x86_64).
				Supported: x86_64 ppc64le
		-I IMG		OS image with Fedora, Centos or Rhel. Can be
				existing file, or http(s) url.
		-N NVME		Nvme image to run on. It needs to be at least
				1GB in size.
		-r REPO		Specify yum repository file to include in guest.
				Can be repeated to include multiple files and
				implies image initialization.
		-n		Do not initialize the image with virt-sysprep
		-d		Do not run liburing tests on startup. Implies
				image initialization.
		-c		Do not run on specified image, but rather create
				copy of it first.
		-e		Exclude test. Can be repeated to exclude
				multiple tests.
		-p PKG		RPM package to install in guest

	Example: ././qemu-test-iouring.sh -a ppc64le -r test.repo -c -I fedora.img -N nvme.img
