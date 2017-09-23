#!/bin/bash
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

NOF_HOSTS=3
HOSTPORT_BASE=33380
NETWORK_NAME="ansible.tutorial"
WORKSPACE="${BASEDIR}/workspace"
TUTORIALS_FOLDER="${BASEDIR}/tutorials"

DOCKER_HOST_IMAGE="turkenh/ubuntu-1604-ansible-docker-host:1.0"
TUTORIAL_IMAGE="turkenh/ansible-tutorial:1.0"

function help() {
    echo -ne "-h, --help              prints this help message
-r, --remove            remove created containers and network 
-t, --test              run lesson tests
"
}
function doesNetworkExist() {
    return $(docker network inspect $1 >/dev/null 2>&1)
}

function removeNetworkIfExists() {
    doesNetworkExist $1 && echo "removing network $1" && docker network rm $1 >/dev/null
}

function doesContainerExist() {
    return $(docker inspect $1 >/dev/null 2>&1)
}

function killContainerIfExists() {
    doesContainerExist $1 && echo "killing container $1" && { docker kill $1 >/dev/null 2>&1; docker rm $1 >/dev/null 2>&1; };
}

function runHostContainer() {
    local name=$1
    local image=$2
    local port=$(($HOSTPORT_BASE + $3))
    echo "starting container ${name}"
    docker run -d -p 127.0.0.1:$port:80 --net ${NETWORK_NAME} --name="${name}" "${image}"
}

function runTutorialContainer() {
    local entrypoint=""
    local args=""
    if [ -n "${TEST}" ]; then
        entrypoint="--entrypoint nutsh"
        args="test /tutorials ${LESSON_NAME}"  
    fi
    echo "starting container ansible.tutorial"
    killContainerIfExists ansible.tutorial
    docker run -it -v ${WORKSPACE}:/root/workspace -v ${TUTORIALS_FOLDER}:/tutorials --net ${NETWORK_NAME} \
      --env HOSTPORT_BASE=$HOSTPORT_BASE \
      ${entrypoint} --name="ansible.tutorial" "${TUTORIAL_IMAGE}" ${args}
    return $?
}

function remove () {
    for ((i = 0; i < $NOF_HOSTS; i++)); do
       killContainerIfExists host$i.example.org
    done
    removeNetworkIfExists ${NETWORK_NAME}
} 

function setupFiles() {
    # step-01/02
    local step_01_hosts_file="${BASEDIR}/tutorials/files/step-1-2/hosts"
    rm -f "${step_01_hosts_file}"
    for ((i = 0; i < $NOF_HOSTS; i++)); do
        #ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' host$i.example.org)
        ip=$(docker network inspect --format="{{range \$id, \$container := .Containers}}{{if eq \$container.Name \"host$i.example.org\"}}{{\$container.IPv4Address}} {{end}}{{end}}" ${NETWORK_NAME} | cut -d/ -f1)
        echo "host$i.example.org ansible_host=$ip ansible_user=root" >> "${step_01_hosts_file}"
    done
}
function init () {
    mkdir -p ${WORKSPACE}
    doesNetworkExist "${NETWORK_NAME}" || { echo "creating network ${NETWORK_NAME}" && docker network create "${NETWORK_NAME}"; }
    for ((i = 0; i < $NOF_HOSTS; i++)); do
       doesContainerExist host$i.example.org || runHostContainer host$i.example.org ${DOCKER_HOST_IMAGE} $i
    done
    setupFiles
    runTutorialContainer
    exit $?
}

###
MODE="init"
TEST=""
for i in "$@"; do
case $i in
    -r|--remove)
    MODE="remove"
    shift # past argument=value
    ;;
    -t|--test)
    TEST="yes"
    shift # past argument=value
    ;;
    -h|--help)
    help
    exit 0
    shift # past argument=value
    ;;
    *)
    echo "Unknow argument ${i#*=}"
    exit 1
esac
done

if [ "${MODE}" == "remove" ]; then
    remove
elif [ "${MODE}" == "init" ]; then
    init
fi
exit 0