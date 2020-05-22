#!/bin/bash
# Copyright 2020 Dave Bort (git@dbort.com)
# Use of this source code is governed by a MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT
#
# Backs up a directory to S3 if it has changed since the last backup.
#
# Options:
# --src_dir (required)
#     The directory to back up.
# --s3_bucket (required)
#     The S3 bucket to write backups to. This should be the plain name without
#     any "s3:"-type prefix, and must already exist.
# --s3_subpath (optional)
#     Subdirectory within the bucket to put the backup.
# --archive_prefix (optional)
#     Prefix to use for backup file names. The remainder of the file name will
#     be the date/time and checksum.
#
# Prerequisites;
# - The target S3 bucket must exist.
# - The 'aws' tool must be installed and configured to allow access to the
#   target S3 bucket.
# - The 'zip' tool must be installed.
# - The 'sha256sum' tool must be installed.

# Fail on any error or undefined variable.
set -eu
set -o pipefail

# The name of this program; used in log/error messages.
readonly PROGNAME='backup-to-s3'

# Default values; may be overridden by commandline options. Don't define vars
# that correspond to required args, so that we'll get an undefined access error
# if someone refers to them when they're not set.
S3_SUBPATH=''
ARCHIVE_PREFIX=''

# DIE [<msg>]
# Prints an optional message and exits with an error
DIE() {
  echo "${PROGNAME} [$(date)] FAILED: $@" >&2
  exit 1
}

# parse_args [...]
# Parses commandline args and sets the corresponding global variables.
parse_args() {
  # getopt doesn't work right if we don't set any short options, so give it
  # an empty list.
  local options
  options="$(getopt \
      --options='' \
      --longoptions='src_dir:,s3_bucket:,s3_subpath:,archive_prefix:' \
      -- "$@")"
  eval set -- "${options}"
  while true; do
    case "$1" in
    --src_dir)
      shift
      SRC_DIR="$1"
      readonly SRC_DIR
      ;;
    --s3_bucket)
      shift
      S3_BUCKET="$1"
      readonly S3_BUCKET
      ;;
    --s3_subpath)
      shift
      S3_SUBPATH="$1"
      ;;
    --archive_prefix)
      shift
      ARCHIVE_PREFIX="$1"
      ;;
    --)
      shift
      break
      ;;
    *)
      DIE "Unknown option $1"
      ;;
    esac
    shift
  done

  # Lock down these values now that they've had a chance to be overridden.
  readonly S3_SUBPATH
  readonly ARCHIVE_PREFIX
}

# LOG <msg>
# Logs a message.
LOG() {
  # TODO: write to a logfile instead of stdout
  echo "${PROGNAME} [$(date)] $@"
}

# checksum_tree <dir>
# Prints a stable sha256 sum based on the contents and filenames of all
# files under <dir>.
checksum_tree() {
  local dir="$1"
  # Prints the sums of all files under <dir>, sorts them into a predictable
  # order, then sums the sorted list of sums. The final 'sed' removes the
  # '  -' string after the hex sum. LANG/LC_ALL overrides make sort behave
  # predictably in UTF8 envionments.
  LANG=C LC_ALL=C find "${dir}" -type f -print0 \
    | xargs -0 sha256sum \
    | sort \
    | sha256sum \
    | sed -e 's/ .*//'
}

# Checks assumptions and prerequisites.
check_prerequisites() {
  # Make sure the directory we're backing up is specified and exists.
  if [[ ! -v SRC_DIR || -z "${SRC_DIR}" ]]; then
    DIE "Must set --src_dir"
  fi
  if [[ ! -d "${SRC_DIR}" ]]; then
    DIE "--src_dir does not exist or is not a directory: ${SRC_DIR}"
  fi

  # Make sure a bucket is specified.
  if [[ ! -v S3_BUCKET || -z "${S3_BUCKET}" ]]; then
    DIE "Must set --s3_bucket"
  fi

  # Make sure the necessary tools are present.
  if [[ -z "$(which zip)" ]]; then
    DIE "'zip' tool not found in PATH"
  fi
  if [[ -z "$(which aws)" ]]; then
    DIE "'aws' tool not found in PATH"
  fi
  if [[ -z "$(which sha256sum)" ]]; then
    DIE "'sha256sum' tool not found in PATH"
  fi
}

main() {
  parse_args "$@"
  check_prerequisites

  # Create a temporary working directory and delete it when the script exits.
  local work_dir
  work_dir="$(mktemp -d -t "${PROGNAME}-XXXXXXXXXX")"
  trap "rm -r ${work_dir}" EXIT

  # Calculate a checksum based on the names and contents of the source files.
  # This intentionally ignores file dates, permissions, and owners.
  LOG "Checksumming ${SRC_DIR}..."
  local new_checksum
  new_checksum="$(checksum_tree "${SRC_DIR}")"
  if [[ "${#new_checksum}" -ne 64 ]]; then
    DIE "Malformed checksum '${new_checksum}'"
  fi
  LOG "Checksum: ${new_checksum}"

  # Common prefix for all backups with this configuration.
  local s3_prefix="s3://${S3_BUCKET}/${S3_SUBPATH}"

  LOG "Scanning existing backups in ${s3_prefix}..."
  local existing_backups_file="${work_dir}/existing-backups"
  # The ls command will fail if the directory doesn't exist yet.
  # Ignore failures.
  (aws s3 ls "${s3_prefix}/${ARCHIVE_PREFIX}" || /bin/true) \
      > "${existing_backups_file}"
  # mapfile creates a bash array from the input lines.
  local existing_backups
  mapfile -t existing_backups < "${existing_backups_file}"

  # Look for existing backups with the same checksum. If found, we've already
  # backed up the current state.
  local backup
  for backup in "${existing_backups[@]}"; do
    if [[ "${backup}" =~ ${new_checksum} ]]; then
      LOG "Found existing backup with same checksum: ${backup}"
      LOG "Backup not necessary; exiting."
      exit 0
    fi
  done

  # Establish the name of the backup, using the current time.
  local archive="${work_dir}/${ARCHIVE_PREFIX}$( \
      date -Iseconds)-${new_checksum}.zip"

  LOG "Archiving ${SRC_DIR} to ${archive}..."
  (cd "${SRC_DIR}" && zip -r "${archive}" .)

  # The name of the archive in S3.
  local s3_archive
  s3_archive="${s3_prefix}/$(basename "${archive}")"

  LOG "Uploading new backup to ${s3_archive}..."
  aws s3 cp "${archive}" "${s3_archive}"

  LOG "Backup complete."
}

main "$@"
