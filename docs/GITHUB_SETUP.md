# Connect this folder to a new GitHub repository

This folder is prepared as a standalone local Git repository on the `main` branch. It has no GitHub remote and has not been uploaded. Its history starts with this community source snapshot; the universal-modder development history is not copied into it.

## GitHub Desktop

1. Choose **File → Add local repository** and select this folder.
2. Review the files and make any changes you want before publishing.
3. Use **Publish repository**. Suggested name: `ftl-tabletop-vr`.
4. Suggested description: `Experimental OpenXR tabletop VR mod for FTL: Faster Than Light, using your own game installation.`
5. Select your account and visibility, then publish when ready.

## Git command line

Create an **empty** repository on GitHub. Leave automatic README, ignore and license creation unchecked because this folder already has those files. In a terminal opened in this folder:

```powershell
git status
# If you changed or added files, review and commit them first:
git add .
git commit -m "Prepare community release"

# Replace YOUR-ACCOUNT with your actual account or organization:
git remote add origin https://github.com/YOUR-ACCOUNT/ftl-tabletop-vr.git
git push -u origin main
```

If there are no changes to commit, skip that commit command. If a remote named `origin` already exists, inspect it with `git remote -v` before changing it.

## After publishing

- Suggested topics: `ftl`, `vr`, `openxr`, `godot`, `steamvr`, `steam-frame`, `modding`.
- Keep the root [MIT license](../LICENSE), [third-party notices](../THIRD_PARTY_NOTICES.md) and [license-reference documents](../licenses/README.md) with the source when copying or redistributing it.
- The issue forms and Windows Python-test workflow are already included. The workflow does not install or run FTL and does not test a VR headset.
- The first public description should call this an **experimental source alpha** and link to [project status](STATUS.md).
- Keep local game data and prepared labs outside commits. `.gitignore` covers the expected generated folders and game formats.
- Do not upload a ZIP of a working game installation as a release. A future client release should contain only the mod/client and generate game-dependent data locally.
- A gameplay demo should be clearly identified as headset or desktop footage. Credit FTL's creators in the video/description, following [Subset's video policy](https://subsetgames.com/faq.html).

The packaged source does not include local testing captures or the development machine's launch configuration.
