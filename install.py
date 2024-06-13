import os
import argparse
import re
import urllib.request

## Gitlab group and project/program name. 
DEFAULT_IMG='ladlib'
DEFAULT_VERSION='main'

SHORTCUTS = ['eic-shell']
DOCKER_REF = r'docker://apanta123/$CONTAINER:$VERSION'

## Singularity bind directive
BIND_DIRECTIVE= '-B {0}:{0}'

class UnknownVersionError(Exception):
    pass
class ContainerDownloadError(Exception):
    pass
class InvalidArgumentError(Exception):
    pass

## generic launcher bash script to launch the application
_LAUNCHER='''#!/usr/bin/env bash

## Boilerplate to make pipes work
piped_args=
if [ -p /dev/stdin ]; then
  # If we want to read the input line by line
  while IFS= read line; do
    if [ -z "$piped_args" ]; then
      piped_args="${{line}}"
    else 
      piped_args="${{piped_args}}\n${{line}}"
    fi
  done
fi

## Fire off the application wrapper
if [ ${{piped_args}} ]  ; then
    echo -e ${{piped_args}} | singularity exec {bind} {container} {exe} $@
else
    singularity exec {bind} {container} {exe} $@
fi
'''

def smart_mkdir(dir):
    '''functions as mkdir -p, with a write-check.
    
    Raises an exception if the directory is not writeable.
    '''
    if not os.path.exists(dir):
        try:
            os.makedirs(dir)
        except Exception as e:
            print('ERROR: unable to create directory', dir)
            raise e
    if not os.access(dir, os.W_OK):
        print('ERROR: We do not have the write privileges to', dir)
        raise InvalidArgumentError()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
            'prefix',
            help='Install prefix. This is where the container will be deployed.')
    parser.add_argument(
            '-c', '--container',
            dest='container',
            default=DEFAULT_IMG,
            help='(opt.) Container to install. '
                 'D: {} (also available: jug_dev, and legacy "eic" container).')
    parser.add_argument(
            '-v', '--version',
            dest='version',
#            default=project_version(),
            default=DEFAULT_VERSION,
            help='(opt.) project version. '
                 'D: {}. For MRs, use mr-XXX.'.format(DEFAULT_VERSION))
    parser.add_argument(
            '-f', '--force',
            action='store_true',
            help='Force-overwrite already downloaded container',
            default=False)
    parser.add_argument(
            '-b', '--bind-path',
            dest='bind_paths',
            action='append',
            help='(opt.) extra bind paths for singularity.')
    args = parser.parse_args()

    print('Deploying', args.container, 'version', args.version)

    ## Check if our bind paths are valid
    bind_directive = ''
    if args.bind_paths and len(args.bind_paths):
        print('Singularity bind paths:')
        for path in args.bind_paths:
            print(' -', path)
            if not os.path.exists(path):
                print('ERROR: path', path, 'does not exist.')
                raise InvalidArgumentError()
        bind_directive = ' '.join([BIND_DIRECTIVE.format(path) for path in args.bind_paths])
    args.prefix = os.path.abspath(args.prefix)
    print('Install prefix:', args.prefix)
    print('Creating install prefix if needed...')
    bindir = '{}/bin'.format(args.prefix)
    libdir = '{}/lib'.format(args.prefix)
    libexecdir = '{}/libexec'.format(args.prefix)
    root_prefix = os.path.abspath('{}/..'.format(args.prefix))
    dirs = [bindir, libdir, libexecdir]
    for dir in dirs:
        print(' -', dir)
        smart_mkdir(dir)
    img = args.container
    version_docker = args.version
    container = '{}/{}-{}.sif'.format(libdir, img, version_docker)
    if not os.path.exists(container) or args.force:
        print('Attempting alternative download from docker registry')
        cmd = ['singularity pull', '--force', container, DOCKER_REF.format(img=img, tag=version_docker)]
        cmd = ' '.join(cmd)
        print('Executing:', cmd)
        err = os.system(cmd)
        if err:
            raise ContainerDownloadError()
    else:
        print('WARNING: Container found at', container)
        print(' ---> run with -f to force a re-download')
    
    