# Squash ICON

The aim of this repo is to explore the workflow
1. build ICON
2. squash the resulting ICON repository
3. Run ICON
It can serve either as a tool, originally for CI, or as a base for your own use case.

The repository provides 2 scripts, `build_and_squash_icon.sh` and `run_from_squashed.sh` (plus a helper `duplink.sh` script), that can help in many regards compared to classical builds.
- Several targets are stored in a single squashed file, which is pretty useful for CI or coupled runs requiring multiple executables.
- The build process is faster as
  - targets are built asynchronously
  - building on `/dev/shm` is faster than on drive
  - squashing requires a handful of seconds and retrieving a squashed file from `/dev/shm` is virtually unnoticeable while retrieving a repo full of many small files takes minutes.
  For instance building `santis.cpu.nvhpc`, `santis.gpu.nvhpc` and `santis.icon4py.nvhpc` takes 14 min.
- Accessing a lot of small files, typically for virtual environments like the `ICON4Py` one, is faster.

## Build and squash

`build_and_squash_icon.sh` enables asynchronous building of multiple ICON targets on `/dev/shm` and squashing the resulting directory in a single file.
Builds are done in an out-of-source fashion in directories named after the target in the `build` directory at the root of the ICON clone, e.g. `build/santis.xxx.nvhpc`. The script also dumps the uenv version used at build time so that `run_from_squashed.sh` directly uses it without transparently, removing the need to keep the link between the uenv and the build.

Usage is given by `build_and_squash_icon.sh --help` 

The intended usage is to submit it as a job, e.g. with

``` shell
sbatch --partition=debug --time=00:30:00 ./build_and_squash_icon.sh --uenv="icon/26.2:2612149565" --branch="add_icon4py" --squash="add_icon4py_26.1.squashfs"
```

Interactive run is also possible for testing and runs on disk, not `/dev/shm`. Still, BE CAUTIOUS with that mode as you could end up using a lot of resources of login nodes (one build runs on 72 procs).

## Run from the squashed directory

The `run_from_squashed.sh` script enables running an existing ICON experiment from the squashed ICON file. Since squashed files are read-only, it duplicates the directory with only links except for files that need to be modified using the `duplink.sh` script. Using it out-of-the-box, only one fie needs modification (`run/set-up.info`) but if more are required, you can modify the script and pass more "actual" paths to `duplink.sh` (see `duplink.sh --help`). Then it creates the experiment run script using the classical ICON scripts and finally submits the run script by mounting the ICON squashed file along side the uenv used at build time. The later doesn't need to be explicitly specified since it's found in the squashed file.

Usage is given by `run_from_squashed.sh --help`

A typical call to the script would like

``` shell
./run_from_squashed.sh --squash="add_icon4py_26.1.squashfs" --target="santis.icon4py.nvhpc" --exp="mch_icon-ch2_small" --run="MY_ICON_DUPLICATE"
```
