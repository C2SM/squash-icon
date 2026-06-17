#!/usr/bin/bash

# Duplicate ORIGIN to TARGET with only symlinks except for specified "concrete"
# items. Those will either be copied in the case of a file or created in the
# case of a directory, linking the counterpart ORIGIN content. Any sub-directory
# along the path from TARGET to a concrete item will be created and the content
# of ORIGIN will be symlinked.


set -e
shopt -s dotglob

# Usage
# -----
help_msg(){
    echo
    echo "duplink.sh"
    echo "----------"
    echo "Duplicate ORIGIN to TARGET with only symlinks except for specified concrete"
    echo "items. Those will either be copied in the case of a file or created in the"
    echo "case of a directory, linking the counterpart ORIGIN content. Any sub-directory"
    echo "along the path from TARGET to a concrete item will be created and the content"
    echo "of ORIGIN will be symlinked."
    echo
    echo "usage:"
    echo "$0 --origin=ORIGIN --target=TARGET [--concrete=\"path/to/item_1:path/to/item_2\"]"
    echo
}

# Parse CLI
# ---------
concrete_list=()
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
        --concrete=*)
            IFS=':' read -ra concrete_list <<< "${1#*=}"
            shift 1
            ;;
        --help) help_msg;;
        *) echo "ERROR: unrecognized argument: $1" >&2; exit 1;;
    esac
done

msg="linking items from ${origin} into ${target}"
if  (( ${#concrete_list} == 0 )); then
    echo "${msg}"
else
    echo "${msg}, except following concrete paths:"
    for concrete_path in ${concrete_list[@]}; do
        echo "  - ${concrete_path}"
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

# Handle concrete items
# ---------------------
for concrete_path in ${concrete_list[@]}; do
    IFS='/' read -ra concrete_path_items <<< "${concrete_path}"
    sub_path=""
    found_origin_link="false"
    for path_item in ${concrete_path_items[@]}; do
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
