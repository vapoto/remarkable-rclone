#!/bin/bash

# Author Kim Covil
#
# Inspired by stucule's maxio script from reddit
# https://www.reddit.com/r/RemarkableTablet/comments/7blo1k/suggestion_network_drive_in_myfiles/
#
# Uses hardlinks for unedited files
# Uses wget to download edited files
# Uses associative arrays for maps
# Uses awk for data extraction from metadata files

# Standard variables
HOME="/home/root/"
BASE="${HOME}.local/share/remarkable"
SRCROOT="${BASE}/xochitl"
TGTROOT="${BASE}/file-tree"
URL="http://10.11.99.1/download"
# rclone support if available (http://rclone.org)
RCLONE="$(which rclone)" # change to the rclone binary (add the path if rclone is outside of $PATH)
RCLONE_CONFIG="${HOME}.config/rclone/rclone.conf" # change to the config file created by 'rclone config'
RCLONE_OPTIONS="--delete-excluded"
UPLOAD="cloud:reMarkable" # sync to a reMarkable folder on the remote rclone storage "cloud"

# Flags
VERBOSE=
QUIET=
DEBUG=
SYNC=
HELP=
WGET_FLAGS="-q"

[[ -s "${HOME}/.file-treerc" ]] && . "${HOME}/.file-treerc"

typeset -A PARENT
typeset -A NAME
typeset -A TYPE
typeset -A FULL
typeset -A FILETYPE
typeset -A UUIDS
typeset -A UUIDS_DIRS
typeset -a FILES
typeset -a DIRS

while getopts "dvshq" OPT
do
    case "${OPT}" in
        v) VERBOSE=1; QUIET=; WGET_FLAGS=;;
        q) QUIET=1;;
        d) DEBUG=1;;
        s) SYNC=1;;
        h) HELP=1;;
        \?) echo "Invalid option: -${OPTARG}" >&2; HELP=1;;
    esac
done

shift $((OPTIND-1))

if [[ -n "${HELP}" ]]
then
    cat <<EOHELP
Usage: $0 [-vqdsh]
    -v    verbose
    -q    quiet
    -d    debug
    -s    sync
    -h    this help
EOHELP
    exit
fi

if [[ -n "${DEBUG}" ]]
then
    set -o xtrace
fi

[[ -z "${QUIET}" ]] && echo "Building metadata maps..."
for D in "${SRCROOT}/"*.metadata
do
    UUID="$(basename "${D}" ".metadata")"
    if [[ "$(awk -F\" '$2=="deleted"{print $3}' "${D}")" == ": false," ]]
    then
        PARENT["${UUID}"]="$(awk -F\" '$2=="parent"{print $4}' "${D}")"
        NAME["${UUID}"]="$(awk -F\" '$2=="visibleName"{print $4}' "${D}")"
        TYPE["${UUID}"]="$(awk -F\" '$2=="type"{print $4}' "${D}")"
        if [[ "${TYPE["${UUID}"]}" == "DocumentType" ]]
        then
            FILES+=( "${UUID}" )
            FILETYPE["${UUID}"]="$(awk -F\" '$2=="fileType"{print $4}' "${D%.metadata}.content")"
            [[ "${FILETYPE["${UUID}"]}" == "pdf" ]] && NAME["${UUID}"]="${NAME["${UUID}"]%.pdf}"
            [[ "${FILETYPE["${UUID}"]}" == "epub" ]] && NAME["${UUID}"]="${NAME["${UUID}"]%.epub}"
        elif [[ "${TYPE["${UUID}"]}" == "CollectionType" ]]
        then
            DIRS+=( "${UUID}" )
        else
            echo "WARN: UUID ${UUID} has an unknown type ${TYPE["${UUID}"]}" >&2
        fi
    else
        [[ -n "${VERBOSE}" ]] && echo "Skipping UUID ${UUID} as it is marked as deleted"
    fi
done

find_full () {
    # Build up full name including path
    local UUID="$1"
    FULL["${UUID}"]="${NAME[${UUID}]}"
    P="${PARENT["${UUID}"]}"
    while [[ "${P}" != "" ]]
    do
        if [[ -n "${FULL["${P}"]}" ]]
        then
            FULL["${UUID}"]="${FULL[${P}]}/${FULL["${UUID}"]}"
            break
        else
            FULL["${UUID}"]="${NAME[${P}]}/${FULL["${UUID}"]}"
        fi
        P="${PARENT["${P}"]}"
    done
}

# Build up folder structure
FULL["trash"]="Trash"
for D in "${DIRS[@]}"
do
    find_full ${D}
    UUIDS_DIRS["${FULL["${D}"]}"]="${D}"
    mkdir -p "${TGTROOT}/${FULL["${D}"]}"
done

# Assign IP to usb0 to activate web UI
ifconfig usb0 10.11.99.1 netmask 255.255.255.248 up
if (( $? != 0 )); then
  echo "Unable to assign IP to usb0" >&2
  exit 1
fi

# Export files
[[ -z "${QUIET}" ]] && echo "Updating ${TGTROOT}/ ..."
for F in "${FILES[@]}"
do
    find_full ${F}

    TARGET="${FULL["${F}"]}"
    [[ -n "${VERBOSE}" ]] && echo "UUID ${F} -> ${TARGET}"
    UUIDS["${TARGET}"]="${F}"

    if [[ "${FILETYPE["${F}"]}" == "pdf" || "${FILETYPE["${F}"]}" == "epub" ]]
    then # PDF or ePUB
        if [[ ! "${SRCROOT}/${F}.${FILETYPE["${F}"]}" -ef "${TGTROOT}/${TARGET}.${FILETYPE["${F}"]}" ]]
        then
            [[ -z "${QUIET}" ]] && echo "Linking ${SRCROOT}/${F}.${FILETYPE["${F}"]} to ${TGTROOT}/${TARGET}.${FILETYPE["${F}"]}"
            ln -f "${SRCROOT}/${F}.${FILETYPE["${F}"]}" "${TGTROOT}/${TARGET}.${FILETYPE["${F}"]}"
        else
            [[ -n "${VERBOSE}" ]] && echo "Target ${TGTROOT}/${TARGET} already exists"
        fi
    fi

    if [[ -n "$(ls -A "${SRCROOT}/${F}")" ]]
    then # Marked file
        if [[ "${FILETYPE["${F}"]}" == "pdf" || "${FILETYPE["${F}"]}" == "epub" ]]
        then
            TARGET+=".marked"
            UUIDS["${TARGET}"]="${F}"
        fi
        if [[ "${SRCROOT}/${F}.metadata" -nt "${TGTROOT}/${TARGET}.pdf" ]]
        then # File has been updated
            [[ -z "${QUIET}" ]] && echo "Downloading ${TGTROOT}/${TARGET}.pdf from ${URL}/${F}/placeholder}"
            rm -f "${TGTROOT}/${TARGET}"
            touch -r "${SRCROOT}/${F}.metadata" "${TGTROOT}/${TARGET}.pdf"
            wget ${WGET_FLAGS} -O "${TGTROOT}/${TARGET}.pdf" "${URL}/${F}/placeholder}"
        else
            [[ -n "${VERBOSE}" ]] && echo "Marked file ${TGTROOT}/${TARGET} has not been updated"
        fi
    else
        [[ -n "${VERBOSE}" ]] && echo "File ${TGTROOT}/${TARGET} is unmarked"
    fi
done

# Remove deleted files
find "${TGTROOT}" -type f | while read F
do
    F="${F#${TGTROOT}/}"
    if [[ -z "${UUIDS["${F%%.*}"]}" ]]
    then
        [[ -z "${QUIET}" ]] && echo "Deleting ${F} as looks to have been removed."
        rm "${TGTROOT}/${F}"
    fi
done

# Remove deleted folders
find "${TGTROOT}" -type d -mindepth 1 | while read D
do
    D="${D#${TGTROOT}/}"
    if [[ "${D}" != "Trash" && -z "${UUIDS_DIRS["${D}"]}" ]]
    then
        [[ -z "${QUIET}" ]] && echo "Deleting ${D} as looks to have been removed."
        rm -rf "${TGTROOT}/${D}"
    fi
done

if [[ -n "${SYNC}" ]]
then
    if [[ -n "${RCLONE}" && -x "${RCLONE}" && -n "${UPLOAD}" ]]
    then
        [[ -z "${QUIET}" ]] && echo "Syncing ${TGTROOT}/ to ${UPLOAD}/ ..."
        "${RCLONE}" sync ${VERBOSE:+--verbose} ${RCLONE_OPTIONS} --config ${RCLONE_CONFIG} "${TGTROOT}/" "${UPLOAD}/"
    else
        echo "ERROR: Unable to sync as rclone is not available or correctly configured" >&2
    fi
fi
