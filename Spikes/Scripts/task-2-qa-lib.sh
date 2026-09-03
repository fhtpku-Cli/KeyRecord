#!/usr/bin/env bash

task2_run_logged() {
  local log_file="$1"
  shift
  local status
  local restore_errexit=false

  printf '$' >>"$log_file"
  printf ' %q' "$@" >>"$log_file"
  printf '\n' >>"$log_file"
  [[ $- == *e* ]] && restore_errexit=true
  set +e
  "$@" >>"$log_file" 2>&1
  status=$?
  if [[ "$restore_errexit" == true ]]; then
    set -e
  fi
  printf 'exit_status=%s\n' "$status" >>"$log_file"
  return "$status"
}

task2_privacy_scan() {
  jq -e '[.. | objects | keys[]] | all(.[]; (ascii_downcase | test("serial|keystream|credential|eventsequence|username")) | not)' "$1"
}
