*-----------------------------------------------------------------------------
* example_projectbackup.do
* A short tour of projectbackup.  Builds a throwaway project tree in Stata's
* temp folder, then demonstrates each option.  Nothing outside c(tmpdir) is
* touched, and the whole tree is removed at the end.
*-----------------------------------------------------------------------------
version 14
clear all

* If you have net-installed projectbackup you can delete these two lines;
* they let the example run straight from a clone of the repo.
adopath ++ "`c(pwd)'"
discard

* remove a scratch tree with Mata (no shell, so it runs on every platform)
capture mata: mata drop _pb_rmtree()
mata:
void _pb_rmtree(string scalar d)
{
	string colvector f
	real scalar      i

	if (!direxists(d)) return
	f = dir(d, "files", "*", 1)
	for (i = 1; i <= rows(f); i++) unlink(f[i])
	f = dir(d, "dirs", "*", 1)
	for (i = 1; i <= rows(f); i++) _pb_rmtree(f[i])
	rmdir(d)
}
end

*--- build a toy project ------------------------------------------------------
local demo "`c(tmpdir)'/projectbackup_demo"
mata: _pb_rmtree(st_local("demo"))   // start clean if a prior run left files
capture mkdir "`demo'"
foreach d in code "data raw" output .git {
	capture mkdir "`demo'/`d'"
}
tempname fh
foreach f in "code/analysis.do" "code/clean.do" "data raw/survey.csv" ///
	"output/table1.txt" ".git/config" {
	file open `fh' using "`demo'/`f'", write text replace
	file write `fh' "demo content for `f'" _n
	file close `fh'
}

*--- 1. measure first, write nothing -----------------------------------------
projectbackup "`demo'", dryrun

*--- 2. a plain backup -> _archive/backup_projectbackup_demo.zip --------------
projectbackup "`demo'"
display as text "wrote: " as result `"`r(zipfile)'"'

*--- 3. a dated snapshot with a Markdown log entry ---------------------------
projectbackup "`demo'", timestamp toc note(first dated snapshot)
type "`demo'/_archive/_backup_log.md"

*--- 4. code only: skip data, output, and version control --------------------
projectbackup "`demo'", exclude(output *.csv) nodotfiles timestamp
display as text "archived `r(nfiles)' files (code only)"

*--- 5. a named milestone, plus a manifest of what went in -------------------
projectbackup "`demo'", label(pre-refactor) manifest timestamp

*--- 6. keep only the two newest timestamped snapshots -----------------------
projectbackup "`demo'", timestamp keep(2)

*--- 7. a Stata Journal .zippy copy ------------------------------------------
projectbackup "`demo'", label(sj-submission) zippy replace
display as text "zippy copy: " as result `"`r(zippy)'"'

*--- clean up -----------------------------------------------------------------
mata: _pb_rmtree(st_local("demo"))   // works the same on every platform

display as result _n "example_projectbackup.do finished."
