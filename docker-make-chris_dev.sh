#!/bin/bash
#
# NAME
#
#   docker-make-chris_dev.sh
#
# SYNPOSIS
#
#   docker-make-chris_dev.sh [-r <service>] [-p] [-s] [-i] [local|fnndsc[:dev]]
#
# DESC
# 
#   'docker-make-chris_dev.sh' is the main entry point for instantiating a 
#   complete backend dev environment.
#
#   It creates a pattern of directories and symbolic links that reflect the
#   declarative environment of the docker-compose.yml contents.
#
# ARGS
#
#   -r <service>
#   
#       Restart <service> in interactive mode. This is mainly for debugging
#       and is typically used to restart the 'pfcon', 'pfioh', and 'pman' 
#       services.
#
#   -i 
#
#       Optional do not restart final chris_dev in interactive mode. If any
#       sub services have been restarted in interactive mode then this will
#       break the final restart of the chris_dev container. Thus, if any
#       services have been restarted with '-r <service>' it is recommended
#       to also use this flag to avoid the chris_dev restart.
#
#   -s
#
#       Optional skip intro steps. This skips the check on latest versions
#       of containers and the interval version number printing. Makes for
#       slightly faster startup.
#
#   -p
#   
#       Optional pause after instantiating system to allow user to stop
#       and restart services in interactive mode. User stops and restarts
#       services explicitly with
#
#               docker stop <ID> && docker rm -vf <ID> && *make* -r <service> 
#
#   [local|fnndsc[:dev]] (optional, default = 'fnndsc')
#
#       If specified, denotes the container "family" to use.
#
#       If a colon suffix exists, then this is interpreted to further
#       specify the TAG, i.e :dev in the example above.
#
#       The 'fnndsc' family are the containers as hosted on docker hub. 
#       Using 'fnndsc' will always attempt to pull the latest container first.
#
#       The 'local' family are containers that are assumed built on the local
#       machine and assumed to exist. The 'local' containers are used when
#       the 'pfcon/pman/pfioh/pfurl' services are being locally 
#       developed/debugged.
#
#       


source ./decorate.sh 

declare -i STEP=0
declare -i b_restart=0
declare -i b_pause=0
declare -i b_skip=0
declare -i b_norestartinteractive_chris_dev=0
RESTART=""
HERE=$(pwd)
echo "Starting script in dir $HERE"

CREPO=fnndsc
TAG=:dev

if [[ -f .env ]] ; then
    source .env 
fi

while getopts "r:psi" opt; do
    case $opt in 
        r) b_restart=1
           RESTART=$OPTARG                      ;;
        p) b_pause=1                            ;;
        s) b_skip=1                             ;;
        i) b_norestartinteractive_chris_dev=1   ;;
    esac
done

shift $(($OPTIND - 1))
if (( $# == 1 )) ; then
    REPO=$1
    export CREPO=$(echo $REPO | awk -F \: '{print $1}')
    export TAG=$(echo $REPO | awk -F \: '{print $2}')
    if $(( ${#TAG} )) ; then
        TAG=":$TAG"
    fi
fi

declare -a A_CONTAINER=(
    "chris_dev_backend"
    "pfcon${TAG}"
    "pfurl${TAG}"
    "pfioh${TAG}"
    "pman${TAG}"
    "swarm"
    "pfdcm${TAG}"
    "docker-swift-onlyone"
)


if (( b_restart )) ; then
    docker-compose stop ${RESTART}_service && docker-compose rm -f ${RESTART}_service
    docker-compose run --service-ports ${RESTART}_service
else
    title -d 1 "Using <$CREPO> family containers..."
    if (( ! b_skip )) ; then 
    if [[ $CREPO == "fnndsc" ]] ; then
            echo "Pulling latest version of all containers..."
            for CONTAINER in ${A_CONTAINER[@]} ; do
                echo ""
                CMD="docker pull ${CREPO}/$CONTAINER"
                echo -e "\t\t\t${White}$CMD${NC}"
                echo $sep
                echo $CMD | sh
                echo $sep
            done
        fi
    fi
    windowBottom

    if (( ! b_skip )) ; then 
        title -d 1 "Will use containers with following version info:"
        for CONTAINER in ${A_CONTAINER[@]} ; do
            if [[   $CONTAINER != "chris_dev_backend"   && \
                    $CONTAINER != "pl-pacsretrieve"     && \
                    $CONTAINER != "pl-pacsquery"        && \
                    $CONTAINER != "docker-swift-onlyone"     && \
                    $CONTAINER != "swarm" ]] ; then
                CMD="docker run ${CREPO}/$CONTAINER --version"
                printf "${White}%40s\t\t" "${CREPO}/$CONTAINER"
                Ver=$(echo $CMD | sh | grep Version)
                echo -e "$Green$Ver"
            fi
        done
        # Determine the versions of pfurl *inside* pfcon/chris_dev_backend/pl-pacs*
        CMD="docker run --entrypoint /usr/local/bin/pfurl ${CREPO}/pfcon${TAG} --version"
        printf "${White}%40s\t\t" "pfurl inside ${CREPO}/pfcon${TAG}"
        Ver=$(echo $CMD | sh | grep Version)
        echo -e "$Green$Ver"
        CMD="docker run --entrypoint /usr/local/bin/pfurl ${CREPO}/chris_dev_backend --version"
        printf "${White}%40s\t\t" "pfurl inside ${CREPO}/CUBE"
        Ver=$(echo $CMD | sh | grep Version)
        echo -e "$Green$Ver"
        CMD="docker run --rm --entrypoint /usr/local/bin/pfurl ${CREPO}/pl-pacsquery --version"
        printf "${White}%40s\t\t" "pfurl inside ${CREPO}/pl-pacsquery"
        Ver=$(echo $CMD | sh | grep Version)
        echo -e "$Green$Ver"
        CMD="docker run --rm --entrypoint /usr/local/bin/pfurl ${CREPO}/pl-pacsretrieve --version"
        printf "${White}%40s\t\t" "pfurl inside ${CREPO}/pl-pacsretrieve"
        Ver=$(echo $CMD | sh | grep Version)
        echo -e "$Green$Ver"
        windowBottom
    fi

    title -d 1 "Stopping and restarting the docker swarm... "
    docker swarm leave --force
    docker swarm init
    windowBottom

    title -d 1 "Shutting down any running CUBE and CUBE related containers... "
    docker-compose stop
    docker-compose rm -vf
    for CONTAINER in ${A_CONTAINER[@]} ; do
        printf "%30s" "$CONTAINER"
        docker ps -a                                                        |\
            grep $CONTAINER                                                 |\
            awk '{printf("docker stop %s && docker rm -vf %s\n", $1, $1);}' |\
            sh >/dev/null
        printf "${Green}%20s${NC}\n" "done"
    done
    windowBottom

    cd $HERE
    title -d 1 "Changing permissions to 755 on" " $(pwd)"
    echo "chmod -R 755 $(pwd)"
    chmod -R 755 $(pwd)
    windowBottom

    title -d 1 "Creating tmp dirs for volume mounting into containers..."
    echo "${STEP}.1: Remove tree root 'FS'.."
    rm -fr ./FS 
    echo "${STEP}.2: Create tree structure for remote services in host filesystem..."
    mkdir -p FS/local
    chmod 777 FS/local
    mkdir -p FS/remote
    chmod 777 FS/remote
    chmod 777 FS
    cd FS/remote
    echo -e "${STEP}.3 For pman override to swarm containers, exporting\n\tSTOREBASE=$(pwd)... "
    export STOREBASE=$(pwd)
    cd $HERE
    windowBottom

    title -d 1 "Starting CUBE containerized development environment using " " ./docker-compose.yml"
    # export HOST_IP=$(ip route | grep -v docker | awk '{if(NF==11) print $9}')
    # echo "Exporting HOST_IP=$HOST_IP as environment var..."
    echo "docker-compose up -d"
    docker-compose up -d
    windowBottom

    title -d 1 "Pause for manual restart of services?"
    if (( b_pause )) ; then
        read -n 1 -p "Hit ANY key to continue..." anykey
        echo ""
    fi
    windowBottom

    title -d 1 "Waiting until mysql server is ready to accept connections..."
    docker-compose exec chris_dev_db sh -c 'while ! mysqladmin -uroot -prootp status 2> /dev/null; do sleep 5; done;'
    # Give all permissions to chris user in the DB. This is required for the Django tests:
    docker-compose exec chris_dev_db mysql -uroot -prootp -e 'GRANT ALL PRIVILEGES ON *.* TO "chris"@"%"'
    windowBottom

    title -d 1 "Applying migrations..."
    docker-compose exec chris_dev python manage.py migrate
    windowBottom

    title -d 1 "Running Django Unit tests..."
    #docker-compose exec chris_dev python manage.py test --exclude-tag integration
    windowBottom

    title -d 1 "Running Django Integration tests..."
    #docker-compose exec chris_dev python manage.py test --tag integration
    windowBottom

    title -d 1 "Registering plugins..."
    # Declare an array variable for the list of plugin dock images
    # Add a new plugin image name to the list if you want it to be automatically registered
    docker-compose exec chris_dev /bin/bash -c \
    'declare -a plugins=("fnndsc/pl-simplefsapp"
                        "fnndsc/pl-simpledsapp"
                        "fnndsc/pl-pacsquery"
                        "fnndsc/pl-pacsretrieve"
                        "fnndsc/pl-med2img"
                        "fnndsc/pl-s3retrieve"
                        "fnndsc/pl-s3push"
                        "fnndsc/pl-dircopy"
                        "local/pl-geretrieve"
                        "local/pl-gepush"
                        )
    declare -i i=1
    declare -i STEP=10
    for plugin in "${plugins[@]}"; do
        echo "${STEP}.$i: Registering $plugin..."
        python3 plugins/services/manager.py --add ${plugin} 2> /dev/null;
        ((i++))
    done'
    windowBottom

    title -d 1 "ChRIS API user creation"
    echo ""
    echo "Setting user chris ..."
    docker-compose exec chris_dev /bin/bash -c 'python manage.py createsuperuser2 --username chris --email dev@babymri.org --password chris 2> /dev/null;'
    echo ""
    echo "Setting user cube ..."
    docker-compose exec chris_dev /bin/bash -c 'python manage.py createsuperuser2 --username cube --email dev@babymri.org --password cube 2> /dev/null;'
    windowBottom

    if (( !  b_norestartinteractive_chris_dev )) ; then
        title -d 1 "Restarting CUBE's Django development server in interactive mode..."
        docker-compose stop chris_dev
        docker-compose rm -f chris_dev
        docker-compose run --service-ports chris_dev
        echo ""
        windowBottom
    fi
fi
