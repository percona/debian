#!/bin/bash
# Usage: build-orig.sh [options] [http location of source tarball]
#
# The program will build a .orig.tar.gz file with embedded version information
# for consumption by debian package build process from a raw 'upstream'
# Percona Server source tarball.
#

# Bail out on errors, be strict
set -ue

# The working directory and location of resulting files
WORKING_DIR=$PWD

# The given source tarball location
HTTP_LOCATION=''

# Read from the VERSION file
GALERA_VERSION=''

# git revno
GALERA_REVISION=''

# Don't clean up after ourselves
DONT_CLEAN=''

# Display usage
function show_usage()
{
	if [ $# -gt 1 ]; then
		echo "ERROR : ${2}"
	fi

	echo \
"Usage:
	$(basename $0) [options] [http location of source tarball]
Options:
	-d | --dont-clean	Don't clean directories afterwards.
	-h | --help		Display this help message."
	exit $1
}

# Examine parameters
go_out="$(getopt --options="dh" --longoptions="dont-clean,help" \
	--name="$(basename "$0")" -- "$@")"
eval set -- "$go_out"

for arg
do
	case "$arg" in
	-- ) shift; break;;
	-d | --dont-clean ) shift; DONT_CLEAN='true';;
	-h | --help ) shift; show_usage 0;;
	esac
done

if [ $# -eq 0 ]; then
	show_usage 1 "No http location specified"
fi
HTTP_LOCATION=$@;

echo "HTTP_LOCATION=${HTTP_LOCATION}"
echo "WORKING_DIR=${WORKING_DIR}"

# And away we go...
cd ${WORKING_DIR}

# Get the source
wget ${HTTP_LOCATION}

# Find the resulting source tarball
SOURCE_TAR=$(basename $(find . -type f -name '*.tar.gz' | sort | tail -n1))
if [ ! -e "${SOURCE_TAR}" ] || [ ! -f "${SOURCE_TAR}" ]; then
  echo "ERROR : No result source tar file \"${SOURCE_TAR}\" found from \'cmake . && make dist\'."
  exit 1
fi
SOURCE_TAR_DIR="percona-xtradb-cluster-galera-3"

# Extract the source tar
if [ -d "${SOURCE_TAR_DIR}" ]; then
	rm -rf ${SOURCE_TAR_DIR}
fi
tar -xzf ${SOURCE_TAR}

if [ ! -d "${SOURCE_TAR_DIR}" ]; then
	echo "ERROR : Directory \"${SOURCE_TAR_DIR}\" not found after extracting \"${SOURCE_TAR}\""
	exit 1
fi

# Collect versions stuffs
#GALERA_VERSION=$(grep '^GALERA_VER' ${SOURCE_TAR_DIR}/SConstruct  | grep -oE "'[0-9.]+'" | tr -d "'")
GALERA_VERSION=${SOURCE_TAR#"percona-xtradb-cluster-galera-3-"}
GALERA_VERSION=${GALERA_VERSION%".tar.gz"}

# Relocate to the working dir
cd ${WORKING_DIR}

# Build out various file and directory names
ORIG_TAR=percona-xtradb-cluster-galera-3.x_${GALERA_VERSION}.orig.tar.gz
ORIG_TAR_DIR=percona-xtradb-cluster-galera-3.x_${GALERA_VERSION}

# Remove anything not needed for debian build.
rm -rf ${SOURCE_TAR_DIR}/debian
rm -rf ${SOURCE_TAR_DIR}/packages/debian

# Write DEB-VERSION file and make a copy in the source tree
echo "GALERA_VERSION=${GALERA_VERSION}" > DEB-VERSION
echo "HTTP_LOCATION=${HTTP_LOCATION}" >> DEB-VERSION
cp DEB-VERSION ${SOURCE_TAR_DIR}

# Rename the tree
mv ${SOURCE_TAR_DIR} ${ORIG_TAR_DIR}

# Build the orig tarfile
tar --owner=0 --group=0 --exclude=.bzr --exclude=.git -czf ${ORIG_TAR} ${ORIG_TAR_DIR}

# Clean up
if [ "${DONT_CLEAN}" != "true" ]; then
	rm -rf ${ORIG_TAR_DIR}
fi

# Return
exit 0
