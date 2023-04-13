#!/bin/bash
##
# Cleans corpus using bicleaner-ai or bicleaner
#

set -x
set -euo pipefail

echo "###### Bicleaner filtering"

test -v SRC
test -v TRG
test -v CUDA_DIR
test -v CUDNN_DIR

# cuda and cudnn libs
export LD_LIBRARY_PATH=${CUDA_DIR}/lib64:${CUDNN_DIR}:${LD_LIBRARY_PATH:+LD_LIBRARY_PATH:}

corpus_prefix=$1
output_prefix=$2
bicleaner_threshold=$3
type=$4
threads=$5
pack_dir=$6

if [ "$threads" = "auto" ]; then
  threads=$(nproc)
fi

output_dir=$(dirname "${output_prefix}")
mkdir -p "${output_dir}"

if [ "${bicleaner_threshold}" == "0" ]; then
  echo "Threshold is 0, skipping filtering"
  cp "${corpus_prefix}.${SRC}.zst" "${output_prefix}.${SRC}.zst"
  cp "${corpus_prefix}.${TRG}.zst" "${output_prefix}.${TRG}.zst"
else
  if [ "${type}" == 'bicleaner-ai' ]; then
    echo "### Using bicleaner-ai"
    cmd=bicleaner-ai-classify
  elif [ "${type}" == 'bicleaner' ]; then
    echo "### Using bicleaner"
    cmd=bicleaner-classify
  else
    echo "### Unsupported type: ${type}"
    exit 1
  fi

  export scol=1
  export tcol=2
  if [ -d "${pack_dir}/${TRG}-${SRC}" ]; then
    export scol=2
    export tcol=1
  fi

  #Export cuda visible devices if empty or not set
  if [ -z "${CUDA_VISIBLE_DEVICES:-}" ]; then
    export CUDA_VISIBLE_DEVICES=$(nvidia-smi --query-gpu=index --format=csv,noheader);
  fi

  echo "### Classifying"
  if [[ "${type}" == 'bicleaner-ai' && ${#CUDA_VISIBLE_DEVICES} > 1 ]]; then # Use gnu-parallel'd bicleaner-ai if we have more than 1 GPU
       #Convert CUDA_VISIBLE_DEVICES to an array
       export CUDA_VISIBLE_ARRAY=(${CUDA_VISIBLE_DEVICES//,/ })
       #Turn on tensorflow logging in bicleaner-ai
       export TF_CPP_MIN_LOG_LEVEL=0
       #This function expects a bicleaner yaml and a 1-based index into the CUDA_VISIBLE_ARRAY
       #Example: /mnt/nanna0/nbogoych/data/data/fr-en/fr-en-prod/biclean/pack/metadata.yaml index_in_CUDA_VISIBLE_ARRAY+1
       biclean() {
               export CUDA_VISIBLE_ARRAY=(${CUDA_VISIBLE_DEVICES//,/ })
               export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_ARRAY[$(($2-1))]}
               bicleaner-ai-classify --scol ${scol} --tcol ${tcol} - - $1
       }
       export -f biclean
       # {%} is a 1-indexed job slot number from GNU parallel.  We use that as the 1-indexed offset in CUDA_VISIBLE_ARRAY
       paste <(zstdmt -dc "${corpus_prefix}.${SRC}.zst") <(zstdmt -dc "${corpus_prefix}.${TRG}.zst") |
       parallel -j ${#CUDA_VISIBLE_ARRAY[@]} --pipe -k --block 10M biclean "${pack_dir}"/*.yaml {%} |
       zstdmt >"${output_prefix}.scored.zst"
  else
   paste <(zstdmt -dc "${corpus_prefix}.${SRC}.zst") <(zstdmt -dc "${corpus_prefix}.${TRG}.zst") |
     ${cmd} --scol ${scol} --tcol ${tcol} --processes "${threads}"  - - "${pack_dir}"/*.yaml |
     zstdmt >"${output_prefix}.scored.zst"
  fi

  echo "### Filtering"
  zstdmt -dc "${output_prefix}.scored.zst" |
    awk -v threshold=${bicleaner_threshold} -F"\t" '{if ($3>threshold) {print $0}}' |
    zstdmt >"${output_prefix}.best.zst"

  echo "Lines before filtering: $(zstdmt -dc "${output_prefix}.scored.zst" | wc -l)"
  echo "Lines after filtering: $(zstdmt -dc "${output_prefix}.best.zst" | wc -l)"

  echo "### Writing output corpus"
  zstdmt -dc "${output_prefix}.best.zst" |
    tee >(cut -f1 | zstdmt >"${output_prefix}.${SRC}.zst") |
    cut -f2 | zstdmt >"${output_prefix}.${TRG}.zst"

  # do not delete intermediate files to inspect them and tune the threshold
fi

echo "###### Done: Bicleaner filtering"
