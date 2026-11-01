# HAMMER tools provenance

The `newfs_hammer/`, `mount_hammer/` and `hammer/` directories were imported
unmodified from DragonFly BSD `sbin/` at commit
`4e10f78d03f3d76c5bbe99c5d65022a03ea21e2e`
(https://github.com/DragonFlyBSD/DragonFlyBSD). The import is BSD 3-clause
licensed (The DragonFly Project); every upstream notice is kept.

Per-file SHA256 hashes of the imported bytes are in `ORIGIN`
(`sha256sum -c ORIGIN`). Local changes are recorded in later commits and in
`src/kernel-7/bsd/hammer/PORTING.md`.

The kernel side and its provenance are in `src/kernel-7/bsd/hammer/ORIGIN`.
Design: `docs/superpowers/specs/2026-10-17-hammer-design.md`.
