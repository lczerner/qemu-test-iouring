# Run liburing tests on emulated nvme in qemu

Simple set of scripts to run liburing tests on different architectures.

## Usage

	Usage: ./qemu-test-iouring.sh [-h] [-n] [-d] [-c] [-a ARCH] [-I IMG] [-r REPO] [-N NVME]
		-h		Print this help
		-a ARCH		Specify architecture to run (default: x86_64).
				Supported: x86_64 ppc64le
		-I IMG		Image to run with. Must be specified.
		-N NVME		Nvme image to run on.
		-r REPO		Specify yum repository file to include in guest.
				Can be repeated to include multiple files and
				implies image initialization.
		-n		Do not initialize the image with virt-sysprep
		-d		Do not run liburing tests on startup. Implies
				image initialization.
		-c		Do not run on specified image, but rather create
				copy of it first.

	Example: ././qemu-test-iouring.sh -a ppc64le -r test.repo -c -I fedora.img -N nvme.img
