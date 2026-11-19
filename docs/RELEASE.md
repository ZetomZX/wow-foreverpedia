# Release process

This document defines the repeatable release process for Foreverpedia. Release
archives are build outputs: keep them under the ignored local `dist/` directory
and publish them as GitHub Release assets. Do not commit ZIP archives to Git.

## Version model

`release.toml` is the release metadata source used by
`tools/package_release.py`:

- `bundle_version` identifies the complete public release, its Git tag, the
  combined archive, and its manifest.
- `core_version` identifies the `Foreverpedia` addon and Core-only archive.
- `data_version` identifies `Foreverpedia_Data` and its standalone archive.
- `minimum_data_version` is the oldest Data addon accepted by the current Core.
- `interface`, `data_schema`, `client_build`, and `questiedb_version` pin the
  compatibility and generated-data contracts.

Increment `bundle_version` for every public release. Increment `core_version`
when files under `Foreverpedia/` change. Increment `data_version` when files
under `Foreverpedia_Data/` or their generated inputs change. A release may carry
different Core and Data versions; the combined package always contains the
latest approved version of each component.

Use semantic versions:

- Patch: compatible fixes, documentation, or data refreshes.
- Minor: backward-compatible user-facing features.
- Major: incompatible saved-variable, addon, or data contract changes.

Mirror changed component versions in their runtime metadata:

- Core: `Foreverpedia/Foreverpedia.toc`.
- Data: `Foreverpedia_Data/Foreverpedia_Data.toc` and
  `Foreverpedia_Data/Bootstrap.lua`.
- Update `minimum_data_version` in `release.toml`, `Foreverpedia/Config.lua`, and
  `Foreverpedia/Foreverpedia.toc` only when Core requires a newer Data package.

The package validation must fail if these values disagree.

## Prepare the changelog

Keep commits small and descriptive. Prefer subjects beginning with `feat:`,
`fix:`, `data:`, `docs:`, `test:`, or `chore:` so the release range is easy to
classify.

Find the previous release tag and generate a technical draft:

```powershell
git tag --sort=-version:refname
git log --first-parent --no-merges --pretty=format:"- %s (%h)" v0.9.3..HEAD
git diff --stat v0.9.3..HEAD
git diff --name-status v0.9.3..HEAD
```

Replace `v0.9.3` with the actual previous tag. Curate the result into the
`[Unreleased]` section of `CHANGELOG.md`. Include only player-visible addon
functionality: features, behavior changes, bug fixes, compatibility changes,
and data changes that affect information shown in game. Exclude refactors,
tests, documentation, CI, repository cleanup, packaging implementation, and
version-only metadata. Before tagging, rename `[Unreleased]` to
`[<bundle_version>] - YYYY-MM-DD` and create a fresh empty `[Unreleased]`
section above it.

For a completed pair of releases, the exact commit range is:

```powershell
git log --first-parent --no-merges --pretty=format:"- %s (%h)" v0.9.3..v0.9.4
```

The GitHub comparison URL follows this form:

```text
https://github.com/ZetomZX/wow-foreverpedia/compare/v0.9.3...v0.9.4
```

## Build and verify

Start from a clean `main` branch. If generated inputs changed, rebuild the
affected databases before testing:

```powershell
python tools/build_recipe_database.py
python tools/build_search_database.py
python tools/build_source_database.py
python tools/build_questie_snapshot.py
python -m unittest discover -s tests -v
python tools/package_release.py
```

The final command validates metadata, pinned inputs, archive layout, checksums,
and generated reference records. It produces:

```text
dist/Foreverpedia-<core_version>-Core.zip
dist/Foreverpedia_Data-<data_version>.zip
dist/Foreverpedia-<bundle_version>-WoW-Forever.zip
dist/Foreverpedia-<bundle_version>-WoW-Forever.manifest.json
```

Before publishing:

1. Confirm `git status` contains only intended release-source changes.
2. Inspect the manifest and confirm all archive names and versions.
3. Install the combined archive into a clean WoW AddOns directory.
4. Smoke-test startup, `/fp`, search, item navigation, crafting tree, language
   switching, and gamepad navigation when available.
5. Confirm the ZIP roots are addon directories, not an extra wrapper folder.

## Commit and tag

Commit the version metadata and changelog only after tests and packaging pass:

```powershell
git add -A
git commit -m "Release Foreverpedia <bundle_version>"
git tag -a "v<bundle_version>" -m "Foreverpedia <bundle_version>"
git push origin main
git push origin "v<bundle_version>"
```

Treat a published tag as immutable. If a published release is wrong, publish a
new patch version instead of moving the tag.

## Publish on GitHub

GitHub Releases are the canonical public home for built archives. The simplest
browser workflow is: open the repository, choose **Releases**, choose
**Draft a new release**, select the already-pushed tag, paste the curated
changelog, attach the four files from `dist/`, verify the draft, and publish it.

With GitHub CLI, first place the curated release text in the ignored file
`dist/release-notes-<bundle_version>.md`, then create a draft:

```powershell
gh release create "v<bundle_version>" `
  "dist/Foreverpedia-<bundle_version>-WoW-Forever.zip" `
  "dist/Foreverpedia-<core_version>-Core.zip" `
  "dist/Foreverpedia_Data-<data_version>.zip" `
  "dist/Foreverpedia-<bundle_version>-WoW-Forever.manifest.json" `
  --title "Foreverpedia <bundle_version>" `
  --notes-file "dist/release-notes-<bundle_version>.md" `
  --verify-tag `
  --draft
```

Review the draft and publish it in the browser, or run:

```powershell
gh release edit "v<bundle_version>" --draft=false
```

The combined `WoW-Forever` archive is the required clean-install download and
the manifest is its required verification metadata. The Core-only and Data-only
archives are optional assets for independent updates. QuestieDB is never
embedded and must be installed separately when its extended live data is
desired. Publish the appropriate user-facing package to CurseForge as a
separate distribution step.

## Final checks

- The GitHub Release tag resolves to the tested release commit.
- The Release page contains all expected assets and the manifest.
- The release notes match `CHANGELOG.md`.
- The combined archive installs without manual restructuring.
- `main` is clean and matches `origin/main` after publishing.
- No credentials, local observations, `dist/` outputs, or temporary files are
  committed.
