#!/bin/bash
# Usage: build-dpkg.sh [options] [working-dir]
#
# The program will setup the dpkg building environment and ultimately call
# dpkg-buildpackage with the appropiate parameters.
#
# Within the working dir should be:
#	a DEB-VERSION file
#	an .orig.tar.gz
#	a ./debian source tree

# Bail out on errors, be strict
set -ue

# The working directory and location of resulting files
WORKING_DIR=''

# Build binary packages after source packages
BUILD_BINARY=''

# Strip MTR target from rules file 
STRIP_MTR=''

# Read from the DEB-VERSION file
MYSQL_VERSION_MAJOR=''
MYSQL_VERSION_MINOR=''
MYSQL_VERSION_PATCH=''
MYSQL_VERSION_EXTRA=''
PERCONA_XTRADB_CLUSTER_FULLNAME=''
PERCONA_XTRADB_CLUSTER_DEBNAME=''
BZR_REVISION=''

# The .orig tar file name
ORIG_TAR=''

# The directory that the .orig tar is expanded to
ORIG_TAR_DIR=''

# The resulting .dsc file from the debian build
DSC_FILE=''

# Display usage
function show_usage()
{
	if [ $# -gt 1 ]; then
		echo "ERROR : ${2}"
	fi

	echo \
"Usage:
	$(basename $0) [options] [working-dir]
Options:
	-b | --binary	Build binary packages after source packages have been built.
	-h | --help	Display this help message.
	-s | --skip-mtr	Remove MTR test from package build process."
	exit $1
}

# Examine parameters
go_out="$(getopt --options="bhs" --longoptions="binary,help,skip-mtr" \
	--name="$(basename "$0")" -- "$@")"
eval set -- "$go_out"

for arg
do
	case "$arg" in
	-- ) shift; break;;
	-b | --binary ) shift; BUILD_BINARY='true';;
	-h | --help ) shift; show_usage 0;;
	-s | --skip-mtr ) shift; STRIP_MTR='true';;
	esac
done

if [ $# -eq 0 ]; then
	show_usage 1 "No working-dir specified"
fi
WORKING_DIR=$1; shift;
if [ ! -d "${WORKING_DIR}" ]; then
	show_usage 1 "Invalid working-dir specified \"${WORKING_DIR}\""
fi


echo "BUILD_BINARY=${BUILD_BINARY}"
echo "STRIP_MTR=${STRIP_MTR}"
echo "WORKING_DIR=${WORKING_DIR}"

# And away we go...
cd ${WORKING_DIR}
if [ ! -f "DEB-VERSION" ]; then
	show_usage 1 "Unable to locate file \"${WORKING_DIR}/DEB-VERSION\""
fi
if [ ! -d "./debian" ]; then
	show_usage 1 "Unable to locate directory \"${WORKING_DIR}/debian\""
fi

# Read version info from the DEB-VERSION file
. DEB-VERSION

# Build out various file and directory names
ORIG_TAR=${PERCONA_XTRADB_CLUSTER_DEBNAME}.orig.tar.gz
ORIG_TAR_DIR=percona-xtradb-cluster-${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}-${MYSQL_VERSION_EXTRA}

if [ ! -f "${ORIG_TAR}" ]; then
	show_usage 1 "Unable to locate file \"${WORKING_DIR}/${ORIG_TAR}\""
fi

# Extract original tar file
tar -xzf ${ORIG_TAR}
if [ ! -d "${ORIG_TAR_DIR}" ]; then
	show_usage 1 "Unable to locate directory \"${WORKING_DIR}/${ORIG_TAR_DIR}\""
fi

# Prevent MTR from running on build?
if [ "${STRIP_MTR}" = "true" ]; then
	sed -i "s:MAKE_TEST_TARGET=test-mtr:#MAKE_TEST_TARGET=test-mtr:g" ./debian/rules
fi

# Move the debian directory into the root of the orig source tree
mv -v ./debian ${ORIG_TAR_DIR}

# Change into the orig source tree
cd ${ORIG_TAR_DIR}

# Call the debian build system to build the source package
dpkg-buildpackage -S

# Change back to the working dir
cd ${WORKING_DIR}

# Find the .dsc file that should have been created by the debian package build
DSC_FILE=$(basename $(find . -type f -name '*.dsc' | sort | tail -n1))
if [ -z "${DSC_FILE}" ]; then
	echo "ERROR : Could not find resulting debian dsc file"
fi

# Let's test it
lintian --verbose --info --pedantic ${DSC_FILE} | tee ${WORKING_DIR}/lintian.log

# Are we done?
if [ "${BUILD_BINARY}" != "true" ]; then
	exit 0
fi


# Now, lets build the binary package
cd ${ORIG_TAR_DIR}
dpkg-buildpackage -rfakeroot -uc -us -b

# Change back to the working dir
cd ${WORKING_DIR}

# Find the .deb files that should have been created by the debian package build
for DEB_FILE in $(find . -type f -name '*.deb' | sort); do
	echo "Testing ${DEB_FILE}..." | tee -a ${WORKING_DIR}/lintian.log
	lintian --verbose --info --pedantic ${DEB_FILE} | tee -a ${WORKING_DIR}/lintian.log
done

exit 0
