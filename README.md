LAD software environment container utilities
============================================

Local Installation
------------------

*The environment has been tested on linux (requires singularity v3+ or apptainer v1+)
and MacOS (requires docker)*

Please follow the steps below to setup and run the container in your environment.

1. Create a local directory that you want to work in, e.g `$HOME/lad`, and go into this
   directory.
```bash
mkdir $HOME/lad
cd $HOME/lad
```

2. Execute the following line in your terminal to setup your environment in this directory
   to install the latest stable container
```bash
curl -L https://raw.githubusercontent.com/panta-123/lad-shell/main/install.sh | bash
```

3. You can now load your development environment by executing the `eic-shell` script that
   is in your top-level working directory.
```bash
./lad-shell
```

4. Within your  environment (`lad-shell`), you can install software to the
   internal prefix `$LAD_SHELL_PREFIX`



Included software:
------------------
  - Included software (for the exact versions, use the command `lad-info` inside the container):

    
