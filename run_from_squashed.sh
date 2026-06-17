#!/usr/bin/bash

set -e


# ========================================
# Init
# ========================================

if [ -z "${1}" ]; then
    echo "ERROR: icon squashed file not provided"
fi

# Uenv
# ----
ICON_UENV=${ICON_UENV:-"icon/26.2:2609004181"}
squashed_icon=$(realpath "${1}")


# ========================================
# Link and copy from mounted icon dir
# ========================================

icon_mount=${icon_mount:-"$(realpath ./ICON_MOUNT)"}
icon_run=${icon_run:-"$(realpath ./ICON_RUN)"}

mkdir -p ${icon_mount}
uenv run ${squashed_icon}:${icon_mount} -- ./duplink.sh --origin=${icon_mount} --target=${icon_run} --concrete="setting:run/set-up.info"


# ========================================
# Modify necessary files
# ========================================

# enable makre_runscripts from the "cloned" directory
pushd ${icon_run} >/dev/null 2>&1
echo "use_builddir=\"$(pwd)\"" >> ./run/set-up.info

# Remove the sourcing of run.env from setting
sed -i '/\..*run\.env$/d' ./setting
echo "export PYTHONOPTIMIZE=2" >> ./setting

# Add icon4py relevant variables (some others are already in setting)
echo "export GT4PY_BUILD_CACHE_LIFETIME=\"persistent\"" >> ./setting
popd >/dev/null 2>&1


# ========================================
# Run
# ========================================

pushd ${icon_run} >/dev/null 2>&1

exp=mch_icon-ch2_small
uenv run ${squashed_icon}:${icon_mount} -- ./make_runscripts ${exp}

pushd run >/dev/null 2>&1
sbatch --uenv ${ICON_UENV},${squashed_icon}:${icon_mount} --view default \
    --time 00:30:00 \
    --account cwd01 \
    --partition debug \
    ./exp.${exp}.run
popd >/dev/null 2>&1

popd >/dev/null 2>&1
