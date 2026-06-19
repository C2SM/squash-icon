#!/usr/bin/bash

#SBATCH --account=cwd01
#SBATCH --time=01:00:00
#SBATCH --output="build_and_squash_icon.%j.o"
#SBATCH --partition=debug

set -e


# ========================================
# Init
# ========================================

# TODO: enable build target selection

# Help
# ----
help_msg(){
    echo
    echo "Build and squash the icon directory"
    echo
    echo "Usage:"
    echo "$0 [required arguments] [optional arguments]"
    echo
    echo "required arguments"
    echo "  --uenv=UENV                    icon uenv"
    echo
    echo "optional arguments"
    echo "  --repo=ICON_REPO               icon git repository, default: git@gitlab.dkrz.de:icon/icon-nwp.git"
    echo "  --branch=ICON_BRANCH           branch of ICON_REPO, default: master"
    echo "  --squash=SQUASHED_FILE         squashed filename for the icon directory, default infered from ICON_REPO and ICON_BRANCH"
    echo "  --targets=TARGET1,...          comma separated list of build targets, default: santis.cpu.nvhpc,santis.gpu.nvhpc,santis.icon4py.nvhpc"
    echo "  --gitlab-dkrz-token TOKEN      clone from gitlab.dkrz.de with TOKEN instead of ssh"
    echo "  --github-tokenc TOKEN          clone from github.com with TOKEN instead of ssh"
}

# Set defaults
# ------------
# Required args
icon_uenv=""

# Optional args
icon_repo="git@gitlab.dkrz.de:icon/icon-nwp.git"
icon_branch="master"
squashed_icon=""
build_targets=("santis.cpu.nvhpc" "santis.gpu.nvhpc" "santis.icon4py.nvhpc")
gitlab_dkrz_token=""
github_token=""

# Parse CLI args
# --------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        --uenv=*) icon_uenv="${1#*=}"; shift 1;;
        --repo=*) icon_repo="${1#*=}"; shift 1;;
        --branch=*) icon_branch="${1#*=}"; shift 1;;
        --squash=*) squashed_icon="$(realpath ${1#*=})"; shift 1;;
        --target=*)
            IFS=',' read -ra build_targets <<< "${1#*=}"
            shift 1
            ;;
        --gitlab-dkrz-token=*) gitlab_dkrz_token="${1#*=}"; shift 1;;
        --github-token=*) github_token="${1#*=}"; shift 1;;
        --help) help_msg; exit 0;;
        *)
            help_msg
            echo "ERROR: unrecognized argument: $1" >&2
            exit 1
            ;;
    esac
done

# Check required args
# -------------------
required_vars=("icon_uenv")
required_opts=("--uenv")
for ((k=0; k<${#required_vars[@]}; k++)); do
    var_name=${required_vars[k]}
    opt_name=${required_opts[k]}
    if [ -z ${!var_name} ]; then
        help_msg
        echo
        echo "ERROR: required option ${opt_name} not provided"
        exit 1
    fi
done

# Clone with tokens
# -----------------
k=0
if [ -n "${gitlab_dkrz_token}" ]; then
    eval "GIT_CONFIG_KEY_${k}=\"url.https://oauth2:${gitlab_dkrz_token}@gitlab.dkrz.de/.insteadOf\""
    eval "GIT_CONFIG_VALUE_${k}=\"git@gitlab.dkrz.de:\""
    (( k += 1 ))
fi
if [ -n "${github_token}" ]; then
    eval "GIT_CONFIG_KEY_${k}=\"url.https://oauth2:${github_token}@github.com/.insteadOf\""
    eval "GIT_CONFIG_VALUE_${k}=\"git@github.com:\""
    (( k += 1 ))
fi
(( k > 0 )) &&  GIT_CONFIG_COUNT=${k}

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
    build_dir="/dev/shm/${USER}/build_and_squash_icon"
else
    script_dir=$(cd "$(dirname "$0")"; pwd)
    build_dir="${script_dir}/build_and_squash_icon"
fi

# Helper functions
# ----------------
elapsed(){
    local seconds=$(($2 - $1))
    printf '%02d:%02d:%02d\n' $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

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

icon_name=$(basename ${icon_repo})
icon_name=${icon_name%%.git}
icon_dirname="${icon_name}_${icon_branch}"

git clone --depth 1 --recurse-submodules --shallow-submodules -b "${icon_branch}" "${icon_repo}" "${icon_dirname}"

stop=$(date +%s)
echo "[build_and_squash] ... Getting ICON => done in $(elapsed $start $stop)"


# ========================================
# Build
# ========================================

pushd "${icon_dirname}" >/dev/null 2>&1

start=$(date +%s)
echo "[build_and_squash] ... Building ICON"

# Build all santis targets in parallel
# WARNING: Without changes to santis.xxx.nvhpc, it requires 3 x 72 processes
#          so building on the shared partition could fail or just be slow because sequential
for build_target in ${build_targets[@]}; do
    build_dir="build/${build_target}"
    echo "[build_and_squash] ...... Launchng build of  ${build_target} in ${build_dir}. See log file build.${build_target}.o"
    mkdir -p $build_dir
    pushd $build_dir >/dev/null 2>&1
    uenv run ${icon_uenv} --view default -- time ../../config/cscs/${build_target} > "${original_dir}/build.${build_target}.o" 2>&1 &
    popd >/dev/null 2>&1
done
echo "[build_and_squash] ...... Waiting for all build processes to finish"
wait
stop=$(date +%s)
echo "[build_and_squash] ... Building => done in $(elapsed $start $stop)"

popd >/dev/null 2>&1


# ========================================
# Squash
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Squashing"
squashed_icon=${squashed_icon:-"${icon_dirname}.squashfs"}
mksquashfs "${icon_dirname}" "${squashed_icon}" -no-recovery -noappend -Xcompression-level 3 || exit
stop=$(date +%s)
echo "[build_and_squash] ... Squashing => done in $(elapsed $start $stop)"


# ========================================
# Retrieve squashed file
# ========================================

start=$(date +%s)
echo "[build_and_squash] ... Retrieving squash"
rsync -av "${squashed_icon}" "${original_dir}/."
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
