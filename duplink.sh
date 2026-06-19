#!/usr/bin/bash

set -e
shopt -s dotglob

# Usage
# -----
help_msg(){
    echo
    echo "Duplicate ORIGIN to TARGET with only symlinks except for specified actual"
    echo "items. Those will be created in the case of a directory, linking the"
    echo "counterpart ORIGIN content, and copied otherwise. Any sub-directory along the"
    echo "path from TARGET to an actual item will be created and the content of ORIGIN"
    echo "will be symlinked."
    echo
    echo "Usage:"
    echo "$0 --origin=ORIGIN --target=TARGET [--actual=\"path/to/item_1:path/to/item_2\"]"
    echo
}

# Parse CLI
# ---------
actual_list=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --origin=*)
            origin="${1#*=}"
            if [ ! -e "${origin}" ]; then
                help_msg
                echo "ERROR: origin ${orgin} does not exist"
                exit 1
            fi
            origin="$(realpath ${origin})"
            shift 1
            ;;
        --target=*)
            target="${1#*=}"          
            if [ -e ${target} ]; then
                help_msg
                echo "ERROR: target ${target} already exists, delete it or choose another one."
                exit 1
            fi
            shift 1
            ;;
        --actual=*)
            IFS=':' read -ra actual_list <<< "${1#*=}"
            shift 1
            ;;
        --help) help_msg; exit 0;;
        *) echo "ERROR: unrecognized argument: $1" >&2; exit 1;;
    esac
done

msg="linking items from ${origin} into ${target}"
if  (( ${#actual_list} == 0 )); then
    echo "${msg}"
else
    echo "${msg}, except following actual paths:"
    for actual_path in ${actual_list[@]}; do
        echo "  - ${actual_path}"
    done
fi

# Init target directory
# ---------------------
rm -rf ${target}
target="$(realpath ${target})"
mkdir ${target}
pushd ${target} >/dev/null 2>&1
for item in ${origin}/*; do
    ln -s ${item} .
done
popd >/dev/null 2>&1

# Handle actual items
# -------------------
for actual_path in ${actual_list[@]}; do
    IFS='/' read -ra actual_path_items <<< "${actual_path}"
    sub_path=""
    found_origin_link="false"
    for path_item in ${actual_path_items[@]}; do
        [ -z ${sub_path} ] && sub_path="${path_item}" || sub_path+="/${path_item}"
        origin_sub_path="${origin}/${sub_path}"
        target_sub_path="${target}/${sub_path}"
        if [ ! -e "${origin_sub_path}" ]; then
            echo "ERROR: ${origin_sub_path} does not exist"
            exit 1
        fi
        if [ "${found_origin_link}" == "false" ] && [ -L "${target_sub_path}" ] && [[ "$(readlink ${target_sub_path})" == "${origin}"* ]]; then
            found_origin_link="true"
        fi
        if [ "${found_origin_link}" == "true" ]; then
            rm -rf ${target_sub_path}
            if [ -d ${origin_sub_path} ]; then
                mkdir ${target_sub_path}
                pushd ${target_sub_path} >/dev/null 2>&1
                for item in ${origin_sub_path}/*; do
                    ln -s ${item} .
                done
                popd >/dev/null 2>&1
            else
                cp -a ${origin_sub_path} ${target_sub_path}
            fi
        fi
        origin_sub_path="${origin}/${sub_path}"
    done
done
