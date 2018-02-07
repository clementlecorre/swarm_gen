#!/bin/bash
# Github: https://github.com/clementlecorre/swarm_gen
# Maintainer: clement@le-corre.eu
# Description: Bash script to deploy a swarm infrastructure using docker-machine

color_cyan='\033[36m'
color_reset='\033[0m'
color_red='\033[31m'

worker_basename=worker
manager_basename=manager

managers=3
workers=3

action=(remove deploy evalconfig)
chosen_action=""

function usage()
{
    echo "Bash script to deploy a swarm infrastructure using docker-machine"
    echo ""
    echo -e "$0"
    echo -e "\t-h --help"
    echo -e "\t--action=${action[*]}"
    echo -e "\t-m --managers=${managers}"
    echo -e "\t-w --workers=${workers}"

    echo ""
}
function action_remove() {
  echo -e "${color_cyan}\t=> Remove $managers manager machines ...${color_reset}"
  for node in $(seq 1 $managers)
  do
  	echo -e "${color_cyan}\t=> Remove ${manager_basename}${node} machine ...${color_reset}"
    docker-machine stop ${manager_basename}${node}
  	docker-machine rm -y ${manager_basename}${node}
  done
  echo -e "${color_cyan}\t=> Remove $workers worker machines ...${color_reset}"
  for node in $(seq 1 $workers)
  do
  	echo -e "${color_cyan}\t=> Remove ${worker_basename}${node} machine ...${color_reset}"
    docker-machine stop ${worker_basename}${node}
    docker-machine rm -y ${worker_basename}${node}
  done
}
function action_deploy() {
  echo -e "${color_cyan}\t=> Creating $managers manager ...${color_reset}"
  for node in $(seq 1 $managers)
  do
  	echo -e "${color_cyan}\t=> Creating ${manager_basename}${node} ...${color_reset}"
  	docker-machine create -d virtualbox ${manager_basename}${node}
  done

  # create worker machines
  echo -e "${color_cyan}\t=> Creating $workers worker ...${color_reset}"
  for node in $(seq 1 $workers)
  do
  	echo -e "${color_cyan}\t=> Creating ${worker_basename}${node} machine ...${color_reset}"
  	docker-machine create -d virtualbox ${worker_basename}${node}
  done

  # initialize swarm mode and create a manager
  echo -e "${color_cyan}\t=> Initializing first swarm manager ...${color_reset}"
  docker-machine ssh ${manager_basename}1 "docker swarm init --listen-addr $(docker-machine ip ${manager_basename}1) --advertise-addr $(docker-machine ip ${manager_basename}1)"

  # get manager and worker tokens
  export m_token=`docker-machine ssh ${manager_basename}1 "docker swarm join-token manager -q"`
  export w_token=`docker-machine ssh ${manager_basename}1 "docker swarm join-token worker -q"`

  # other masters join swarm
  for node in $(seq 2 $managers);
  do
  	echo -e "${color_cyan}\t=> ${manager_basename}${node} joining swarm as manager ...${color_reset}"
  	docker-machine ssh ${manager_basename}${node} \
  		"docker swarm join \
  		--token $m_token \
  		--listen-addr $(docker-machine ip ${manager_basename}${node}) \
  		--advertise-addr $(docker-machine ip ${manager_basename}${node}) \
  		$(docker-machine ip ${manager_basename}1)"
  done

  # workers join swarm
  for node in $(seq 1 $workers);
  do
  	echo -e "${color_cyan}\t=> ${worker_basename}${node} joining swarm as worker ...${color_reset}"
  	docker-machine ssh ${worker_basename}${node} \
  	"docker swarm join \
  	--token $w_token \
  	--listen-addr $(docker-machine ip ${worker_basename}${node}) \
  	--advertise-addr $(docker-machine ip ${worker_basename}${node}) \
  	$(docker-machine ip ${manager_basename}1):2377"
  done

  echo "m_token: $m_token"
  echo "w_token: $w_token"
  # show members of swarm
  docker-machine ssh ${manager_basename}1 "docker node ls"
}
function action_evalconfig() {
  echo -e "${color_cyan}\t=> Get docker config ...${color_reset}"
  docker-machine env --shell bash ${manager_basename}1
  eval $(docker-machine env --shell bash ${manager_basename}1)
}
while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        --action)
            chosen_action=$VALUE
            ;;
        -m |--managers)
            managers=$VALUE
            ;;
        -w |--workers)
            workers=$VALUE
            ;;
        *)
            echo "${color_red}ERROR: unknown parameter \"$PARAM\"${color_reset}"
            usage
            exit 1
            ;;
    esac
    shift
done


for a in "${action[@]}"
do
  if [[ "${a}" == "${chosen_action}" ]]; then
    action_${a}
    find=1
  fi
done

if [[ ${find} != 1 ]]; then
  usage
fi
