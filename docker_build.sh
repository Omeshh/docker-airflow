#!/bin/bash
echo "======> RUNNING $0"
set -e


: ${bamboo_repository_git_branch:?}
: ${bamboo_buildNumber:?}

BRANCH_NAME=$bamboo_repository_git_branch
BRANCH_NAME=$(echo $BRANCH_NAME | awk '{print tolower($0)}' | awk '{ gsub("/","-",$0); print $0 }')

echo "BRANCH_NAME=$BRANCH_NAME"

if [ "$BRANCH_NAME" == "master" ] || [ "$BRANCH_NAME" == "develop" ] || [ "$BRANCH_NAME" == "dev" ]
then
    IMAGE_NAME="docker-airflow"
    version=`cat VERSION`

    TAG=$version
    ENV=${1:-dev}
    git_commit=`git rev-parse --short HEAD`

    REGISTRY="${bamboo_DOCKER_REPO_HOST}/docker-virtual/"
    REGISTRY_EMAIL="devops@domain.com"

    docker_image="$REGISTRY$IMAGE_NAME:$TAG"

    echo "export docker_image=$docker_image" > docker_image.sh
    # echo "version='$version'" > version.sh

    user_id="$(id -u)"

    echo "======> LOGING INTO DOCKER: ${bamboo_DOCKER_REPO_HOST}"
    docker login -e ${REGISTRY_EMAIL} -u ${bamboo_DOCKER_USERNAME} -p ${bamboo_DOCKER_PASSWORD} ${bamboo_DOCKER_REPO_HOST}

    echo "======> BUILDING $docker_image"
    mkdir -p container/files/app/client/
    echo "$version" > container/files/app/client/version.txt
    # build an image from all compiled code
    docker build -t $docker_image .  --build-arg project_version=${version} --build-arg environ=${ENV} --build-arg git_commit=${git_commit}

    echo "======> PUSHING $docker_image"
    docker push $docker_image

    echo "======> REMOVING LOCAL IMAGE"
    docker rmi -f $docker_image
fi