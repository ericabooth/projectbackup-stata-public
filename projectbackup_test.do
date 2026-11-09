* projectbackup_test.do -- regression test for projectbackup
* run:  stata-mp -b do projectbackup_test.do   (from the repo folder)
clear all
set more off
version 14

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

* ---- build a toy project tree in the scratch dir ---------------------------
local root "`c(tmpdir)'/pbtest_root"
mata: _pb_rmtree(st_local("root"))
mkdir "`root'"
mkdir "`root'/proj"
mkdir "`root'/proj/code"
mkdir "`root'/proj/code/deeper"
mkdir "`root'/proj/data raw"
mkdir "`root'/proj/output"

tempname fh
foreach f in "proj/readme.txt" "proj/code/main.do" "proj/code/deeper/utils.do" ///
	"proj/data raw/data file.csv" "proj/output/fig1.txt" {
	file open `fh' using "`root'/`f'", write text
	file write `fh' "hello from `f'" _n
	forvalues i = 1/50 {
		file write `fh' "line `i' of filler content to give the zip something to chew on" _n
	}
	file close `fh'
}
* a dotfile to test nodotfiles
file open `fh' using "`root'/proj/.DS_Store_fake", write text
file write `fh' "junk" _n
file close `fh'

di as res _n "=== T1: dryrun scans without writing ==="
projectbackup "`root'/proj", dryrun
assert r(nfiles)   == 6
assert r(ndirs)    == 4
assert r(bytes)    > 0
assert r(maxdepth) == 3
capture confirm file "`root'/proj/_archive/backup_proj.zip"
assert _rc != 0

di as res _n "=== T2: basic backup, default archive, roundtrip ==="
projectbackup "`root'/proj"
assert r(nfiles) == 6
local zip1 `"`r(zipfile)'"'
confirm file `"`zip1'"'
assert r(zipbytes) > 0
* roundtrip: unzip and count what comes back
mkdir "`root'/rt"
local pwd0 "`c(pwd)'"
cd "`root'/rt"
unzipfile `"`zip1'"'
cd "`pwd0'"
confirm file "`root'/rt/readme.txt"
confirm file "`root'/rt/code/deeper/utils.do"
confirm file "`root'/rt/data raw/data file.csv"
* the archive folder itself must NOT be inside the zip
capture confirm file "`root'/rt/_archive/backup_proj.zip"
assert _rc != 0

di as res _n "=== T3: existing zip without replace errors 602 ==="
capture noisily projectbackup "`root'/proj"
assert _rc == 602

di as res _n "=== T4: replace works ==="
projectbackup "`root'/proj", replace
confirm file `"`r(zipfile)'"'

di as res _n "=== T5: timestamp + toc + note + manifest + zippy ==="
projectbackup "`root'/proj", timestamp toc note(first stamped run) manifest zippy
local zip2 `"`r(zipfile)'"'
confirm file `"`zip2'"'
confirm file `"`r(zippy)'"'
confirm file "`root'/proj/_archive/_backup_log.md"
* log contains the zip name and the note
tempname lh
local found 0
file open `lh' using "`root'/proj/_archive/_backup_log.md", read text
file read `lh' line
while r(eof) == 0 {
	if strpos(`"`line'"', "first stamped run") local found 1
	file read `lh' line
}
file close `lh'
assert `found' == 1
* manifest exists and lists the nested file
local manifile = substr(`"`zip2'"', 1, strlen(`"`zip2'"') - 4) + "_manifest.txt"
confirm file `"`manifile'"'
local found 0
file open `lh' using `"`manifile'"', read text
file read `lh' line
while r(eof) == 0 {
	if strpos(`"`line'"', "code/deeper/utils.do") local found 1
	file read `lh' line
}
file close `lh'
assert `found' == 1

di as res _n "=== T6: exclude() drops top-level folders; nodotfiles drops dotfiles ==="
projectbackup "`root'/proj", dryrun exclude("output data*") nodotfiles
assert r(nfiles) == 3        // readme + 2 code files
assert r(ndirs)  == 2        // code + deeper

di as res _n "=== T7: label() in the zip name ==="
projectbackup "`root'/proj", label(pre refactor) replace
assert strpos(`"`r(zipfile)'"', "backup_proj_pre_refactor.zip") > 0

di as res _n "=== T8: keep() prunes to the newest N ==="
sleep 1100
projectbackup "`root'/proj", timestamp
sleep 1100
projectbackup "`root'/proj", timestamp keep(2)
local nz 0
local zl : dir "`root'/proj/_archive" files "backup_proj_2*.zip", respectcase
foreach f of local zl {
	local ++nz
}
assert `nz' == 2

di as res _n "=== T9: removeall sweeps the archive ==="
projectbackup "`root'/proj", removeall
assert r(nremoved) > 0
local nz 0
local zl : dir "`root'/proj/_archive" files "backup_proj*.zip", respectcase nofail
foreach f of local zl {
	local ++nz
}
assert `nz' == 0

di as res _n "=== T10: bad folder errors 601 ==="
capture noisily projectbackup "`root'/no_such_dir_xyz"
assert _rc == 601

di as res _n "=== T11: default folder is the cwd ==="
cd "`root'/proj"
projectbackup, replace
assert r(nfiles) == 6
cd "`pwd0'"

di as res _n "=== T12: external archive folder ==="
projectbackup "`root'/proj", archive("`root'/ext_archive") timestamp
confirm file `"`r(zipfile)'"'
assert strpos(`"`r(zipfile)'"', "ext_archive") > 0

di as res _n "=== T13: a second run does not pack the default _archive ==="
projectbackup "`root'/proj", timestamp
local n1 = r(nfiles)
sleep 1100
projectbackup "`root'/proj", timestamp
assert r(nfiles) == `n1'

di as res _n "=== T14: shared archive -- one prefix extending another is left alone ==="
foreach d in wave1 wave10 {
	mkdir "`root'/`d'"
	file open `fh' using "`root'/`d'/a.txt", write text
	file write `fh' "`d'" _n
	file close `fh'
}
mkdir "`root'/shared"
projectbackup "`root'/wave10", archive("`root'/shared")
projectbackup "`root'/wave10", archive("`root'/shared") timestamp
sleep 1100
projectbackup "`root'/wave10", archive("`root'/shared") timestamp
sleep 1100
projectbackup "`root'/wave1", archive("`root'/shared") timestamp
sleep 1100
projectbackup "`root'/wave1", archive("`root'/shared") timestamp keep(1)
local zl : dir "`root'/shared" files "backup_wave10*.zip", respectcase
assert `: word count `zl'' == 3
local zl : dir "`root'/shared" files "backup_wave1_*.zip", respectcase
assert `: word count `zl'' == 1
projectbackup "`root'/wave1", archive("`root'/shared") removeall
assert r(nremoved) == 1
local zl : dir "`root'/shared" files "backup_wave10*.zip", respectcase
assert `: word count `zl'' == 3

di as res _n "=== T15: keep() leaves labelled series alone and keeps the new zip ==="
mkdir "`root'/lab"
projectbackup "`root'/proj", archive("`root'/lab") timestamp label(m1)
sleep 1100
projectbackup "`root'/proj", archive("`root'/lab") timestamp label(m2)
sleep 1100
projectbackup "`root'/proj", archive("`root'/lab") timestamp
sleep 1100
projectbackup "`root'/proj", archive("`root'/lab") timestamp keep(2)
local newzip `"`r(zipfile)'"'
sleep 1100
projectbackup "`root'/proj", archive("`root'/lab") timestamp keep(1)
confirm file `"`r(zipfile)'"'
capture confirm file `"`newzip'"'
assert _rc != 0                         // the older plain stamp was rotated out
local zl : dir "`root'/lab" files "backup_proj_2*.zip", respectcase
assert `: word count `zl'' == 1
local zl : dir "`root'/lab" files "backup_proj_m*.zip", respectcase
assert `: word count `zl'' == 2         // both labelled snapshots survive

di as res _n "=== T16: same-second collisions rotate by counter, not name ==="
mkdir "`root'/cc"
foreach k in "" _1 _2 _10 {
	file open `fh' using "`root'/cc/backup_proj_20200101_000000`k'.zip", write text
	file write `fh' "x" _n
	file close `fh'
}
projectbackup "`root'/proj", archive("`root'/cc") timestamp keep(2)
confirm file `"`r(zipfile)'"'
confirm file "`root'/cc/backup_proj_20200101_000000_10.zip"
capture confirm file "`root'/cc/backup_proj_20200101_000000_2.zip"
assert _rc != 0

mata: _pb_rmtree(st_local("root"))
di as res _n "=== ALL projectbackup TESTS PASSED ==="
exit
