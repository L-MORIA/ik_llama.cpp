@echo off
REM Double-click launcher for sync_ik_repos.sh (requires Git Bash)
setlocal
set "HERE=%~dp0"
set "REPO=%HERE%.."
pushd "%REPO%"
bash "personal/sync_ik_repos.sh" %*
popd
