# Synology NAS autonomous deployment

This repository is the source for the **Calendario Gare** HUB.

## NAS layout

- Stack root: `/volume1/docker/bogdan-sites`
- Race HUB local port: `8082`
- Repository: `Zenchak/race-map-bog`
- Existing updater: `bogdan-sites-updater`

## Autonomous deploy

The workflow `.github/workflows/nas-deploy.yml` runs on a repository-level
self-hosted GitHub Actions runner installed on the Synology and labelled
`synology`.

On every push to `main`, `scripts/nas-deploy.sh`:

1. discovers the real local checkout by inspecting Git remotes under the stack root;
2. fetches and hard-resets that checkout to the exact GitHub commit;
3. verifies `index.html`, `app.html`, and `extra-races.js`;
4. checks the files actually served by `http://127.0.0.1:8082`;
5. writes `/volume1/docker/bogdan-sites/deploy-status-race-map.json`;
6. also exposes a local `deploy-status.json` in the deployed race repo when writable.

A successful GitHub Actions run therefore means both the Git checkout **and the NAS-served HUB**
were verified, rather than merely assuming that the periodic updater completed.

## Required runner permissions

The runner account needs:
- read/write access to the local checkout of `race-map-bog`;
- read/write access to `/volume1/docker/bogdan-sites` for the status file;
- local TCP access to `127.0.0.1:8082`.

It does **not** need DSM administrator access or access to unrelated NAS data.
