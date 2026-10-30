# beets

Helm chart running [beets](https://beets.io) as a scheduled **in-place tagger** next to Lidarr.
Lidarr owns file names and folders; beets only rewrites tag content.

It follows the "side-by-side persistent beets" pattern from the
[Servarr wiki](https://wiki.servarr.com/lidarr/beets-integration), adapted to Kubernetes:
the wiki's script-based patterns need beets inside the Lidarr container, which the Lidarr image
does not ship.

## What beets adds on top of Lidarr

Lidarr already writes the core tags and the MusicBrainz IDs. beets adds, among others:

- **`ARTISTS` / `ALBUMARTISTS` multi-valued tags**, which Navidrome prefers for collaborations
  (Lidarr only writes single `ARTIST` / `ALBUMARTIST`)
- the artist name **as credited** on each release
- genres (Last.fm), ReplayGain, embedded cover art, catalog number, barcode
- acoustic fingerprinting (AcoustID) when the incoming tags are poor

## How a run works

Every run (hourly by default):

1. **`beet update -M`** syncs the database with the files on disk: files changed by Lidarr
   (upgrades) are re-read, deleted or renamed files are dropped. `-M` matters: without it,
   `beet update` renames and moves files according to beets' own path format.
2. **`beet import --quiet --incremental /music`** tags, in place, only the album folders that
   are not in the incremental history yet.

The **database is persistent** (`library.db`, `state.pickle` and `import.log` on the `data`
volume): it is built once, then each run only works on what is new. Progress is saved after
every album, so an interrupted run resumes where it stopped.

## Safety

The chart enforces, and refuses to render without:

- `import.move/copy/link/hardlink/reflink: no`: beets never touches file names or folders
- `import.quiet` and `import.incremental: yes`: unattended runs, new albums only
- `import.duplicate_action` set and not `ask`: in a CronJob nobody can answer the prompt,
  and beets would otherwise ask even in quiet mode
- fixed paths for the library, the database and the incremental state

The run script also **refuses to start if the music library is empty or unmounted**: `beet update`
would otherwise drop every item from the database, since their files look deleted.

## Lidarr settings

*Settings > Metadata*:

- **Tag Audio Files with Metadata: For new downloads only**
- **Scrub Existing Tags: off**

The Servarr wiki recommends *Never* for its patterns. This chart deliberately keeps
*For new downloads only*:

- Soularr imports count as new downloads, so Lidarr writes its tags **once, at import**,
  including the exact **MusicBrainz release ID**, and never rewrites them on refresh
  (only *All files, keep in sync with MusicBrainz* would).
- beets reads that ID from the files: with a strong match it uses **that exact release**
  instead of a text search. Both tools therefore always agree on the edition.

Caveat: a Lidarr upgrade or a manual *Retag* brings Lidarr's tags back on that album. The next
`beet update` picks the change up in the database, but the album is not re-enriched
automatically (its folder is already in the incremental history). Re-run it by hand if needed
(see below).

## Requirements

- The Lidarr library mounted at the same place for Lidarr, beets and Navidrome (NFS or a
  `ReadWriteMany` PVC), owned by UID/GID 1000: `fsGroup` does not apply to NFS.
- Outbound internet access (MusicBrainz, AcoustID, cover art sources, Last.fm).

## Installation

```yaml
# my-values.yaml
persistence:
  music:
    nfs:
      server: 192.168.1.10
      path: /export/music
```

```sh
helm install beets ./beets -n music -f my-values.yaml
```

## First build of the database

The first run processes the whole library, which can take hours. Two options:

- **Let the CronJob do it.** Albums without a confident match are skipped and listed in
  `import.log`. If a run hits `activeDeadlineSeconds`, the next one continues.
- **Do it interactively**, to review doubtful albums as you go. Start a shell in a one-off
  pod using the same image, user and volumes, and run `beet import /music`.

## Handling skipped albums

Skipped albums appear as `skip` lines in `/config/import.log`. They are not retried
automatically (`incremental_skip_later: no`), so a hopeless album does not cost MusicBrainz
lookups every hour. To fix one, run beets interactively on it with the incremental history
ignored:

```sh
beet import --noincremental "/music/Artist/Album (Year)"
```

Run `beet` by hand with the same rules as the CronJob: never let it move files. Commands such as
`update`, `mbsync` and `modify` move files by default: always add `-M`.

## Validation status

The chart was rendered in several scenarios and validated against the official Kubernetes 1.31
JSON schemas (CronJob, ConfigMap, PersistentVolumeClaim). The generated `config.yaml` was checked
against beets 2.14.1: every option exists in `config_default.yaml` or in the plugin's own
defaults, every plugin exists, and the safety settings hold. Every `beet` option used by the run
script exists in the 2.14.1 sources. The run script itself was executed against a stub `beet`
reproducing the real behaviour: empty database (first run), populated database, and empty
library (must refuse).

On the very first run, beets prints a series of `Created database backup at: ...-before-...bak`
lines: it applies its internal schema migrations once to the new database and backs it up first.
Those files are copies of an empty database and can be deleted. It has **not been deployed on a real cluster yet**: run
`helm template`, then trigger a manual run on a small library first.

## Sources

- [Servarr Wiki – Lidarr and beets Integration](https://wiki.servarr.com/lidarr/beets-integration)
- [Servarr Wiki – Lidarr Settings (Tag Audio Files with Metadata)](https://wiki.servarr.com/lidarr/settings)
- [beets – command-line reference (`update -M`)](https://beets.readthedocs.io/en/stable/reference/cli.html)
- [beets – configuration (`incremental_skip_later`, `duplicate_action`)](https://beets.readthedocs.io/en/stable/reference/config.html)
- [beets 2.14.1 sources (autotag/match.py, importer, plugins)](https://github.com/beetbox/beets/tree/v2.14.1)
- [mediafile – ARTISTS / ALBUMARTISTS fields](https://github.com/beetbox/mediafile)
- [linuxserver/docker-beets](https://github.com/linuxserver/docker-beets)
- [Navidrome – Tagging Guidelines](https://www.navidrome.org/docs/usage/library/tagging)
