#!/usr/bin/env bash

set -euo pipefail
shopt -s dotglob globstar nullglob
LOG="$(mktemp)"

escre() {
  sed -E 's/[](){}[\\.*+?|^$]/\\&/g' <<< "$*"
}

escsub() {
  sed -E 's/[\\|&]/\\&/g' <<< "$*"
}

extract() {
  local fmt="$1" files=("${@:2}")

  case "$fmt" in
    dockerfile) sed -En "s|^FROM.* (\S+):(\S+).*|\1 \2|p" "${files[@]}" ;;
    docker-compose) sed -En "s|^\s*image: (\S+):(\S+).*|\1 \2|p" "${files[@]}" ;;
    github-workflow) sed -En "s|^\s*-? uses: (\S+)@(\S+).*|\1 \2|p" "${files[@]}" ;;
  esac
}

insert() {
  local fmt="$1" files=("${@:2}") name old new

  while read -r name old new; do
    case "$fmt" in
      dockerfile) sed -Ei "s|^(FROM.*) $(escre "$name:$old")|\1 $(escsub "$name:$new")|" "${files[@]}" ;;
      docker-compose) sed -Ei "s|^(\s*image:) $(escre "$name:$old")|\1 $(escsub "$name:$new")|" "${files[@]}" ;;
      github-workflow) sed -Ei "s|^(\s*-? uses:) $(escre "$name@$old")|\1 $(escsub "$name@$new")|" "${files[@]}" ;;
    esac
  done
}

versions() {
  local src="$1" name="$2"

  case "$src" in
    docker) crane ls "$name" ;;
    github) git ls-remote --tags --refs "https://github.com/$(cut -d / -f 1-2 <<< "$name")" | sed -n "s|.*refs/tags/||p" ;;
  esac
}

latest() {
  local src="$1" name old

  while read -r name old; do
    local pattern="${old%%-*}" new
    pattern="$(escre "$pattern" | sed -E "s/[0-9]+/[0-9]+/g")"

    if [[ $old == *-* ]]; then pattern+="-$(escre "${old#*-}")"; fi
    new="$(versions "$src" "$name" | { grep -E "^$pattern$" || (($? == 1)); } | sort -V | tail -n 1)"

    if [[ $new && $new != "$old" ]]; then
      echo "$name $old $new"
      echo "$src $name $old $new" >> "$LOG"
    fi
  done
}

update() {
  local src="$1" fmt="$2" files=("${@:3}")

  if ((${#files[@]})); then
    extract "$fmt" "${files[@]}" | sort -u | latest "$src" | insert "$fmt" "${files[@]}"
    git add "${files[@]}"
  fi
}

summary() {
  local src name old new last=""

  while read -r src name old new; do
    if [[ $src != "$last" ]]; then
      if [[ $last ]]; then echo -e "\n"; fi
      echo "- **${src^}**"
      last="$src"
    fi

    echo "  - \`$name\`: $old → $new"
  done
}

update docker dockerfile ./**/Dockerfile
update docker docker-compose ./**/compose.yaml
update github github-workflow .github/workflows/*.yaml

if [[ -f .gitmodules ]]; then
  git submodule update --init --remote
  git submodule status | sed -En "s/^\+\S+ (\S+) \S+$/\1/p" | xargs -r git add
  git submodule summary | sed -En "s/^\* (\S+) (\S+)\.\.\.(\S+).*/gitmodule \1 \2 \3/p" >> "$LOG"
fi

if ! git diff --staged --quiet; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"

  sort -u "$LOG" | summary > "$GITHUB_STEP_SUMMARY"
  git commit --message "chore(deps): automatic update" --message "$(< "$GITHUB_STEP_SUMMARY")"
fi
