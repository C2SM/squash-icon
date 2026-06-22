#!/usr/bin/bash

set -e


# ========================================
# Init
# ========================================

# Help
# ----
help_msg(){
    echo
    echo "Run an icon experiment using the content of a squashed icon directory"
    echo
    echo "Usage:"
    echo "$0 [required arguments] [optional arguments]"
    echo
    echo "required arguments"
    echo "  --squash=SQUASHED_FILE  icon directory squashed file with icon builds"
    echo "  --target=TARGET         use icon build at \"build/TARGET\" in SQUASHED_FILE (see build_and_squash_icon.sh)"
    echo "  --exp=EXP               icon experiment name"
    echo
    echo "optional arguments"
    echo "  --mount=MOUNT_POINT     mount point for SQUASHED_FILE, default: \"./ICON_MOUNT\""
    echo "  --run=ICON_RUN          dupplicate icon from ICON_MOUNT to ICON_RUN using duplink.sh, default: \"./ICON_RUN\""
    echo "  --account=ACCOUNT       SLURM account, default: first entry of \$(groups)"
    echo "  --partition=PARTITION   use SLURM partition PARTITION, default: \"debug\""
    echo "  --time=TIME             request --time=TIME to SLURM, default: \"00:30:00\""
}

# Parse CLI
# ---------
# Required args
icon_uenv=""
squashed_icon=""
build_target=""
exp=""
# Optional args
icon_mount="$(realpath ./ICON_MOUNT)"
icon_run=${icon_run:-"$(realpath ./ICON_RUN)"}
user_groups=($(groups))
account=${user_groups[0]}
partition="debug"
wall_time="00:30:00"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --squash=*) squashed_icon="$(realpath ${1#*=})"; shift 1;;
        --target=*) build_target="${1#*=}"; shift 1;;
        --exp=*) exp="${1#*=}"; shift 1;;
        --mount=*) icon_mount="$(realpath ${1#*=})"; shift 1;;
        --run=*) icon_run="$(realpath ${1#*=})"; shift 1;;
        --account=*) account="${1#*=}"; shift 1;;
        --partition=*) partition="${1#*=}"; shift 1;;
        --time=*) wall_time="${1#*=}"; shift 1;;
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
required_vars=("squashed_icon" "build_target" "exp")
required_opts=("--squash" "--target" "--exp")
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

# Create mount point
# ------------------
mkdir -p ${icon_mount}

# Get icon_uenv from squashed file
# --------------------------------
icon_uenv=$(uenv run ${squashed_icon}:${icon_mount} -- cat ${icon_mount}/ICON_UENV)
if [ -z "${icon_uenv}" ]; then
    echo "ERROR: could not read ICON_UENV at the root of ${squashed_icon}"
    exit 1
fi


# ========================================
# Duplicate icon squashed directory
# ========================================

# uenv run ${squashed_icon}:${icon_mount} -- ./duplink.sh --origin=${icon_mount} --target=${icon_run} --actual="build/${build_target}/run/set-up.info:build/${build_target}/setting"
uenv run ${squashed_icon}:${icon_mount} -- ./duplink.sh --origin=${icon_mount} --target=${icon_run} --actual="build/${build_target}/run/set-up.info"


# ========================================
# Modify necessary files
# ========================================

pushd ${icon_run}/build/${build_target} >/dev/null 2>&1
    
# enable make_runscripts from the "cloned" directory
echo "use_builddir=\"$(pwd)\"" >> ./run/set-up.info

# # Use the correct icon4py location
# sed -i "s|\..*run\.env$|\. ${icon_run}/build/${build_target}/externals/icon4py/run\.env|" ./setting

popd >/dev/null 2>&1


# ========================================
# Run
# ========================================

pushd ${icon_run}/build/${build_target} >/dev/null 2>&1

uenv run ${squashed_icon}:${icon_mount} -- ./make_runscripts ${exp}

pushd run >/dev/null 2>&1

sbatch_cmd="sbatch --uenv=${icon_uenv},${squashed_icon}:${icon_mount} --view=default"
sbatch_cmd+=" --time=${wall_time} --account=${account} --partition=${partition}"
sbatch_cmd+=" ./exp.${exp}.run"

echo "Submitting job from $(pwd) with command"
echo "${sbatch_cmd}"

# Set icon4py paths for icon4py targets
if [[ "${build_target}" == *"icon4py"* ]]; then
    export ICON4PY_BIN="${icon_run}/externals/icon4py/.venv/bin"
    export ICON4PY_RUN_ENV="${icon_run}/build/${build_target}/externals/icon4py/run.env"
fi

${sbatch_cmd}

popd >/dev/null 2>&1

popd >/dev/null 2>&1
