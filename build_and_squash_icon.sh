#!/usr/bin/bash

#SBATCH --account=cwd01
#SBATCH --time=01:00:00
#SBATCH --output="build_and_squash_icon.%j.o"
#SBATCH --partition=shared
#SBATCH --gpus-per-node=1

set -e


# ========================================
# Init
# ========================================

# Check if building on compute or login node
# ------------------------------------------
if [ -n "${SLURM_JOB_ID:-}" ]; then
    ON_COMPUTE_NODE="true"
else
    ON_COMPUTE_NODE="false"
fi

# Build dir
# ---------
if [ "${ON_COMPUTE_NODE}" == "true" ]; then
    DEFAULT_BUILD_DIR="/dev/shm/${USER}/build_and_squash_icon"
else
    SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
    DEFAULT_BUILD_DIR="${SCRIPT_DIR}/build_and_squash_icon"
fi
BUILD_DIR="${BUILD_DIR:-$DEFAULT_BUILD_DIR}"

# Uenv
# ----
UENV=${UENV:-"icon/26.2:2544170721"}

# Helper functions
# ----------------
elapsed(){
    local seconds=$(($2 - $1))
    printf '%02d:%02d:%02d\n' $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

# Target
# ----------
# One of "santis.gpu.nvhpc", etc ...
TARGET="${1}"
if [ -z "${TARGET}" ]; then
    echo "ERROR: TARGET not set. Should one of 'santis.gpu.nvhpc', etc ..."
fi
echo "[build_and_squash] ... Set up for ${TARGET}"

# Cloning urls with token
# -----------------------
if [ -z "${GITLAB_DKRZ_TOKEN}" ] || [ -z "${GITHUB_TOKEN}" ]; then
    echo "ERROR: GITLAB_DKRZ_TOKEN and/or GITHUB_TOKEN unset"
    exit 1
fi
GIT_CONFIG_COUNT=2
GIT_CONFIG_KEY_0="url.https://oauth2:${GITLAB_DKRZ_TOKEN}@gitlab.dkrz.de/.insteadOf"
GIT_CONFIG_VALUE_0="git@gitlab.dkrz.de:"
GIT_CONFIG_KEY_1="url.https://oauth2:${GITHUB_TOKEN}@github.com/.insteadOf"
GIT_CONFIG_VALUE_1="git@github.com:"


# ========================================
# Start
# ========================================

overall_start=$(date +%s)
echo "[build_and_squash] ... Building ICON in ${BUILD_DIR}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
ORIGINAL_DIR="$(pwd)"
pushd "${BUILD_DIR}" >/dev/null 2>&1


# ========================================
# Get ICON
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Getting ICON"

ICON_REPO='git@gitlab.dkrz.de:icon/icon-nwp.git'
# This branch is a merge of add_icon4py and update_spack_1.1_santis
ICON_BRANCH='add_icon4py_spack_v1.1'
ICON_DIRNAME="icon-nwp_${ICON_BRANCH}"

git clone --depth 1 --recurse-submodules --shallow-submodules -b "${ICON_BRANCH}" "${ICON_REPO}" "${ICON_DIRNAME}"

stop=$(date +%s)
echo "[build_and_squash] ... Getting ICON => done in $(elapsed $start $stop)"


# ========================================
# Build
# ========================================

pushd "${ICON_DIRNAME}" >/dev/null 2>&1

start=$(date +%s)
echo "[build_and_squash] ... Building ICON"

# Test in-source build => OK
uenv run ${UENV} --view default -- time ./config/cscs/${TARGET}

# # Test out-of-source build => OK
# BUILD_DIR="build_${TARGET//./_}"
# mkdir $BUILD_DIR
# pushd $BUILD_DIR >/dev/null 2>&1
# uenv run ${UENV} --view default -- time ../config/cscs/${TARGET}
# popd >/dev/null 2>&1

stop=$(date +%s)
echo "[build_and_squash] ... Building => done in $(elapsed $start $stop)"

popd >/dev/null 2>&1


# ========================================
# Squash
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Squashing"
ICON_SQUASH_FILE="${ICON_DIRNAME}.squashfs"
mksquashfs "${ICON_DIRNAME}" "${ICON_SQUASH_FILE}" -no-recovery -noappend -Xcompression-level 3 || exit
stop=$(date +%s)
echo "[build_and_squash] ... Squashing => done in $(elapsed $start $stop)"


# ========================================
# Retrieve squashed file
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Retrieving squash"
rsync -av "${ICON_SQUASH_FILE}" "${ORIGINAL_DIR}/."
stop=$(date +%s)
echo "[build_and_squash] ... Retrieving squash => done in $(elapsed $start $stop)"


# ========================================
# Clean /dev/shm on login node
# ========================================
# 
if [ "${ON_COMPUTE_NODE}" == "false" ] && [ "${BUILD_DIR}" == "/dev/shm/*" ]; then
    start=$(date +%s)
    echo "[build_and_squash] ... cleaning ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
    stop=$(date +%s)
    echo "[build_and_squash] ... cleaning => done in $(elapsed $start $stop)"
fi


# ========================================
# Accounting
# ========================================

stop=$(date +%s)
echo "[build_and_squash] ... build and squash complete in $(elapsed $overall_start $stop)"

if [ "${ON_COMPUTE_NODE}" == "true" ]; then
    sacct -j "${SLURM_JOB_ID}" --format "JobID, JobName, AllocCPUs, Elapsed, ElapsedRaw, CPUTimeRAW, ConsumedEnergyRaw, MaxRSS, MaxVMSize, AveRSS"
fi


# ========================================
# End
# ========================================

popd >/dev/null 2>&1
