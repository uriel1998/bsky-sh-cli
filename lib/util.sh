#!/bin/sh
# Bluesky in the shell
# A Bluesky CLI (Command Line Interface) implemented with shell script
# Author Bluesky:@billsbs.bills-appworks.net
# 
# Copyright (c) 2024 bills-appworks
# This software is released under the MIT License.
# http://opensource.org/licenses/mit-license.php
FILE_DIR=`dirname "$0"`
FILE_DIR=`(cd "${FILE_DIR}" && pwd)`

BSKYSHCLI_DEBUG_ROOT_PATH="${TOOLS_WORK_DIR}"
BSKYSHCLI_DEBUG_LOG_FILEPATH="${TOOLS_WORK_DIR}/bsky_sh_cli_debug.log"
BSKYSHCLI_DEBUG_SINGLE=''

# variable use at this file include(source) script
# shellcheck disable=SC2034
BSKYSHCLI_DEFAULT_DOMAIN='.bsky.social'

SESSION_FILENAME_DEFAULT_PREFIX='_bsky_sh_cli'
SESSION_FILENAME_SUFFIX='_session'
SESSION_DIR="${TOOLS_WORK_DIR}"
SESSION_KEY_HANDLE='SESSION_HANDLE'
SESSION_KEY_ACCESS_JWT='SESSION_ACCESS_JWT'
SESSION_KEY_REFRESH_JWT='SESSION_REFRESH_JWT'

## for restore (keeping) original JSON response 
##  in script expanded escape sequence at function/command return value by echo to standard output
## strategy:
##   no calibration
##     caller(){VAR1=`callee`} calls callee(){...;echo "${VAR2}"} and return to caller()
##       caller receive in $VAR1  <-  callee return in $VAR2
##         \"                     <-    \"
##         \a                     <-    \\a
##         \n                     <-    \\n
##         (line break)           <-    \n
##         (line break)           <-    (line break)
##   do calibration
##     caller(){VAR1=`callee`} calls callee(){...;echo "${VAR2}" | $ESCAPE_BSKYSHCLI and return to caller()
##       caller receive in $VAR1  <-  callee return in $VAR2 (after process ESCAPE_BSKYSHCLI) <- callee original $VAR (before process ESCAPE_BSKYSHCLI)
##         \"                     <-    \"                                                    <-   \"
##         \\a                    <-    \\\\a                                                 <-   \\a
##         \\n                    <-    \\\\n                                                 <-   \\n
##         (line break)           <-    \n                                                    <-   \n
##         (line break)           <-    \n                                                    <-   (line break)
##   doing calibration each function layers
##   this logic is original \n(non escaped newline escape sequence literally) lacks and mix together with line break (0x0A)
##   this code assuming there are no line breaks in the original JSON
##
# (line break) -> \n(literally), \n(literally) at the end of line -> (remove)
# using GNU sed -z option
ESCAPE_NEWLINE_PATTERN='s/\n/\\n/g;s/\\n$//g'
ESCAPE_NEWLINE="sed -z ${ESCAPE_NEWLINE_PATTERN}"
# \\ -> \\\\ (literally in left variable of VAR=`echo "${VAR}" | $ESCAPE_DOUBLEBACKSLASH`)
ESCAPE_DOUBLEBACKSLASH_PATTERN='s/\\\\/\\\\\\\\/g'
# variable use at this file include(source) script
# shellcheck disable=SC2034
ESCAPE_DOUBLEBACKSLASH="sed ${ESCAPE_DOUBLEBACKSLASH_PATTERN}"
# using GNU sed -z option
# variable use at this file include(source) script
# shellcheck disable=SC2034
ESCAPE_BSKYSHCLI="sed -z ${ESCAPE_DOUBLEBACKSLASH_PATTERN};${ESCAPE_NEWLINE_PATTERN}"

get_timestamp()
{
  date '+%Y/%m/%d %H:%M:%S'
}

debug_mode_suppress()
{
  EVACUATED_BSKYSHCLI_DEBUG="${BSKYSHCLI_DEBUG}"
  BSKYSHCLI_DEBUG=0
}

debug_mode_restore()
{
  BSKYSHCLI_DEBUG="${EVACUATED_BSKYSHCLI_DEBUG}"
}

debug()
{
  ID="$1"
  MESSAGE="$2"

  if [ "${BSKYSHCLI_DEBUG:=0}" -eq 1 ]
  then
    TIMESTAMP=`get_timestamp`
    echo "${TIMESTAMP} ${ID}: ${MESSAGE}" >> "${BSKYSHCLI_DEBUG_LOG_FILEPATH}"
  fi
}

debug_single()
{
  FILE="$1"

  if [ "${BSKYSHCLI_DEBUG:=0}" -eq 1 ]
  then
    BSKYSHCLI_DEBUG_SINGLE="${BSKYSHCLI_DEBUG_ROOT_PATH}/${FILE}"
  else
    BSKYSHCLI_DEBUG_SINGLE='/dev/null'
  fi
}

debug_json()
{
  ID="$1"
  JSON="$2"

  if [ "${BSKYSHCLI_DEBUG:=0}" -eq 1 ]
  then
    MESSAGE=`echo "${JSON}" | jq`
    debug "${ID}" "${MESSAGE}"
  fi
}

error()
{
  MESSAGE="$1"

  echo "ERROR: ${MESSAGE}" 1>&2
  exit 1
}

api_core()
{
  API="$1"
  # various API params continue

  debug 'api_core' 'START'
  debug 'api_core' "API:${API}"

  shift
  debug_single 'api_core-1'
  # BSKYSHCLI_API_PARAM use in API script
  # shellcheck disable=SC2034
  BSKYSHCLI_API_PARAM="$*"
  # SC1090 disable for dynamical(variable) path source(.) using
  # shellcheck source=/dev/null
  RESULT=`. "${TOOLS_ROOT_DIR}"/lib/api/"${API}" | $ESCAPE_BSKYSHCLI | tee "${BSKYSHCLI_DEBUG_SINGLE}"`
  ERROR=`echo "${RESULT}" | $ESCAPE_NEWLINE | jq -r '.error // empty'`
  if [ -n "$ERROR" ]
  then
    debug 'api_core' "ERROR:${ERROR}"
    case "${ERROR}" in
      ExpiredToken)
        # TODO: refresh session
        #error 'session expired (session auto refresh not yet implemented).'
        return 2
        ;;
      *)
        error "unknown error: ${ERROR}"
        ;;
    esac
  fi

  if [ -n "${RESULT}" ]
  then
    debug_single 'api_core-2'
    echo "${RESULT}" | $ESCAPE_BSKYSHCLI | tee "${BSKYSHCLI_DEBUG_SINGLE}"
  fi

  debug 'api_core' 'END'
  return 0
}

api()
{
  # TODO: retry any time for api_core error
  API="$1"
  # various API params continue

  debug 'api' 'START'
  debug 'api' "API:${API}"

  RESULT=`api_core "$@"`
  STATUS=$?
  debug_single 'api-1'
  RESULT=`echo "${RESULT}" | $ESCAPE_BSKYSHCLI | tee "${BSKYSHCLI_DEBUG_SINGLE}"`
  debug 'api' "api_core status: ${STATUS}"
  case $STATUS in
    0)
      debug_single 'api-2'
      echo "${RESULT}" | $ESCAPE_BSKYSHCLI | tee "${BSKYSHCLI_DEBUG_SINGLE}"
      ;;
    1)
      error "unknown error: ${ERROR}"
      ;;
    2)
      # session expired
      read_session_file
      api_core 'com.atproto.server.refreshSession' "${SESSION_REFRESH_JWT}" > /dev/null
      debug_single 'api-3'
      api_core "$@" | $ESCAPE_DOUBLEBACKSLASH | tee "${BSKYSHCLI_DEBUG_SINGLE}"
      ;;
  esac

  debug 'api' 'END'
}

verify_profile_name()
{
  PROFILE="$1"

  debug 'verify_profile_name' 'START'
  debug 'verify_profile_name' "PROFILE:${PROFILE}"

  VERIFY=`echo "${PROFILE}" | sed 's/^[A-Za-z0-9][A-Za-z0-9._-]*//g'`
  if [ -n "${VERIFY}" ]
  then
    error "invalid profile name '${PROFILE}' : must be start with alphanumeric and continue alphanumeric or underscore or hyphen or period"
  fi

  debug 'verify_profile_name' 'END'
}

get_session_filepath()
{
  debug 'get_session_filepath' 'START'
  if [ -n "${BSKYSHCLI_GLOBAL_OPTION_PROFILE}" ]
  then
    SESSION_FILENAME="${BSKYSHCLI_GLOBAL_OPTION_PROFILE}${SESSION_FILENAME_SUFFIX}"
  else
    SESSION_FILENAME="${SESSION_FILENAME_DEFAULT_PREFIX}${SESSION_FILENAME_SUFFIX}"
  fi

  SESSION_FILEPATH="${SESSION_DIR}/${SESSION_FILENAME}"

  debug 'get_session_filepath' "SESSION_FILEPATH:${SESSION_FILEPATH}"
  debug 'get_session_filepath' 'END'

  echo "${SESSION_FILEPATH}"
}

create_session_info()
{
  OPS="$1"
  HANDLE="$2"
  ACCESS_JWT="$3"
  REFRESH_JWT="$4"

  debug 'create_session_info' 'START'

  debug 'create_session_info' "PROFILE: ${PROFILE}"
  debug 'create_session_info' "UPDATE_MODE: ${UPDATE_MODE}"
  debug 'create_session_info' "HANDLE: ${HANDLE}"
  if [ -n "${ACCESS_JWT}" ]
  then
    MESSAGE='(specified)'
  else
    MESSAGE='(empty)'
  fi
  debug 'create_session_info' "ACCESS_JWT: ${MESSAGE}"
  if [ -n "${REFRESH_JWT}" ]
  then
    MESSAGE='(specified)'
  else
    MESSAGE='(empty)'
  fi
  debug 'create_session_info' "REFRESH_JWT: ${MESSAGE}"

  TIMESTAMP=`get_timestamp`
  echo "# session ${OPS} at ${TIMESTAMP}"
  echo "${SESSION_KEY_HANDLE}=${HANDLE}"
  echo "${SESSION_KEY_ACCESS_JWT}=${ACCESS_JWT}"
  echo "${SESSION_KEY_REFRESH_JWT}=${REFRESH_JWT}"

  debug 'create_session_info' 'END'
}

create_session_file()
{
  HANDLE="$1"
  ACCESS_JWT="$2"
  REFRESH_JWT="$3"

  debug 'create_session_file' 'START'
  debug 'create_session_file' "HANDLE:${HANDLE}"
# WARNING: parameters may contain sensitive information (e.g. session token) and will remain in the debug log
#  debug 'create_session_file' "ACCESS_JWT:${ACCESS_JWT}"
#  debug 'create_session_file' "REFRESH_JWT:${REFRESH_JWT}"

  SESSION_FILEPATH=`get_session_filepath`
  create_session_info 'create' "${HANDLE}" "${ACCESS_JWT}" "${REFRESH_JWT}" > "${SESSION_FILEPATH}"

  debug 'create_session_file' 'END'
}

read_session_file()
{
  debug 'read_session_file' 'START'

  SESSION_FILEPATH=`get_session_filepath`
  if [ -e "${SESSION_FILEPATH}" ]
  then
    # SC1090 disable for dynamial(variable) path source(.) using
    # shellcheck source=/dev/null
    . "${SESSION_FILEPATH}"
  else
    error "session not found: ${SESSION_FILEPATH}"
  fi

  debug 'read_session_file' 'END'
}

update_session_file()
{
  HANDLE="$1"
  ACCESS_JWT="$2"
  REFRESH_JWT="$3"

  debug 'update_session_file' 'START'

  SESSION_FILEPATH=`get_session_filepath`
  case $BSKYSHCLI_SESSION_FILE_UPDATE in
    append)
      create_session_info 'update' "${HANDLE}" "${ACCESS_JWT}" "${REFRESH_JWT}" >> "${SESSION_FILEPATH}"
      ;;
    overwrite|*)
      create_session_info 'update' "${HANDLE}" "${ACCESS_JWT}" "${REFRESH_JWT}" > "${SESSION_FILEPATH}"
      ;;
  esac

  debug 'update_session_file' 'END'
}

clear_session_file()
{
  debug 'clear_session_file' 'START'

  SESSION_FILEPATH=`get_session_filepath`
  if [ -e "${SESSION_FILEPATH}" ]
  then
    rm -f "${SESSION_FILEPATH}"
  fi

  debug 'clear_session_file' 'END'
}

