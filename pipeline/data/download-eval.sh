#!/bin/bash
##
# Downloads evaluation datasets
#
# Usage:
#   bash download-eval.sh dir [datasets...]
#

set -x
set -euo pipefail

echo "###### Downloading evaluation datasets"

test -v WORKDIR
test -v TEST_DATASETS

dir=$1


for dataset in "${@:2}"; do
  name="${dataset//[^A-Za-z0-9_- ]/_}"
  bash "${WORKDIR}/pipeline/data/download-corpus.sh" "${dir}/${name}" "${dataset}"

  test -e "${dir}/${name}.${SRC}" || pigz -dk "${dir}/${name}.${SRC}.gz"
  test -e "${dir}/${name}.${TRG}" || pigz -dk "${dir}/${name}.${TRG}.gz"
done


echo "###### Done: Downloading evaluation datasets"
