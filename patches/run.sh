#!/bin/bash
PATCH_DIR=$(dirname $0)
for PATCH_FILE in $(find ${PATCH_DIR} -name "*.patch*"); do
    PATCH=$(basename ${PATCH_FILE})
    DEP_NAME=${PATCH%%.*}
    patch -N -p1 -d ${REBAR_DEPS_DIR}/${DEP_NAME}/ < ${PATCH_FILE} || true
done
