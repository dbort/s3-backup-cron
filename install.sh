#!/bin/bash
# Copyright 2020 Dave Bort (git@dbort.com)
# Use of this source code is governed by a MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT
#
# Generates and installs backup tools.
#
# Usage: Run it and answer the questions. Paste the suggested
#     line into your crontab.

set -eu
set -o pipefail

# The name of this script.
readonly PROGNAME="$(basename "${BASH_SOURCE[0]}")"

# The directly that contains this file.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
readonly SCRIPT_DIR

# read_path <default value> <prompt>
read_path() {
  local default="$1"
  local default_prompt
  if [[ -n "${default}" ]]; then
    default_prompt="[${default}]"
  else
    default_prompt='(NO DEFAULT)'
  fi

  local prompt="$2"
  local provided
  echo >&2
  read -p "${prompt}:"$'\n'"${default_prompt} > " provided
  if [[ -z "${provided}" ]]; then
    echo "${default}"
  else
    echo "${provided}"
  fi
}

main() {
  # Ask user for paths and other parameters.
  local install_dir=''
  while [[ -z "${install_dir}" ]]; do
    install_dir="$(read_path \
        "${HOME}/bin" \
        "Directory to install scripts to (will be created if not present)")"
    if [[ -z "${install_dir}" ]]; then
      echo "!!! Installation directory is required. Press ^C to exit."
    fi
  done

  local src_dir=''
  while [[ -z "${src_dir}" ]]; do
    src_dir="$(read_path \
        "${HOME}/.local/share/FoundryVTT/Data/worlds" \
        "Directory to back up")"
    if [[ ! -d "${src_dir}" ]]; then
      echo "!!! Not a directory: '${src_dir}'. Press ^C to exit."
      src_dir=''
    fi
  done

  local s3_bucket=''
  while [[ -z "${s3_bucket}" ]]; do
    s3_bucket="$(read_path \
        '' \
        "S3 bucket to back up to (without 's3://' prefix)")"
    if [[ -z "${s3_bucket}" ]]; then
      echo "!!! Bucket name is required. Press ^C to exit."
    fi
  done

  local s3_subpath
  s3_subpath="$(read_path \
      "foundry/worlds" \
      "Path under the S3 bucket to store backup archives")"

  local archive_prefix
  archive_prefix="$(read_path \
      "foundry-worlds-" \
      "Prefix of archive file names")"

  local log_path
  log_path="$(read_path \
      "${HOME}/var/log/backup-foundry.log" \
      "Where to write logs when the backup command runs")"

  echo
  echo "Creating ${install_dir}..."
  # Ensure the installation directory is present, and get its absolute path.
  mkdir -p "${install_dir}"
  install_dir="$(cd "${install_dir}" >/dev/null 2>&1 && pwd )"

  local capture_logs_bin="${install_dir}/capture-logs.sh"
  local backup_bin="${install_dir}/backup-to-s3.sh"

  echo "Installing backup tools..."
  rm -f "${capture_logs_bin}"
  cp -f "${SCRIPT_DIR}/capture-logs.sh" "${capture_logs_bin}"
  chmod u+x "${capture_logs_bin}"

  rm -f "${backup_bin}"
  cp -f "${SCRIPT_DIR}/backup-to-s3.sh" "${backup_bin}"
  chmod u+x "${backup_bin}"

  # Generate the script that cron will invoke.
  local backup_wrapper="${install_dir}/backup-foundry.sh"
  echo "Creating ${backup_wrapper}..."
  rm -f "${backup_wrapper}"
  cat > "${backup_wrapper}" << HERE
#!/bin/bash
# Generated on $(date).
#
# Run this nightly by running 'crontab -e' and adding the line:
#
#     40 3 * * * '${backup_wrapper}'
#
# (without the leading '#')

# The directory to back up.
readonly SRC_DIR='${src_dir}'

# The S3 bucket to back up to.
readonly S3_BUCKET='${s3_bucket}'

# Path under the S3 bucket to store backup archives.
readonly S3_SUBPATH='${s3_subpath}'

# Prefix of archive file names.
readonly ARCHIVE_PREFIX='${archive_prefix}'

# Where to write the output of this tool when it runs.
readonly LOG_PATH='${log_path}'

# cron doesn't typically provide a very good PATH, so hard-code one.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Run the backup script, writing its output to the log.
'${capture_logs_bin}' --log="\${LOG_PATH}" -- \\
    '${backup_bin}' \\
        --src_dir="\${SRC_DIR}" \\
        --s3_bucket="\${S3_BUCKET}" \\
        --s3_subpath="\${S3_SUBPATH}" \\
        --archive_prefix="\${ARCHIVE_PREFIX}" \\
  || echo "${backup_wrapper} failed: see \${LOG_PATH}"
HERE
  chmod u+x "${backup_wrapper}"

  echo "Backup scripts installed to ${install_dir}."
  echo
  echo "To run once a day at 03:40am, run 'crontab -e' and add the line:"
  echo
  echo "40 3 * * * '${backup_wrapper}'"
  echo
}

main "$@"
