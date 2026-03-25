#!/bin/bash

# This script runs all the phenotypic queries in the top-phenotypic-query directory.

trap 'exit 1' INT

ALGORITHMS=""
SLIM_OPT=""
EXTENSION="zip"
JAR=top-phenotypic-query.jar
ADAPTER_CONFIG=adapter.yml

envsubst '$DB_HOST,$DB_PORT,$DB_NAME,$DB_USER,$DB_PASS' < $ADAPTER_CONFIG > "$ADAPTER_CONFIG.prepared"

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

mkdir -p results

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
  echo "Processing model $model"
  file="models/${model}.json"

  if [[ ! -f "$file" ]]; then
    echo "File $file does not exist, skipping..."
    echo
    continue
  fi

  for id in ${model_ids[$model]}; do
    exists=$(jq -e --arg id "$id" '.[] | select(.id == $id)' "$file" > /dev/null; echo $?)
    if [[ $exists -ne 0 ]]; then
      echo "Phenotype $id does not exist in $file, skipping..."
      continue
    fi

    algorithm=$(
      jq -r --arg id "$id" \
        '.[] | select(.id == $id) | (.titles[] | select(.lang == "en") | .text) // .titles[0].text' \
        "$file"
    )

    # Sanitize algorithm name for filename: replace spaces and unsafe chars with underscores
    safe_algorithm=$(echo "$algorithm" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    output_file="results/${model}_${safe_algorithm}.${EXTENSION}"
    echo -n "$algorithm: "
    java -jar "$JAR" query -fn $SLIM_OPT -p "$id" "$file" "$ADAPTER_CONFIG.prepared" -o "$output_file"
  done
  echo
done
