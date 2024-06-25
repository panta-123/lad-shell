#!/bin/bash

## Simple setup script that installs the container
## in your local environment under $PREFIX/local/lib
## and creates a simple top-level launcher script
## that launches the container for this working directory
## with the $LAD_SHELL_PREFIX variable pointing
## to the $PREFIX/local directory

CONTAINER="ladlib"
VERSION="main"
PREFIX="$PWD"

function print_the_help {
  echo "USAGE:  ./install.sh [-p PREFIX] [-v VERSION]"
  echo "OPTIONAL ARGUMENTS:"
  echo "          -p,--prefix     Working directory to deploy the environment (D: $PREFIX)"
  echo "          -t,--tmpdir     Change tmp directory (D: $([[ -z "$TMPDIR" ]] && echo "/tmp" || echo "$TMPDIR"))"
  echo "          -n,--no-cvmfs   Disable check for local CVMFS (D: enabled)"
  echo "          -c,--container  Container version (D: $CONTAINER)"
  echo "          -v,--version    Version to install (D: $VERSION)"
  echo "          -h,--help       Print this message"
  echo ""
  echo "  Set up containerized development environment."
  echo ""
  echo "EXAMPLE: ./install.sh" 
  exit
}

while [ $# -gt 0 ]; do
  key=$1
  case $key in
    -p|--prefix)
      PREFIX=$(realpath $2)
      shift
      shift
      ;;
    -t|--tmpdir)
      export TMPDIR=$2
      export SINGULARITY_TMPDIR=$2
      shift
      shift
      ;;
    -n|--no-cvmfs)
      DISABLE_CVMFS_USAGE=true
      shift
      ;;
    -c|--container)
      CONTAINER=$2
      shift
      shift
      ;;
    -v|--version)
      VERSION=$2
      shift
      shift
      ;;
    -h|--help)
      print_the_help
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $key"
      echo "use --help for more info"
      exit 1
      ;;
  esac
done

## create prefix if needed
mkdir -p $PREFIX || exit 1
pushd $PREFIX

if [ ! -d $PREFIX ]; then
  echo "ERROR: not a valid directory: $PREFIX"
  echo "use --help for more info"
  exit 1
fi

echo "Setting up development environment for apanta123/$CONTAINER:$VERSION"

mkdir -p $PREFIX/local/lib || exit 1

function install_singularity() {
  SINGULARITY=
  ## check for a singularity install
  ## default singularity if new enough
  if [ $(type -P singularity ) ]; then
    SINGULARITY=$(which singularity)
    SINGULARITY_VERSION=`$SINGULARITY --version`
    if [ ${SINGULARITY_VERSION:0:1} = 2 ]; then
      ## too old, look for something else
      SINGULARITY=
    fi
  fi
  if [ -z $SINGULARITY ]; then
    ## first priority: a known good install (this one is on JLAB)
    if [ -d "/apps/singularity/3.7.1/bin/" ]; then
      SINGULARITY="/apps/singularity/3.7.1/bin/singularity"
    ## whatever is in the path is next
    elif [ $(type -P singularity ) ]; then
      SINGULARITY=$(which singularity)
    ## cvmfs singularity is last resort (sandbox mode can cause issues)
    elif [ -f "/cvmfs/oasis.opensciencegrid.org/mis/singularity/bin/singularity" ]; then
      SINGULARITY="/cvmfs/oasis.opensciencegrid.org/mis/singularity/bin/singularity"
    ## not good...
    else
      echo "ERROR: no singularity found, please make sure you have singularity in your \$PATH"
      exit 1
    fi
  fi
  echo " - Found singularity at $SINGULARITY"

  ## get singularity version
  ## we only care if is 2.x or not, so we can use singularity --version 
  ## which returns 2.xxxxx for version 2
  SINGULARITY_VERSION=`$SINGULARITY --version`
  SIF=
  if [ ${SINGULARITY_VERSION:0:1} = 2 ]; then
    SIF="$PREFIX/local/lib/${CONTAINER}-${VERSION}.simg"
    echo "Attempting last-resort singularity pull for old image"
    echo "This may take a few minutes..."
    INSIF=`basename ${SIF}`
    singularity pull --name "${INSIF}" docker://apanta123/$CONTAINER:$VERSION
    mv ${INSIF} $SIF
    chmod +x ${SIF}
    unset INSIF
  ## we are in sane territory, yay!
  else
    ## check if we can just use local image in PREFIX/local/lib
    SIF="$PREFIX/local/lib/${CONTAINER}-${VERSION}.sif"
    if [ -z "$DISABLE_CVMFS_USAGE" -a -d /cvmfs/singularity.opensciencegrid.org/eicweb/${CONTAINER}:${VERSION} ]; then
      SIF="$PREFIX/local/lib/${CONTAINER}-${VERSION}"
      ## need to cleanup in this case, else it will try to make a subdirectory
      rm -rf ${SIF}
      ln -sf /cvmfs/singularity.opensciencegrid.org/${CONTAINER}:${VERSION} ${SIF}
    ## check if we have an jlab deployed image. #TODO replace with work lad directory
    elif [ -f /u/home/panta/ladimg/${CONTAINER}-${VERSION}.sif ]; then
      ln -sf /u/home/panta/ladimg/${CONTAINER}-${VERSION}.sif ${SIF}
    ## if not, download the container to the system
    else
      ## get the python installer and run the old-style install
      ## work in temp directory
      echo "Downloading image"
      wget https://raw.githubusercontent.com/JeffersonLab/lad-shell/main/install.py
      chmod +x install.py
      python3 install.py -f -c ${CONTAINER} -v ${VERSION} $PREFIX/local
      chmod +x ${SIF}
    fi
  fi

  echo $SIF
  ls $SIF 2>&1 > /dev/null && GOOD_SIF=1 
  if [ -z "$SIF" -o -z "$GOOD_SIF" ]; then
    echo "ERROR: no singularity image found"
    exit 1
  else
    echo " - Deployed ${CONTAINER} image: $SIF"
  fi

  ## We want to make sure the root directory of the install directory
  ## is always bound. We also check for the existence of a few standard
  ## locations (/scratch /volatile /cache) and bind those too if found
  echo " - Determining additional bind paths"
  BINDPATH=${SINGULARITY_BINDPATH}
  echo "   --> system bindpath: $BINDPATH"
  PREFIX_ROOT="/$(realpath $PREFIX | cut -d "/" -f2)"
  for dir in /w /work /scratch /volatile /cache /net $PREFIX_ROOT; do
    ## only add directories once
    if [[ ${BINDPATH} =~ $(basename $dir) ]]; then
      continue
    fi
    if [ -d $dir ]; then
      echo "   --> $dir"
      BINDPATH=${dir}${BINDPATH:+,$BINDPATH}
    fi
  done

  ## create a new top-level lad-shell launcher script
  ## that sets the LAD_SHELL_PREFIX and then starts singularity
cat << EOF > lad-shell
#!/bin/bash

## capture environment setup for upgrades
CONTAINER=$CONTAINER
TMPDIR=$TMPDIR
VERSION=$VERSION
PREFIX=$PREFIX
DISABLE_CVMFS_USAGE=${DISABLE_CVMFS_USAGE}

function print_the_help {
  echo "USAGE:  ./lad-shell [OPTIONS] [ -- COMMAND ]"
  echo "OPTIONAL ARGUMENTS:"
  echo "          -u,--upgrade    Upgrade the container to the latest version"
  echo "          -n,--no-cvmfs   Disable check for local CVMFS when updating. (D: enabled)"
  echo "          -c,--container  Container version (D: \$CONTAINER) (requires cvmfs)"
  echo "          -v,--version    Version to install (D: \$VERSION) (requires cvmfs)"
  echo "          -h,--help       Print this message"
  echo ""
  echo "  Start the lad-shell containerized software environment (Singularity version)."
  echo ""
  echo "EXAMPLES: "
  echo "  - Start an interactive shell: ./lad-shell" 
  echo "  - Upgrade the container:      ./lad-shell --upgrade"
  echo "  - Use different version:      ./lad-shell --version \$(date +%y.%m).0-stable"
  echo "  - Execute a single command:   ./lad-shell -- <COMMAND>"
  echo ""
  exit
}

UPGRADE=

while [ \$# -gt 0 ]; do
  key=\$1
  case \$key in
    -u|--upgrade)
      UPGRADE=1
      shift
      ;;
    -n|--no-cvmfs)
      DISABLE_CVMFS_USAGE=true
      shift
      ;;
    -c|--container)
      CONTAINER=\$2
      export SIF=/cvmfs/singularity.opensciencegrid.org/eicweb/\${CONTAINER}:\${VERSION}
      shift
      shift
      ;;
    -v|--version)
      VERSION=\$2
      export SIF=/cvmfs/singularity.opensciencegrid.org/eicweb/\${CONTAINER}:\${VERSION}
      shift
      shift
      ;;
    -h|--help)
      print_the_help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "ERROR: unknown argument: \$key"
      echo "use --help for more info"
      exit 1
      ;;
  esac
done

if [ ! -z \${UPGRADE} ]; then
  echo "Upgrading lad-shell..."
  if [ -z "\$DISABLE_CVMFS_USAGE" -a -d /cvmfs/singularity.opensciencegrid.org/eicweb/\${CONTAINER}:\${VERSION} ]; then
    echo ""
    echo "Note: You cannot manually update the container as you are using the CVMFS version."
    echo "      The container will automatically update every 24 hours."
    echo "      You can override this by setting the '--no-cvmfs' flag, which will"
    echo "      instantiate a local version."
    echo "      This is only recommended for expert usage."
    echo ""
    echo "This will only upgrade the lad-shell script itself."
    echo ""
  fi
  FLAGS="-p \${PREFIX} -v \${VERSION}"
  if [ ! -z \${TMPDIR} ]; then
    FLAGS="\${FLAGS} -t \${TMPDIR}"
  fi
  if [ ! -z \${DISABLE_CVMFS_USAGE} ]; then
    FLAGS="\${FLAGS} --no-cvmfs"
  fi
  curl -L https://github.com/panta-123/lad-shell/raw/main/install.sh \
    | bash -s -- \${FLAGS}
  echo "lad-shell upgrade sucessful"
  exit 0
fi

export LAD_SHELL_PREFIX=$PREFIX/local
export SINGULARITY_BINDPATH=$BINDPATH
\${SINGULARITY:-$SINGULARITY} exec \${SINGULARITY_OPTIONS:-} \${SIF:-$SIF} lad-shell \$@
EOF

  chmod +x lad-shell

  echo " - Created custom lad-shell excecutable"
}

function install_docker() {
  ## check for docker install
  DOCKER=$(which docker)
  if [ -z ${DOCKER} ]; then
    echo "ERROR: no docker install found, docker is required for the docker-based install"
  fi
  echo " - Found docker at ${DOCKER}"

  IMG=apanta123/${CONTAINER}:${VERSION}
  docker pull ${IMG}
  echo " - Deployed ${CONTAINER} image: ${IMG}"

  ## We want to make sure the root directory of the install directory
  ## is always bound. We also check for the existence of a few standard
  ## locations (/Volumes /Users /tmp) and bind those too if found
  echo " - Determining mount paths"
  PREFIX_ROOT="/$(realpath $PREFIX | cut -d "/" -f2)"
  MOUNT=""
  echo "   --> $PREFIX_ROOT"
  for dir in /Volumes /Users /tmp; do
    ## only add directories once
    if [[ ${MOUNT} =~ $(basename $dir) ]]; then
      continue
    fi
    if [ -d $dir ]; then
      echo "   --> $dir"
      MOUNT="$MOUNT -v $dir:$dir"
    fi
  done
  echo " - Docker mount directive: '$MOUNT'"
  PLATFORM_FLAG=''
  if [ `uname -m` = 'arm64' ]; then
    PLATFORM_FLAG='--platform linux/amd64'
    echo " - Additional platform flag to run on arm64"
  fi

  ## create a new top-level lad-shell launcher script
  ## that sets the LAD_SHELL_PREFIX and then starts singularity
cat << EOF > lad-shell
#!/bin/bash

## capture environment setup for upgrades
CONTAINER=$CONTAINER
TMPDIR=$TMPDIR
VERSION=$VERSION
PREFIX=$PREFIX
DISABLE_CVMFS_USAGE=${DISABLE_CVMFS_USAGE}

function print_the_help {
  echo "USAGE:  ./lad-shell [OPTIONS] [ -- COMMAND ]"
  echo "OPTIONAL ARGUMENTS:"
  echo "          -u,--upgrade    Upgrade the container to the latest version"
  echo "          --noX           Disable X11 forwarding on macOS"
  echo "          -h,--help       Print this message"
  echo ""
  echo "  Start the lad-shell containerized software environment (Docker version)."
  echo ""
  echo "EXAMPLES: "
  echo "  - Start an interactive shell: ./lad-shell" 
  echo "  - Upgrade the container:      ./lad-shell --upgrade"
  echo "  - Execute a single command:   ./lad-shell -- <COMMAND>"
  echo ""
  exit
}

UPGRADE=
NOX=
while [ \$# -gt 0 ]; do
  key=\$1
  case \$key in
    -u|--upgrade)
      UPGRADE=1
      shift
      ;;
    --noX)
      NOX=1
      shift
      ;;
     -h|--help)
      print_the_help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "ERROR: unknown argument: \$key"
      echo "use --help for more info"
      exit 1
      ;;
  esac
done

if [ ! -z \${UPGRADE} ]; then
  echo "Upgrading lad-shell..."
  docker pull $IMG || exit 1
  echo "lad-shell upgrade sucessful"
  exit 0
fi
EOF

  if [ `uname -s` = 'Darwin' ]; then
      echo 'if [ ! ${NOX} ]; then' >> lad-shell
      echo ' nolisten=`defaults find nolisten_tcp | grep nolisten | head -n 1 | awk ' "'{print" '$3}'"'" '|cut -b 1 `' >> lad-shell
      echo ' [[ $nolisten -ne 0 ]] && echo "For X support: In XQuartz settings --> Security --> enable \"Allow connections from network clients\" and restart (should be only once)."' >> lad-shell
      ## getting the following single and double quotes, escapes and backticks right was a nightmare
      ## But with a heredoc it was worse
      echo '  xhost +localhost' >> lad-shell
      echo '  dispnum=`ps -e |grep Xquartz | grep listen | grep -v xinit |awk ' "'{print" '$5}'"'" '`' >> lad-shell
      echo '  XSTUFF="-e DISPLAY=host.docker.internal${dispnum} -v /tmp/.X11-unix:/tmp/.X11-unix"' >> lad-shell
      echo 'fi' >> lad-shell
  fi
  echo "docker run $PLATFORM_FLAG $MOUNT \$XSTUFF -w=$PWD -it --rm -e LAD_SHELL_PREFIX=$PREFIX/local $IMG lad-shell \$@" >> lad-shell

  chmod +x lad-shell
  echo " - Created custom lad-shell excecutable"
}

function install_podman() {
  ## check for docker install
  PODMAN=$(which podman)
  if [ -z ${DOCKER} ]; then
    echo "ERROR: no docker install found, docker is required for the docker-based install"
  fi
  echo " - Found docker at ${PODMAN}"

  IMG=apanta123/${CONTAINER}:${VERSION}
  docker pull ${IMG}
  echo " - Deployed ${CONTAINER} image: ${IMG}"

  ## We want to make sure the root directory of the install directory
  ## is always bound. We also check for the existence of a few standard
  ## locations (/Volumes /Users /tmp) and bind those too if found
  echo " - Determining mount paths"
  PREFIX_ROOT="/$(realpath $PREFIX | cut -d "/" -f2)"
  MOUNT=""
  echo "   --> $PREFIX_ROOT"
  for dir in /Volumes /Users /tmp; do
    ## only add directories once
    if [[ ${MOUNT} =~ $(basename $dir) ]]; then
      continue
    fi
    if [ -d $dir ]; then
      echo "   --> $dir"
      MOUNT="$MOUNT -v $dir:$dir"
    fi
  done
  echo " - Docker mount directive: '$MOUNT'"
  PLATFORM_FLAG=''
  if [ `uname -m` = 'arm64' ]; then
    PLATFORM_FLAG='--platform linux/amd64'
    echo " - Additional platform flag to run on arm64"
  fi

  ## create a new top-level lad-shell launcher script
  ## that sets the LAD_SHELL_PREFIX and then starts singularity
cat << EOF > lad-shell
#!/bin/bash

## capture environment setup for upgrades
CONTAINER=$CONTAINER
TMPDIR=$TMPDIR
VERSION=$VERSION
PREFIX=$PREFIX
DISABLE_CVMFS_USAGE=${DISABLE_CVMFS_USAGE}

function print_the_help {
  echo "USAGE:  ./lad-shell [OPTIONS] [ -- COMMAND ]"
  echo "OPTIONAL ARGUMENTS:"
  echo "          -u,--upgrade    Upgrade the container to the latest version"
  echo "          --noX           Disable X11 forwarding on macOS"
  echo "          -h,--help       Print this message"
  echo ""
  echo "  Start the lad-shell containerized software environment (Docker version)."
  echo ""
  echo "EXAMPLES: "
  echo "  - Start an interactive shell: ./lad-shell" 
  echo "  - Upgrade the container:      ./lad-shell --upgrade"
  echo "  - Execute a single command:   ./lad-shell -- <COMMAND>"
  echo ""
  exit
}

UPGRADE=
NOX=
while [ \$# -gt 0 ]; do
  key=\$1
  case \$key in
    -u|--upgrade)
      UPGRADE=1
      shift
      ;;
    --noX)
      NOX=1
      shift
      ;;
     -h|--help)
      print_the_help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "ERROR: unknown argument: \$key"
      echo "use --help for more info"
      exit 1
      ;;
  esac
done

if [ ! -z \${UPGRADE} ]; then
  echo "Upgrading lad-shell..."
  podman pull $IMG || exit 1
  echo "lad-shell upgrade sucessful"
  exit 0
fi
EOF

  if [ `uname -s` = 'Darwin' ]; then
      echo 'if [ ! ${NOX} ]; then' >> lad-shell
      echo ' nolisten=`defaults find nolisten_tcp | grep nolisten | head -n 1 | awk ' "'{print" '$3}'"'" '|cut -b 1 `' >> lad-shell
      echo ' [[ $nolisten -ne 0 ]] && echo "For X support: In XQuartz settings --> Security --> enable \"Allow connections from network clients\" and restart (should be only once)."' >> lad-shell
      ## getting the following single and double quotes, escapes and backticks right was a nightmare
      ## But with a heredoc it was worse
      echo '  xhost +localhost' >> lad-shell
      echo '  dispnum=`ps -e |grep Xquartz | grep listen | grep -v xinit |awk ' "'{print" '$5}'"'" '`' >> lad-shell
      echo '  XSTUFF="-e DISPLAY=host.containers.internal${dispnum} -v /tmp/.X11-unix:/tmp/.X11-unix"' >> lad-shell
      echo 'fi' >> lad-shell
  fi
  echo "podman run $PLATFORM_FLAG $MOUNT \$XSTUFF -w=$PWD -it --rm -e LAD_SHELL_PREFIX=$PREFIX/local $IMG lad-shell \$@" >> lad-shell

  chmod +x lad-shell
  echo " - Created custom lad-shell excecutable"
}

## detect OS
OS=`uname -s`
CPU=`uname -m`
case ${OS} in
  Linux)
    echo " - Detected OS: Linux"
    echo " - Detected CPU: $CPU"
    if [ "$CPU" = "arm64" ]; then
      install_docker
    else
      install_singularity
    fi
    ;;
  Darwin)
    echo " - Detected OS: MacOS"
    echo " - Detected CPU: $CPU"
    install_docker
    ;;
  *)
    echo "ERROR: OS '${OS}' not currently supported"
    exit 1
    ;;
esac

popd
echo "Environment setup succesfull"
echo "You can start the development environment by running './lad-shell'"
