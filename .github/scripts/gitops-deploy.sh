#!/bin/bash
set -euo pipefail
echo 'Deploying....'

export KEYFILE="$(mktemp)"
echo "$RPI_GIT_DEPLOY_KEY" > "$KEYFILE"
cd /
GIT_SSH_COMMAND='ssh -i "$KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' git clone git@github.com:benjvi/rpi-k8s.git
cd -

IMG_VERSION="$(git rev-parse --short=8 HEAD)"
# TODO: add kshard in here
echo "$IMG_VERSION"
cd _deploy/k8s
kustomize edit set image "benjvi/blog-arm=benjvi/blog-arm:${IMG_VERSION}"
kustomize build . > /rpi-k8s/sync/prod/blog/k8s-blog/package.yml
yshard --help
# need some details set in env for prify to work correctly
# not all context is kept between sh commands, so use a one liner
cd -
cd /rpi-k8s/sync/prod
pwd
ls
git config user.email "benjvi.github.io@ghactions"
git config user.name "GH Actions CI Bot - Blog"
GIT_SSH_COMMAND='ssh -i "$KEYFILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' prify run
rm $KEYFILE 
