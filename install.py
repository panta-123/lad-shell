import os
import argparse
import re
import urllib.request

## Gitlab group and project/program name. 
DEFAULT_IMG='ladlib'
DEFAULT_VERSION='main'

SHORTCUTS = ['lad-shell']
DOCKER_REF = r'docker://apanta123/{img}:{tag}'

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
def _write_script(path, content):
    print(' - creating', path)
    with open(path, 'w') as file:
        file.write(content)
    os.system('chmod +x {}'.format(path))
    
def make_launcher(app, container, bindir, 
                  bind='', exe=None):
    '''Configure and install a launcher.

    Generic launcher script to launch applications in this container.

    The launcher script calls the desired executable from the singularity image.
    As the new images have the environment properly setup, we can accomplish this
    without using any wrapper scripts.

    Arguments:
        - app: our application
        - container: absolute path to container
        - bindir: absolute launcher install path
    Optional:
        - bind: singularity bind directives
        - exe: executable to be associated with app. 
               Default is app.
        - env: environment directives to be added to the wrapper. 
               Multiline string. Default is nothing
    '''
    if not exe:
        exe = app

    ## paths
    launcher_path = '{}/{}'.format(bindir, app)

    ## scripts --> use absolute path for wrapper path inside launcher
    launcher = _LAUNCHER.format(container=container, 
                                bind=bind,
                                exe=exe)

    ## write our scripts
    _write_script(launcher_path, launcher)

## Generic module file
_MODULEFILE='''#%Module1.0#####################################################################
##
## for {name} {version}
##
proc ModulesHelp {{ }} {{
    puts stderr "This module sets up the environment for the {name} container"
}}
module-whatis "{name} {version}"

# For Tcl script use only
set version 4.1.4

prepend-path    PATH    {bindir}
'''


def make_modulefile(project, version, moduledir, bindir):
    '''Configure and install a modulefile for this project.

    Arguments:
        - project: project name
        - version: project version
        - moduledir: root modulefile directory
        - bindir: where executables for this project are located
    '''

    ## create our modulefile
    content = _MODULEFILE.format(name=project, version=version, bindir=bindir)
    fname = '{}/{}'.format(moduledir, version)
    print(' - creating', fname)
    with open(fname, 'w') as file:
        file.write(content)

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
    parser.add_argument(
            '-m', '--module-path',
            dest='module_path',
            help='(opt.) Root module path to install a modulefile. '
                 'D: Do not install a modulefile')

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
    if not args.module_path:
        deploy_local=True
    else:
        deploy_local=False
    print('Install prefix:', args.prefix)
    print('Creating install prefix if needed...')
    bindir = '{}/bin'.format(args.prefix)
    libdir = '{}/lib'.format(args.prefix)
    libexecdir = '{}/libexec'.format(args.prefix)
    root_prefix = os.path.abspath('{}/..'.format(args.prefix))
    dirs = [bindir, libdir, libexecdir]
    if not deploy_local:
        moduledir = '{}/{}'.format(args.module_path, args.container)
        dirs.append(moduledir)
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
    
    if not deploy_local:
        make_modulefile(args.container, version_docker, moduledir, bindir)

    ## configure the application launchers
    print('Configuring applications launchers: ')
    for prog in SHORTCUTS:
        app = prog
        exe = prog
        if type(prog) == tuple:
            app = prog[0]
            exe = prog[1]
        make_launcher(app, container, bindir,
                      bind=bind_directive,
                      exe=exe)

    print('Container deployment successful!')