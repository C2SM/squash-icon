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
    on_compute_node="true"
else
    on_compute_node="false"
fi

# Build dir
# ---------
if [ "${on_compute_node}" == "true" ]; then
    default_build_dir="/dev/shm/${USER}/build_and_squash_icon"
else
    script_dir=$(cd "$(dirname "$0")"; pwd)
    default_build_dir="${script_dir}/build_and_squash_icon"
fi
build_dir="${build_dir:-$default_build_dir}"

# Uenv
# ----
icon_uenv=${icon_uenv:-"icon/26.2:2609004181"}

# Helper functions
# ----------------
elapsed(){
    local seconds=$(($2 - $1))
    printf '%02d:%02d:%02d\n' $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

# Target
# ----------
# One of "santis.gpu.nvhpc", etc ...
build_target="${1}"
if [ -z "${build_target}" ]; then
    echo "ERROR: build_target not set. Should be one of 'santis.gpu.nvhpc', etc ..."
fi
echo "[build_and_squash] ... Set up for ${build_target}"

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
echo "[build_and_squash] ... Building ICON in ${build_dir}"

rm -rf "${build_dir}"
mkdir -p "${build_dir}"
original_dir="$(pwd)"
pushd "${build_dir}" >/dev/null 2>&1


# ========================================
# Get ICON
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Getting ICON"

ICON_REPO=${ICON_REPO:-'git@gitlab.dkrz.de:icon/icon-nwp.git'}
ICON_BRANCH=${ICON_BRANCH:-'main'}
icon_name=$(basename $ICON_REPO)
icon_name=${icon_name%%.git}
ICON_DIRNAME="${icon_name}_${ICON_BRANCH}"

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
uenv run ${icon_uenv} --view default -- time ./config/cscs/${build_target}

# # Test out-of-source build => OK
# build_dir="build_${build_target//./_}"
# mkdir $build_dir
# pushd $build_dir >/dev/null 2>&1
# uenv run ${icon_uenv} --view default -- time ../config/cscs/${build_target}
# popd >/dev/null 2>&1

stop=$(date +%s)
echo "[build_and_squash] ... Building => done in $(elapsed $start $stop)"

popd >/dev/null 2>&1


# ========================================
# Squash
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Squashing"
ICON_SQUASH_FILE="${ICON_DIRNAME}_${build_target}.squashfs"
mksquashfs "${ICON_DIRNAME}" "${ICON_SQUASH_FILE}" -no-recovery -noappend -Xcompression-level 3 || exit
stop=$(date +%s)
echo "[build_and_squash] ... Squashing => done in $(elapsed $start $stop)"


# ========================================
# Retrieve squashed file
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Retrieving squash"
rsync -av "${ICON_SQUASH_FILE}" "${original_dir}/."
stop=$(date +%s)
echo "[build_and_squash] ... Retrieving squash => done in $(elapsed $start $stop)"


# ========================================
# Clean /dev/shm on login node
# ========================================
# 
if [ "${on_compute_node}" == "false" ] && [ "${build_dir}" == "/dev/shm/*" ]; then
    start=$(date +%s)
    echo "[build_and_squash] ... cleaning ${build_dir}"
    rm -rf "${build_dir}"
    stop=$(date +%s)
    echo "[build_and_squash] ... cleaning => done in $(elapsed $start $stop)"
fi


# ========================================
# Accounting
# ========================================

stop=$(date +%s)
echo "[build_and_squash] ... build and squash complete in $(elapsed $overall_start $stop)"

if [ "${on_compute_node}" == "true" ]; then
    sacct -j "${SLURM_JOB_ID}" --format "JobID, JobName, AllocCPUs, Elapsed, ElapsedRaw, CPUTimeRAW, ConsumedEnergyRaw, MaxRSS, MaxVMSize, AveRSS"
fi


# ========================================
# End
# ========================================

popd >/dev/null 2>&1
