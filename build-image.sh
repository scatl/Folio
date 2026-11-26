#!/usr/bin/env bash
# Cross-platform image build/export (Linux, macOS, Git Bash, WSL).
# Usage: ./build-image.sh
#        ./build-image.sh 0.1.0   # skip tag prompt

set -u
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1

DEFAULT_TAG="0.1.0"
TAG="${1:-}"

prompt_tag() {
  local input=
  printf "Build tag [%s]: " "$DEFAULT_TAG"
  read -r input || true
  if [ -z "${input}" ]; then
    TAG="$DEFAULT_TAG"
  else
    TAG="$input"
  fi
}

do_build() {
  echo
  echo "Building folio:${TAG} ..."
  echo "Ctrl+C stops this build; then press Enter to retry."
  # Subshell + INT trap: Ctrl+C aborts docker without exiting the outer loop.
  (
    trap 'exit 130' INT
    docker build -t "folio:${TAG}" .
  )
}

do_save() {
  mkdir -p .build
  echo "Exporting .build/folio-${TAG}.tar ..."
  (
    trap 'exit 130' INT
    docker save "folio:${TAG}" -o ".build/folio-${TAG}.tar"
  )
}

if [ -z "${TAG}" ]; then
  prompt_tag
fi

while true; do
  if do_build; then
    if do_save; then
      echo
      echo "Done: .build/folio-${TAG}.tar"
    fi
  fi

  echo
  again=
  printf "Press Enter to build again (n to quit): "
  read -r again || true
  case "${again}" in
    [nN]|[nN][oO]) break ;;
  esac
done

exit 0
