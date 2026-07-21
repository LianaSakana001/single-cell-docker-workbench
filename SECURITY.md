# Security and data-safety notes

This project reduces accidental damage inside a workbench container; it is not
a security boundary between people who can control the same Docker daemon.

## Shared Docker host

Membership in a rootful Docker-access group is effectively root-level access to
the host. Any such user can create a different container that mounts host files,
inspect other containers, or bypass the restrictions in this Compose file.
Unique container names and Unix permissions prevent mistakes, not a malicious
Docker-authorized user. Use rootless Docker, separate virtual machines, or an
administrator-managed scheduler when isolation between users is required.

## Protections in this template

- The analysis process runs as the matching non-root host UID/GID.
- Linux capabilities are dropped and `no-new-privileges` is enabled.
- No host port, Docker socket, privileged mode, or host PID namespace is used.
- Raw/reference inputs use narrow read-only bind mounts.
- The writable bind mount is limited to `/workspace`.
- `create_host_path: false` prevents a typo from silently creating a root-owned
  input directory.
- Memory, memory+swap, CPU, process, shared-memory, and log-size limits are set.
- `umask 027` keeps newly created workbench files private from unrelated users.

## Operator rules

1. Never commit `workbench.env`; it contains local account names and paths.
2. Never place passwords, access tokens, SSH keys, clinical identifiers, or
   participant-level metadata in this repository.
3. Do not mount `/`, `/home`, a whole shared data root, or the Docker socket.
4. Run `./workbench preflight` after changing identity or mount values.
5. Run `./workbench smoke` after building or changing the image.
6. Back up irreplaceable outputs outside the container writable layer.
7. Coordinate heavy jobs: two containers may each have a 150 GiB ceiling, but a
   256 GiB host cannot allow both to reach that ceiling simultaneously.

## Persistence

`./workbench stop` stops but retains the container. `./workbench down` removes
the container and its writable layer. In both cases, files under the bind-mounted
`/workspace` remain on the host. Files written elsewhere in the container may be
lost when the container is removed or rebuilt.

Report suspected credential exposure privately to the repository owner. Revoke
the exposed credential before relying on a Git history rewrite.
