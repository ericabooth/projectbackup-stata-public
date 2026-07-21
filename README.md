# projectbackup — zip up a project folder, subfolders and all, in native Stata

**Snapshot a whole project into a dated `.zip` with one command — no `tar`, no 7-Zip, no PowerShell. Just Stata.**

```stata
projectbackup "~/Documents/MyProject", timestamp toc
```

`projectbackup` archives a folder and everything under it into a single `.zip`, using nothing but Stata's own [`zipfile`](https://www.stata.com/help.cgi?zipfile) command and Mata. Because it is 100% native, the *same* command behaves identically on macOS, Windows, and Linux — and it runs in locked-down environments where you cannot shell out to external programs.

It is built for the everyday "let me snapshot this before I break it" habit: point it at a project folder and it drops a (optionally timestamped) zip into an `_archive` subfolder, and can keep a running Markdown log of every backup you take. Before it writes anything, it walks the tree and warns you about the things that actually make zipping fail — a folder that's too big, too many files, or paths so deeply nested that Windows will refuse to extract them.

## Install

```stata
net install projectbackup, from("https://raw.githubusercontent.com/ericabooth/projectbackup-stata-public/main/") replace force
help projectbackup
```

No dependencies. Needs Stata 14 or newer (for `zipfile` and Mata). Nothing to configure, no external tools to install.

## Quick start

```stata
projectbackup                                  // back up the current folder
projectbackup "~/MyProject", dryrun            // measure it first, write nothing
projectbackup "~/MyProject", timestamp toc     // dated snapshot + a logged entry
```

A plain run writes `<folder>/_archive/backup_<foldername>.zip`. Paths inside the zip are stored **relative** to the source folder, so unzipping into an empty directory rebuilds your project's layout exactly.

## What each option does

| option | what it does |
|--------|--------------|
| `archive(dir)`   | where the zip goes (default `<folder>/_archive`, created if missing) |
| `prefix(str)`    | leading part of the zip name (default `backup_<foldername>`) |
| `timestamp`      | append `_YYYYMMDD_HHMMSS` — unique names that sort by date |
| `label(str)`     | insert your own tag, e.g. `backup_myproj_pre-refactor.zip` |
| `replace`        | overwrite an existing zip of the same name |
| `exclude(pats)`  | space-separated top-level names to skip; `*` and `?` wildcards ok |
| `nodotfiles`     | skip top-level dot-entries (`.git`, `.DS_Store`, `.Rhistory`, …) |
| `toc`            | create/append `_backup_log.md` in the archive folder |
| `note(str)`      | note recorded in the log row (turns on `toc`) |
| `manifest`       | write `<zipname>_manifest.txt` listing every archived file |
| `keep(#)`        | after backing up, keep only the newest `#` **timestamped** backups |
| `removeall`      | delete all matching backups and make no new one |
| `zippy`          | also save a `.zippy` copy for Stata Journal submissions |
| `dryrun`         | scan and report size / counts / path lengths only; write nothing |
| `force`          | override the size / file-count safety stops |

`projectbackup` is `rclass` — it returns `r(zipfile)`, `r(nfiles)`, `r(ndirs)`, `r(bytes)`, `r(zipbytes)`, `r(maxdepth)`, `r(maxplen)`, `r(size)`, `r(seconds)`, and more. See `help projectbackup`.

## The best bits

**Look before you leap.** `dryrun` does the full walk and tells you what you're about to zip, without writing a byte:

```stata
. projectbackup "~/BigStudy", dryrun

projectbackup dry run ----------------------------------------
  source folder:   ~/BigStudy
  would write:     ~/BigStudy/_archive/backup_BigStudy.zip
  files:           12,884
  subfolders:      206
  total size:      3.41 GB
  largest file:    1.90 GB  (data/raw/panel_full.dta)
  deepest nesting: 7 level(s)
  longest path:    173 character(s)
--------------------------------------------------------------
```

**It refuses to hang on a monster folder.** Zipping multi-GB trees through a single-threaded `zipfile` call is slow and can produce archives that won't open elsewhere, so `projectbackup` stops (with advice) before it starts when it sees:

- total size over **2 GB**
- any single file over **2 GB** (the classic ZIP per-file limit)
- more than **100,000 files**

Add `force` to zip anyway, or take the advice it prints — usually "exclude the heavy data folders and back up code separately":

```stata
projectbackup, exclude(data output *.dta) nodotfiles timestamp
```

It also *warns* (without blocking) on a folder over 500 MB, over 20,000 files, or — the Windows gotcha — any path longer than 200 characters, which can blow past Windows' 260-character `MAX_PATH` limit when the zip is later extracted under a deep folder.

**A log of every backup.** With `toc` (or `note()`), a Markdown table grows in the archive folder — it renders as a real table on GitHub and stays readable as plain text everywhere:

```markdown
# Backup log

| date | time | archive | files | size | note |
|------|------|---------|-------|------|------|
| 20 Jul 2026 | 21:37:53 | backup_myproj_20260720_213753.zip | 128 | 4.2 MB | pre-refactor |
```

**Rolling snapshots.** `keep(#)` prunes the timestamped series down to the newest few, so a scripted "back up on every run" doesn't fill your disk:

```stata
projectbackup, timestamp keep(5)     // always keep the 5 most recent
```

**A manifest without unzipping.** `manifest` writes a sorted, plain-text index of exactly what went into the zip — handy for a "what was in that backup?" glance months later.

**A `.zippy` for the Stata Journal.** Submitting a package to the [*Stata Journal*](https://www.stata-journal.com/submissions/)? Their guidelines ask authors to rename `.zip` attachments, because mail servers routinely strip them. `zippy` writes both the normal `.zip` and a byte-identical `.zippy` copy you can email safely; the editor renames it back on receipt.

```stata
projectbackup "~/sj-package", zippy
```

## Examples

```stata
* 1. Simplest — back up the current project
projectbackup

* 2. Dated snapshot with a log entry
projectbackup ".", timestamp toc

* 3. Code only — skip data, output, and version control
projectbackup, exclude(data output *.dta) nodotfiles timestamp

* 4. A named milestone with a note in the log
projectbackup, label(before-reviewer-revisions) timestamp toc note(v1 submitted)

* 5. Rolling snapshots — keep only the five most recent
projectbackup, timestamp keep(5)

* 6. Send the archive outside the project (e.g. to a synced folder)
projectbackup "~/MyProject", archive("~/Dropbox/backups") timestamp

* 7. Package a folder for a Stata Journal submission
projectbackup "~/sj-package", zippy

* 8. Clear out every backup for this project
projectbackup, removeall
```

A runnable tour is in [`example_projectbackup.do`](example_projectbackup.do), and the regression tests are in [`projectbackup_test.do`](projectbackup_test.do).

## How it works (and its limits)

The tree is walked once in Mata to gather counts, byte totals, and path lengths, then handed to a single `zipfile` call with paths relative to the source folder. The archive folder is never packed into its own backup. Everything is native Stata, so there's no configuration and no platform-specific behavior — with one exception worth knowing: Windows' 260-character path limit applies when *extracting*, which is exactly what the long-path warning is there to catch in advance. For genuinely multi-GB trees, a dedicated archiver (7-Zip, `tar`) will be faster and give you compression control; `projectbackup` will tell you when you've reached that point.

## License

MIT © 2026 Eric A. Booth. See [LICENSE](LICENSE).
