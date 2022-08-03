#!/bin/bash

COMMIT_SHA=$1
REPO_URL=$2

main() {
  echo "Running source code installation script..."
  echo "Current repository URL: $REPO_URL"
  echo "Current commit SHA: $COMMIT_SHA \n\n\n"

  clean_old_source
  install_source_code
  verify_source
}

clean_old_source() {
  if [ -d "/home/ansible/derivative-maker" ]; then
    rm -rf /home/ansible/derivative-maker
  fi
}

install_source_code() {
  cd /home/ansible
  # TODO: Set to upstream repo instead of mycobee
  git clone --recurse-submodules --jobs=4 --shallow-submodules --depth=1 https://github.com/$REPO_URL
  cd /home/ansible/derivative-maker 
  git fetch --all --tags
  git pull origin $COMMIT_SHA
}

verify_source() {
  # TODO: Set up commit verification with upstream keys
  # git verify-commit $COMMIT_SHA
  git checkout --recurse-submodules $COMMIT_SHA 
}

main
