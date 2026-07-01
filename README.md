# Squash ICON

The aim of this repo is to explore the workflow
1. build ICON
2. squash the resulting ICON repository
3. Run ICON

It can serve either as a tool, originally for CI, or as a base for your own use case.

The repository provides 2 scripts, `build_and_squash_icon.sh` and `run_from_squashed.sh` (plus a helper `duplink.sh` script), that can help in many regards compared to classical builds.
- Several targets are stored in a single squashed file, which is pretty useful for CI or coupled runs requiring multiple executables.
- Obviously the number of files is reduced from tens of thousands to 1.
- The build process is faster as:
  - targets are being built asynchronously.
  - building on `/dev/shm` is faster than on drive.
  - squashing requires a handful of seconds and retrieving a squashed file from `/dev/shm` is virtually unnoticeable while retrieving a repo full of many small files takes minutes.

  For instance building `santis.cpu.nvhpc`, `santis.gpu.nvhpc` and `santis.icon4py.nvhpc` takes 14 min.
- Accessing a lot of small files, typically for virtual environments like the `ICON4Py` one, is faster.

## Build and squash

`build_and_squash_icon.sh` enables asynchronous building of multiple ICON targets on `/dev/shm` and squashing the resulting directory in a single file.
Builds are done in an out-of-source fashion in directories named after the target in the `build` directory at the root of the ICON clone, e.g. `build/santis.xxx.nvhpc`. The script also dumps the uenv version used at build time so that `run_from_squashed.sh` directly uses it without transparently, removing the need to keep the link between the uenv and the build.

Usage is given by `build_and_squash_icon.sh --help`

```
❯ ./build_and_squash_icon.sh --help

Build multiple out-of-source targets asynchronously and squash the icon directory.
Targets are beeing built in `build/TARGET_NAME`

Usage:
./build_and_squash_icon.sh [required arguments] [optional arguments]

required arguments
  --uenv=UENV                    icon uenv

optional arguments
  --repo=ICON_REPO               icon git repository, default: git@gitlab.dkrz.de:icon/icon-nwp.git
  --branch=ICON_BRANCH           branch of ICON_REPO, default: master
  --squash=SQUASHED_FILE         squashed path for the icon directory,
                                 default: in current directory, filename inferred from ICON_REPO and ICON_BRANCH
  --targets=TARGET1,...          comma separated list of build targets,
                                 default: santis.cpu.nvhpc,santis.gpu.nvhpc,santis.icon4py.nvhpc
  --gitlab-dkrz-token TOKEN      clone from gitlab.dkrz.de with TOKEN instead of ssh
  --github-token TOKEN           clone from github.com with TOKEN instead of ssh
```

The intended usage is to submit it as a job, e.g. with

``` shell
sbatch --partition=debug --time=00:30:00 ./build_and_squash_icon.sh --uenv="icon/26.2:2612149565" --branch="add_icon4py" --squash="add_icon4py_26.1.squashfs"
```

Interactive run is also possible for testing and runs on disk, not `/dev/shm`. Still, BE CAUTIOUS with that mode as you could end up using a lot of resources of login nodes (one build runs on 72 procs).

## Run from the squashed directory

The `run_from_squashed.sh` script enables running an existing ICON experiment from the squashed ICON file. Since squashed files are read-only, it duplicates the directory with only links except for files that need to be modified using the `duplink.sh` script. Using it out-of-the-box, only one file needs modification (`run/set-up.info`). If more are required, when modifying `run_from_squashed.sh`, pass more "actual" paths to `duplink.sh` with something like `--actual=first/apth:second/path` (see `duplink.sh --help`). Then it creates the experiment run script using the classical ICON scripts and finally submits the run script, mounting the ICON squashed file alongside the uenv used at build time. The later doesn't need to be explicitly specified since it's found in the squashed file.

Usage is given by `run_from_squashed.sh --help`

```
❯ ./run_from_squashed.sh --help

Run an icon experiment using the content of a squashed icon directory

Usage:
./run_from_squashed.sh [required arguments] [optional arguments]

required arguments
  --squash=SQUASHED_FILE  icon directory squashed file with icon builds
  --target=TARGET         use icon build at "build/TARGET" in SQUASHED_FILE
                          (see build_and_squash_icon.sh)
  --exp=EXP               icon experiment name

optional arguments
  --mount=MOUNT_POINT     mount point for SQUASHED_FILE, default: "./ICON_MOUNT"
  --run=ICON_RUN          dupplicate directory from MOUNT_POINT where the experiment runs,
                          default: "./ICON_RUN"
  --account=ACCOUNT       SLURM account, default: first entry of $(groups)
  --partition=PARTITION   use SLURM partition PARTITION, default: "debug"
  --time=TIME             request --time=TIME to SLURM, default: "00:30:00"
```

A typical call to the script would look like this:

``` shell
./run_from_squashed.sh --squash="add_icon4py_26.1.squashfs" --target="santis.icon4py.nvhpc" --exp="mch_icon-ch2_small" --run="MY_ICON_DUPLICATE"
```
