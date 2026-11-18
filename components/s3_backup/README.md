# s3_backup — snapshots of a bucket, taken only when something changed

Used by `s3_backup` in [s3rds](../../modules/s3rds), [s3keepass](../../modules/s3keepass) and
[lambdavault](../../modules/lambdavault):

```hcl
  s3_backup = { enabled = true, every = "1d", keep_days = 30 } # every: <n>h or <n>d
```

## Rules

- **Every `every`** the copier Lambda lists the backed-up objects (with their ETags) and reads the newest
  snapshot's `manifest.json`.
- It takes a **full snapshot** (every object, copied to `<UTC time>/<key>`, then `manifest.json` last) when:
  - there is no snapshot yet,
  - an object was added, removed or rewritten (the keys or their source ETags differ from the manifest), or
  - the newest snapshot is **half of `keep_days`** old (rounded down, at least 1 day; 30 → 15 days), so a fresh
    one exists before the newest expires.

  Otherwise it does nothing.
- Only a folder with `manifest.json` counts as a snapshot; a run that stopped half way leaves none, and is ignored.
- Each snapshot is deleted `keep_days` after it was taken (the backup bucket's lifecycle rule).
- `every` must be at most half of `keep_days` (rounded down, at least 1d); a longer one is refused at plan time.
- The copier can list, read `manifest.json` and write in the backup bucket; it cannot delete anything.

## The backup bucket

`<bucket>-backup`, flat: one folder per snapshot, named by its UTC time; inside, the same keys as the source.

```
s3://<bucket>-backup/
  2026-11-17T030000Z/
    manifest.json          {"time": ..., "objects": {"<key>": "<source ETag>", ...}}
    keepass/a.kdbx
    keepass/b.kdbx
  2026-12-02T030000Z/
    ...
```

## Restore

List the snapshots (the newest is last):

```bash
aws s3 ls s3://<bucket>-backup/
```

Put a whole snapshot back (`manifest.json` stays in the backup bucket):

```bash
aws s3 sync s3://<bucket>-backup/<snapshot>/ s3://<bucket>/ --exclude "manifest.json"
```

Or one file:

```bash
aws s3 cp s3://<bucket>-backup/<snapshot>/<key> s3://<bucket>/<key>
```

`sync` overwrites and adds back; objects created after the snapshot stay. To remove those as well, sync one backed-up
prefix with `--delete` (check with `--dryrun` first), e.g.
`aws s3 sync s3://<bucket>-backup/<snapshot>/keepass/ s3://<bucket>/keepass/ --delete` — never the bucket root:
a snapshot holds only the backed-up prefixes, so `--delete` there would remove the rest (e.g. s3keepass's `log/`).
