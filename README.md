# Single-cell Docker Workbench

A reusable, GPU-enabled Docker/Compose workbench for interactive single-cell
analysis with Python notebooks in VS Code and terminal R. It is designed for
large sparse AnnData/10X workflows on a shared Linux workstation.

这是一套可迁移到多个 Linux 账号的单细胞分析工作台模板。每个账号拥有独立
容器、镜像名称和工作区；所有需要替换的身份、路径与资源参数集中在一份
`workbench.env` 登记表中。

## Maintainer

**Liang Yu**  
Chinese Academy of Medical Sciences & Peking Union Medical College  
GitHub: [@LianaSakana001](https://github.com/LianaSakana001)  
ORCID: [0009-0002-2054-7620](https://orcid.org/0009-0002-2054-7620)

## What is included

- A pinned `rapids-singlecell` CUDA base image with Scanpy, AnnData, CuPy and
  RAPIDS support.
- A small Python extension list and a separate Conda/Mamba `r-sc` environment
  with Seurat, SingleCellExperiment, edgeR, limma and common tidyverse tools.
- Tsinghua TUNA mirrors for APT, Conda, pip and CRAN.
- VS Code Dev Containers + Python/Jupyter usage without exposing a Jupyter port.
- Terminal R; no RStudio service and no browser Jupyter service.
- One writable workbench, three narrow read-only inputs, a non-root container
  user, dropped capabilities and explicit resource limits.
- A multi-project layout that is created explicitly, not recreated on every
  container start.
- Host preflight, post-build smoke test, privacy audit and CI validation.

## Host requirements

- Linux with Docker Engine and Docker Compose v2.
- An NVIDIA GPU, compatible host driver, and NVIDIA Container Toolkit.
- Permission to use the Docker daemon.
- Existing readable input paths and one existing writable workspace path.

Docker access on a rootful shared daemon is effectively host-root access. Read
[SECURITY.md](SECURITY.md) before using this template with multiple accounts.

## Repository layout

~~~text
.
├── workbench.env.example     the single user/host registration form
├── workbench                 command wrapper
├── compose.yaml              mounts, runtime limits, and security settings
├── Dockerfile                image build
├── config/                   TUNA mirror configuration
├── env/                      Python and R package lists
├── scripts/
│   ├── preflight-host.sh     read-only host validation
│   ├── entrypoint.sh         creates only workbench infrastructure
│   ├── init-project.sh       one-time project tree creation
│   ├── smoke-test.sh         runtime and scientific-stack validation
│   └── release-audit.sh      tracked-file privacy/secret check
└── templates/                project README template
~~~

## Quick start

### 1. Register one host account

~~~bash
cp workbench.env.example workbench.env
id
id -u
id -g
id -G
nano workbench.env
~~~

Replace every example name, numeric ID, and host path. The real
`workbench.env` is ignored by both Git and the Docker build context.

The input and workspace paths must already exist. Compose is configured with
`create_host_path: false` so a typo cannot silently create a root-owned path.

### 2. Run the read-only preflight

~~~bash
./workbench preflight
./workbench config
~~~

Preflight checks identity, supplementary group membership, path scope and
overlap, Docker, the host GPU, and Compose interpolation. It does not pull,
build, start, delete, or modify an image/container.

### 3. Build only

~~~bash
./workbench build
~~~

This builds the image and does not start a container.

### 4. Start and validate

~~~bash
./workbench up
./workbench smoke
~~~

The smoke test verifies the UID/GID, writable and read-only mounts, exact cgroup
memory limit, `nvidia-smi`, a real CuPy GPU kernel, Python imports, backed h5ad
opening, and core R packages.

## The single registration form

Only `workbench.env` is account-specific:

| Group | Variables |
|---|---|
| Unique names | `COMPOSE_PROJECT_NAME`, `CONTAINER_NAME`, `IMAGE_NAME`, `IMAGE_TAG` |
| Base image | `BASE_IMAGE` |
| Identity | `CONTAINER_USER`, `HOST_UID`, `HOST_GID`, `HOST_EXTRA_GID` |
| Writable path | `WORKSPACE_HOST` |
| Read-only paths | `INPUT_A_HOST`, `INPUT_B_HOST`, `INPUT_FILE_HOST`, `INPUT_FILE_NAME` |
| Limits | `MEM_LIMIT`, `MEMSWAP_LIMIT`, `SHM_SIZE`, `CPU_LIMIT`, `THREAD_LIMIT` |

Set `HOST_EXTRA_GID` to a shared-data group listed by `id -G`. If no extra
group is needed, repeat `HOST_GID`.

### Mount contract

| Host registry value | Container path | Access |
|---|---|---|
| `WORKSPACE_HOST` | `/workspace` | read/write |
| `INPUT_A_HOST` | `/inputs/input-a` | read-only directory |
| `INPUT_B_HOST` | `/inputs/input-b` | read-only directory |
| `INPUT_FILE_HOST` | `/inputs/input-file/INPUT_FILE_NAME` | read-only h5ad |

The third input is used by the smoke test and must be a readable `.h5ad` file.
Rename the three generic slots in your project documentation if desired; their
container paths can stay generic.

For a fourth input, add one variable to `workbench.env` and one long-form bind
mount to `compose.yaml`. Keep `read_only: true` and
`bind.create_host_path: false`. Mount changes require container recreation but
not image rebuilding; `./workbench up` applies the changed Compose definition.

## Multi-project workbench

Create each analysis project once:

~~~bash
./workbench init-project example-analysis
~~~

This creates:

~~~text
/workspace/projects/example-analysis/
├── README.md
├── notebooks/
├── scripts/
├── config/
├── data/
│   ├── interim/
│   └── processed/
├── results/
│   ├── h5ad/
│   ├── figures/
│   └── tables/
├── logs/
└── tmp/
~~~

The entrypoint creates only shared workbench infrastructure such as cache,
Conda, Jupyter, R-library, project-root, and temporary directories. It never
creates, resets, or edits an analysis project.

## VS Code and R

1. Use VS Code Remote SSH to connect to the workstation.
2. Choose **Dev Containers: Attach to Running Container**.
3. Select the configured container name.
4. In `.ipynb`, select `/opt/conda/bin/python`.

Open terminal R with:

~~~bash
./workbench r
~~~

Run any other command with:

~~~bash
./workbench exec COMMAND [ARGS...]
~~~

## Lifecycle and persistence

~~~bash
./workbench ps
./workbench logs
./workbench stop
./workbench up
./workbench down
~~~

- `stop` retains the container and its writable layer.
- `down` removes the container and Compose network.
- Files in the host-backed `/workspace` persist after stop, down, rebuild, and
  container replacement.
- Files written elsewhere in the container may disappear after `down` or image
  replacement.
- Additional user Conda environments should live in `/workspace/.conda/envs`,
  which is already configured as the first `CONDA_ENVS_PATH`.

The container normally stays alive with `sleep infinity` and
`restart: unless-stopped`. It restarts after daemon/host restart unless it was
explicitly stopped.

## Memory rules for large single-cell data

The container limit is a ceiling, not a reservation. Two containers configured
for 150 GiB cannot both consume 150 GiB on a 256 GiB host.

- Keep count matrices sparse (normally CSR/CSC); never call `toarray()` on a
  multi-million-cell matrix.
- Prefer `float32`/`int32` where scientifically valid.
- Treat AnnData `backed="r"` as file backing, not universal streaming: many
  Scanpy operations still materialize data or copies.
- Avoid a single in-memory all-cell merge when an on-disk shard +
  `concat_on_disk` workflow is sufficient.
- Process one major cell type or one heavy GPU job at a time.
- Write new large outputs to a temporary name, close and validate them, then
  rename; do not overwrite the only valid h5ad.
- Record peak RSS and free disk space for long jobs.

## Package changes

- Edit `env/requirements-python.txt` for small base-Python additions.
- Edit `env/environment-r.yml` for the shared terminal-R environment.
- Rebuild with `./workbench build` after changing either list.
- Create experiment-specific environments under `/workspace/.conda/envs` when
  the package set should not become part of the shared image.

The pinned upstream image is configurable because NVIDIA driver/CUDA
compatibility differs between hosts. Do not replace `BASE_IMAGE` with an
unpinned moving tag in a production workbench; test any update with
`./workbench smoke`.

## Migrating to another account

Each account should use its own clone or configuration directory:

1. Copy/clone this repository.
2. Copy `workbench.env.example` to the untracked `workbench.env`.
3. Fill that account's username, IDs, unique Docker names, workspace, and
   allowed inputs.
4. Run preflight, build, up, and smoke in order.

Keep deployment-specific account names, host paths, institutional labels,
participant metadata, and secrets out of the tracked repository. Public
maintainer attribution is documented in the Maintainer section.

## License

MIT
