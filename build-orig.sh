#!/bin/bash
# Usage: build-orig.sh [options] [source-dir] [working-dir]
#
# The program will build a .orig.tar.gz file with embedded version information
# for consumption by debian package build process.
#

# Bail out on errors, be strict
set -ue

# The location of the source tree to build
SOURCE_DIR=''

# The working directory and location of resulting files
WORKING_DIR=''

# Read from the VERSION file
MYSQL_VERSION_MAJOR=''
MYSQL_VERSION_MINOR=''
MYSQL_VERSION_PATCH=''
MYSQL_VERSION_EXTRA=''

# Composed versions
PERCONA_SERVER_FULLNAME=''
PERCONA_SERVER_DEBNAME=''

# bzr revno
BZR_REVISION=''

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
	$(basename $0) [options] [source-dir] [working-dir]
Options:
	-d | --dont-clean	Don't clean directories afterwards.
	-h | --help		Display this help message."
	exit $1
}

# Examine parameters
go_out="$(getopt --options="dh" --longoptions="dont-clean,help-mtr" \
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
	show_usage 1 "No source-dir specified"
fi
SOURCE_DIR=$1; shift;
if [ ! -d "${SOURCE_DIR}" ]; then
	show_usage 1 "Invalid source-dir specified \"${SOURCE_DIR}\""
fi

if [ $# -eq 0 ]; then
	show_usage 1 "No working-dir specified"
fi
WORKING_DIR=$1; shift;
if [ ! -d "${SOURCE_DIR}" ]; then
	show_usage 1 "Invalid working-dir specified \"${WORKING_DIR}\""
fi

echo "SOURCE_DIR=${SOURCE_DIR}"
echo "WORKING_DIR=${WORKING_DIR}"

# And away we go...
cd ${SOURCE_DIR}

# Clean up the source tree
bzr clean-tree --unknown --ignored --detritus --force

# Read version info from the VERSION file
. VERSION

# Build out various file and directory names
MYSQL_VERSION_EXTRA=${MYSQL_VERSION_EXTRA#-}
PERCONA_SERVER_FULLNAME=percona-server-${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}-${MYSQL_VERSION_EXTRA}
PERCONA_SERVER_DEBNAME=percona-server-${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}_${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}-rel${MYSQL_VERSION_EXTRA}
BZR_REVISION=$(bzr revno)

# And now our locals for the task at hand
SOURCE_TAR=${PERCONA_SERVER_FULLNAME}.tar.gz
SOURCE_TAR_DIR=${PERCONA_SERVER_FULLNAME}
ORIG_TAR=${PERCONA_SERVER_DEBNAME}.orig.tar.gz

# Build out the source tarball
cmake .
make dist

# Find the resulting source tarball
if [ ! -e "${SOURCE_TAR}" ] || [ ! -f "${SOURCE_TAR}" ]; then
  echo "ERROR : No result source tar file \"${SOURCE_TAR}\" found from \'cmake . && make dist\'."
  exit 1
fi

# Move it out to the working directory
mv ${SOURCE_TAR} ${WORKING_DIR}

# Relocate to the working dir
cd ${WORKING_DIR}

# Extract the source tar
if [ -d "${SOURCE_TAR_DIR}" ]; then
	rm -rf ${SOURCE_TAR_DIR}
fi
tar -xzf ${SOURCE_TAR}

# Touch up/find replace various version bits across tha tree
sed -i "s:@@PERCONA_VERSION_EXTRA@@:${MYSQL_VERSION_EXTRA}:g" ${SOURCE_TAR_DIR}/build-ps/debian/rules
sed -i "s:@@REVISION@@:${BZR_REVISION}:g" ${SOURCE_TAR_DIR}/build-ps/debian/rules

# Remove anything not needed for debian build.
rm -f ${SOURCE_TAR_DIR}/doc/source/percona-theme/static/jquery.min.js
rm -rf ${SOURCE_TAR_DIR}/python-for-subunit2junitxml
rm -f ${SOURCE_TAR_DIR}/subunit2junitxml
rm -f ${SOURCE_TAR_DIR}/Docs/INFO_SRC
rm -f ${SOURCE_TAR_DIR}/mysql-test/t/file_contents.test
rm -f ${SOURCE_TAR_DIR}/mysql-test/r/file_contents.result
rm -rf ${SOURCE_TAR_DIR}/build-ps/debian
rm -f ${SOURCE_TAR_DIR}/build-ps/percona-server.spec
rm -f ${SOURCE_TAR_DIR}/build-ps/build-dpkg-for-archive.sh

# Write DEB-VERSION file and make a copy in the source tree
echo "MYSQL_VERSION_MAJOR=${MYSQL_VERSION_MAJOR}" > DEB-VERSION
echo "MYSQL_VERSION_MINOR=${MYSQL_VERSION_MINOR}" >> DEB-VERSION
echo "MYSQL_VERSION_PATCH=${MYSQL_VERSION_PATCH}" >> DEB-VERSION
echo "MYSQL_VERSION_EXTRA=${MYSQL_VERSION_EXTRA}" >> DEB-VERSION
echo "PERCONA_SERVER_FULLNAME=${PERCONA_SERVER_FULLNAME}" >> DEB-VERSION
echo "PERCONA_SERVER_DEBNAME=${PERCONA_SERVER_DEBNAME}" >> DEB-VERSION
echo "BZR_REVISION=${BZR_REVISION}" >> DEB-VERSION
cp DEB-VERSION ${SOURCE_TAR_DIR}

# Build the orig tarfile
tar --owner=0 --group=0 --exclude=.bzr --exclude=.git -czf ${ORIG_TAR} ${SOURCE_TAR_DIR}

# Clean up
if [ "${DONT_CLEAN}" != "true" ]; then
	rm -rf ${SOURCE_TAR_DIR}
fi
