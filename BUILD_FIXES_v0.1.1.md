# v0.1.1 Windows build hardening

This release fixes the GitHub Actions failure seen after staging completed:

`PermissionError: [WinError 32] ... tasks.db`

Root cause: the build self-check created a SQLite Task Center inside `TemporaryDirectory`, but the SQLite connection was still open when Windows tried to delete that temporary directory. Windows does not allow deleting an open SQLite database file.

Changes:

- `TaskCenter.close()` now checkpoints/closes SQLite deterministically.
- the self-check closes Task Center before the temporary directory exits.
- application shutdown closes Task Center cleanly as well.
- staging now checks every native command exit code explicitly.
- dependency downloads have retries and longer timeouts.
- `pip check`, runtime imports, compileall and application self-check must all pass before packaging.
- GitHub Actions now validates that `XiaoZhiSetup.exe` exists and is non-trivial in size.
- the built installer is silently installed on the GitHub Windows runner and the installed private Python/runtime is checked again before the artifact is uploaded.

Expected success markers in Actions:

- `RUNTIME_IMPORTS_OK`
- `SELF_CHECK_OK`
- `STAGE_RUNTIME_OK`
- `INSTALLED_RUNTIME_IMPORTS_OK`
- `SELF_CHECK_OK`
- `INSTALLER_SMOKE_OK`

Only after those checks does the workflow upload `XiaoZhiSetup.exe`.
