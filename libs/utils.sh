#!/bin/false
##############################
# misc utility library
##############################
[ -v UTILS_LIB_READY ] && return 0
UTILS_LIB_READY=1

# some useful context variables
UTILS_LIB_FILE=$PWD/${BASH_SOURCE[0]}
UTILS_LIB_PATH=${UTILS_LIB_FILE%/*}
BAMBOO_UTILS_LIB_PATH=${UTILS_LIB_PATH%/*}

# lib functions below #
