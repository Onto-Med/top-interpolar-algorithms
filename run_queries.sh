#!/bin/bash

# This script runs all the phenotypic queries in the top-phenotypic-query directory.

trap 'exit 1' INT

ALGORITHMS=""
SLIM_OPT=""
EXTENSION="zip"
JAR=top-phenotypic-query.jar
ADAPTER_CONFIG=adapter.yml
SUMMARY_FILE="results/outputGlobal/summary.txt"
CALL_FILE="results/outputLocal/call.txt"
RETENTION_LIMIT="${RETENTION_LIMIT:-5}"

# This function takes a directory path as argument.
# If the directory exists, it will be archived with create time stamp appended to the archive file name.
# After archiving, the directory is deleted and a fresh one is created.
# Archiving and deletion are skipped if the directory did not exist.
archive_or_prepare_output_dir() {
  local target_dir="$1"
  local dir_name="$(basename "$target_dir")"
  local parent_dir="$(dirname "$target_dir")"

  if [[ -z "$target_dir" ]]; then
    echo "Error [archive_or_prepare_output_dir]: No path provided!" >&2
    return 1
  fi

  if [[ -d "$target_dir" ]]; then
    local created_time
    local date_stamp

    if created_time=$(stat -c %w "$target_dir" 2>/dev/null) && [[ "$created_time" != "-" ]]; then
        date_stamp=$(date -d "$created_time" +"%Y-%m-%d_%H-%M-%S" 2>/dev/null)
    else
        date_stamp=$(date -r "$target_dir" +"%Y-%m-%d_%H-%M-%S")
    fi

    local archive_name="${dir_name}_${date_stamp}.tar.gz"
    local archive_path="${parent_dir}/${archive_name}"

    if tar -czf "$archive_path" -C "$parent_dir" "$dir_name"; then
      rm -rf "$target_dir"
      cleanup_old_archives "$parent_dir" "$dir_name" || (echo "Error: Cleanup failed" && return 1)
    else
      echo "Error [archive_or_prepare_output_dir]: Compression of existing output directory failed!" >&2
      return 1
    fi
  fi

  mkdir -p "$target_dir"
  return 0
}

cleanup_old_archives() {
  local parent_dir="$1"
  local dir_name="$2"
  local archive_pattern="${dir_name}_*.tar.gz"

  local files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(ls -1t "$parent_dir/"$archive_pattern 2>/dev/null)

  local total_files=${#files[@]}
  if (( total_files > RETENTION_LIMIT )); then
    for (( i=RETENTION_LIMIT; i < total_files; i++ )); do
      rm -f "${files[i]}"
    done
  fi
}

archive_or_prepare_output_dir "results/outputLocal" || exit 1
archive_or_prepare_output_dir "results/outputGlobal" || exit 1

envsubst '$DB_HOST,$DB_PORT,$DB_NAME,$DB_USER,$DB_PASS' < $ADAPTER_CONFIG > "$ADAPTER_CONFIG.prepared"

URL=$(yq ".connection.url" "$ADAPTER_CONFIG.prepared")
USER=$(yq ".connection.user" "$ADAPTER_CONFIG.prepared")

echo "CALL: $0 $@" | tee -a "$CALL_FILE"
echo "URL: $URL" | tee -a "$CALL_FILE"
echo "USER: $USER" | tee -a "$CALL_FILE"
echo

while [[ "$1" == --* ]]; do
  case "$1" in
    --algorithms)
      [[ -n "$2" ]] && ALGORITHMS="$2" && shift 2 || shift
      ;;
    --slim)
      SLIM_OPT="--slim"
      EXTENSION="csv"
      shift
      ;;
    *)
      break
      ;;
  esac
done

declare -A model_ids

if [[ -n "$ALGORITHMS" && -f "$ALGORITHMS" ]]; then
  echo "Reading algorithms from CSV file: $ALGORITHMS"
  while IFS=, read -r model phenotype_id || [ -n "$model" ]; do
    [[ $model == "model" ]] && continue
    model_ids["$model"]+="$phenotype_id "
  done < "$ALGORITHMS"
else
  echo "No CSV file provided or file does not exist, processing all models in ./models/*.json"
  echo
  for file in ./models/*.json; do
    model=$(basename "$file" .json)
    model_ids["$model"]=$(
      jq -r \
        '[.[] | select(.entityType == "composite_phenotype" and .dataType == "boolean")] | sort_by((.titles[] | select(.lang == "en") | .text) // .titles[0].text) | .[] | .id' \
        "$file"
    )
  done
fi

sorted_keys=($(printf "%s\n" "${!model_ids[@]}" | sort))

for model in ${sorted_keys[@]}; do
  echo "Processing model $model" | tee -a "$SUMMARY_FILE"
  file="models/${model}.json"

  if [[ ! -f "$file" ]]; then
    echo "File $file does not exist, skipping..." | tee -a "$SUMMARY_FILE"
    echo | tee -a "$SUMMARY_FILE"
    continue
  fi

  for id in ${model_ids[$model]}; do
    exists=$(jq -e --arg id "$id" '.[] | select(.id == $id)' "$file" > /dev/null; echo $?)
    if [[ $exists -ne 0 ]]; then
      echo "Phenotype $id does not exist in $file, skipping..." | tee -a "$SUMMARY_FILE"
      continue
    fi

    algorithm=$(
      jq -r --arg id "$id" \
        '.[] | select(.id == $id) | (.titles[] | select(.lang == "en") | .text) // .titles[0].text' \
        "$file"
    )

    # Sanitize algorithm name for filename: replace spaces and unsafe chars with underscores
    safe_algorithm=$(echo "$algorithm" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    output_file="results/outputLocal/${model}_${safe_algorithm}.${EXTENSION}"
    echo -n "$algorithm: " | tee -a "$SUMMARY_FILE"
    java -jar "$JAR" query -fn $SLIM_OPT -p "$id" "$file" "$ADAPTER_CONFIG.prepared" -o "$output_file" > >(tee -a "$SUMMARY_FILE") 2>&1
  done
  echo | tee -a "$SUMMARY_FILE"
done
