#!/bin/bash
# Copyright 2020 Dave Bort (git@dbort.com)
# Use of this source code is governed by a MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT
#
# Runs a command line, capturing output to specified logs.
# Rotates the output log files when they start to get big; old logs are moved
# to have a '.old' extension, overwriting any older logs.
#
# Usage:
#   capture-logs.sh --log=<log> [--errlog=<errlog>] -- <command to run>

set -eu
set -o pipefail

# The name of this program; used in log/error messages.
readonly PROGNAME='capture-logs'

# Rotate logs when they're larger than this, in bytes.
readonly LOG_SIZE_THRESHOLD="$((10 * 1024 * 1024))"

# Default values; may be overridden by commandline options. Don't define vars
# that correspond to required args, so that we'll get an undefined access error
# if someone refers to them when they're not set.
ERRLOG_PATH=''

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
      --longoptions='log:,errlog:' \
      -- "$@")"
  eval set -- "${options}"
  while true; do
    case "$1" in
    --log)
      shift
      LOG_PATH="$1"
      readonly LOG_PATH
      ;;
    --errlog)
      shift
      ERRLOG_PATH="$1"
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

  # The rest of the args is the command we need to run.
  readonly SUBCOMMAND=("$@")

  # Lock down these values now that they've had a chance to be overridden.
  readonly ERRLOG_PATH
}

# Rotates the log file(s) if they're larger than LOG_SIZE_THRESHOLD.
maybe_rotate() {
  if [[ ! -f "${LOG_PATH}" ]]; then
    return
  fi
  local size
  size="$(stat "${LOG_PATH}" --format='%s')"

  if [[ -n "${ERRLOG_PATH}" && -f "${ERRLOG_PATH}" ]]; then
    local errlog_size
    errlog_size="$(stat "${LOG_PATH}" --format='%s')"
    size="$(( size + errlog_size ))"
  fi

  # Rotate both at the same time so they stay in sync.
  if [[ "${size}" -ge "${LOG_SIZE_THRESHOLD}" ]]; then
    mv -f "${LOG_PATH}" "${LOG_PATH}.old"
    if [[ -n "${ERRLOG_PATH}" && -f "${ERRLOG_PATH}" ]]; then
      mv -f "${ERRLOG_PATH}" "${ERRLOG_PATH}.old"
    fi
  fi
}

# print_header <args to run>
# Prints a line with the date and args.
print_header() {
  echo "=== $(date) - Running $@ ==="
}

# print_footer <exit status>
# Prints a line with the date and exit status.
print_footer() {
  echo "=== $(date) - Finished with status $1 ==="
  echo
}

main() {
  parse_args "$@"
  if [[ ! -v LOG_PATH || -z "${LOG_PATH}" ]]; then
    DIE "Must set --log"
  fi

  # Rotate the log files if they're too big.
  maybe_rotate

  # Make sure the directories containing the logs exist.
  mkdir -p "$(dirname "${LOG_PATH}")"
  if [[ -n "${ERRLOG_PATH}" ]]; then
    mkdir -p "$(dirname "${ERRLOG_PATH}")"
  fi

  # Run the command, sending stdout/stderr to the requested files.
  local result=0
  if [[ -z "${ERRLOG_PATH}" ]]; then
    # All output to the same file.
    (
      print_header "${SUBCOMMAND[@]}"
      "${SUBCOMMAND[@]}" || result="$?"
      print_footer "${result}"
    ) >> "${LOG_PATH}" 2>&1
  else
    # Separate files for stdout and stderr.
    print_header "${SUBCOMMAND[@]}" | tee -a "${LOG_PATH}" "${ERRLOG_PATH}"
    "${SUBCOMMAND[@]}" >> "${LOG_PATH}" 2>>"${ERRLOG_PATH}" || result="$?"
    print_footer "${result}" | tee -a "${LOG_PATH}" "${ERRLOG_PATH}"
  fi
  exit "${result}"
}

main "$@"
