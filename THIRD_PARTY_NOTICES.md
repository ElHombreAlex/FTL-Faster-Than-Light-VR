# Third-party notices

## Project source

The source code, documentation and original procedural model/effect code in this repository are provided under the [MIT license](LICENSE). The upstream **2026 Rehan and universal-modder contributors** copyright notice is retained in that license. An unchanged copy of the upstream notice is also in [licenses/UNIVERSAL-MODDER-LICENSE.txt](licenses/UNIVERSAL-MODDER-LICENSE.txt).

The project was prepared from the FTL example workspace in [universal-modder](https://github.com/rehan-remade/universal-modder). Original contributions are credited to **FTL VR contributors**. Development used OpenAI Codex (GPT-6), with design direction and hardware playtesting by the maintainer.

Third-party license documents included for reference retain their own terms. The MIT license for this project does not replace the terms of an external component.

## External software and reference copies

The following implementations are obtained separately by the player/developer. This repository includes our integration code and license-reference documents; it does not contain their executables, libraries or source trees.

| Component | Inspected version | Terms recorded in the inspected artifact | Local reference |
| --- | --- | --- | --- |
| [Godot](https://godotengine.org/) | 4.7.2 standard Windows engine | MIT; additional licenses for engine components | [Engine license](licenses/GODOT-LICENSE.txt), [component copyrights and full license definitions](licenses/GODOT_COPYRIGHT.txt) |
| [Frida Python bindings](https://github.com/frida/frida-python) | 17.9.0 | wxWindows Library Licence 3.1, including its exception and reference to GNU Library GPL v2 or later | [COPYING](licenses/FRIDA-COPYING.txt) |
| [Capstone](https://www.capstone-engine.org/) | 5.0.9 Python distribution | BSD 3-Clause | [LICENSE](licenses/CAPSTONE-LICENSE.txt) |
| [Pillow](https://python-pillow.org/) | 12.3.0 installed distribution | MIT-CMU for Pillow; additional notices for bundled components | [Full distribution license file](licenses/PILLOW-LICENSE.txt) |
| [NumPy](https://numpy.org/) | 2.3.5 installed distribution | BSD 3-Clause for NumPy; additional notices including OpenBLAS, LAPACK and GCC runtime terms | [Full distribution license file](licenses/NUMPY-LICENSE.txt) |
| [FTL Hyperspace](https://github.com/FTL-Hyperspace/FTL-Hyperspace) | 1.23.2 | CC BY-SA 4.0 for Hyperspace; ZHL/Kilburn attribution and other component notices | [Upstream LICENSE.md](licenses/HYPERSPACE-LICENSE.md) |
| [ftlman](https://github.com/afishhh/ftlman) | 0.7.4 | GNU GPL version 2 text | [Upstream LICENSE](licenses/FTLMAN-LICENSE.txt) |

The copies above come from the inspected source checkouts or installed distributions. Their provenance and SHA-256 hashes are recorded in [licenses/manifest.json](licenses/manifest.json). The Godot documents were obtained through the engine's license-information API, as described in [Godot's licensing guidance](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).

Frida and Capstone are pinned in [requirements.txt](requirements.txt). Pillow and NumPy have minimum-version requirements, so a new installation can resolve to different versions. The copies identify the versions inspected during preparation; preserve the notices supplied with any actual distribution you bundle.

Frida's copied `COPYING` contains the wxWindows exception and refers to the GNU Library GPL base text. The inspected wheel did not contain `COPYING.LIB`. The [GNU Library GPL v2 text](https://www.gnu.org/licenses/old-licenses/lgpl-2.0.html) is linked here for reference. Frida itself is not distributed in this source repository.

Hyperspace's copied license retains its original relative links. Use its [inspected upstream source revision](https://github.com/FTL-Hyperspace/FTL-Hyperspace/blob/db570d728321a5a2c70add0988153373fd4ec08a/LICENSE.md) to follow those links. The hook resolver reads separately obtained Hyperspace signatures locally. The preparation tool constructs its resource package locally from the player's separately obtained Hyperspace release; that generated package is ignored by Git.

## Other prerequisites and references

- [Python](https://docs.python.org/3/license.html) is installed separately. Its terms and the notices of its bundled components remain with that installation.
- [FTL-Version-Rollback](https://github.com/FTL-Hyperspace/FTL-Version-Rollback) supplies the separately obtained rollback patch. No patch or resulting executable is redistributed here; this project does not grant rights to them.
- [Slipstream Mod Manager](https://github.com/Vhati/Slipstream-Mod-Manager) was a reference for archive-format documentation. Its implementation is not included in this repository.
- Valve's [Steam Frame Godot guidance](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/godot) and [controller documentation](https://partner.steamgames.com/doc/steamhardware/steamframe/input) informed the OpenXR integration. SteamVR is obtained separately; no Valve runtime is included.

## FTL content and names

**FTL: Faster Than Light is created by Subset Games. Players must own and supply their own game.**

The project license grants rights to this project's source; it grants no rights to FTL's executables, archives, artwork, character designs, fonts, music, saves or trademarks. These files are not part of this repository. Locally extracted or generated game-dependent data stays in ignored folders. FTL and Steam/Steam Frame names are used to identify compatibility; this project is unofficial and is not endorsed by Subset Games or Valve.

## Future bundled releases

A compiled release must preserve the notices and satisfy the terms of the **actual artifacts it includes**. These source-reference documents are not a complete audit of a future package. A matching Godot build can use the captured engine/component notices; changed builds need refreshed notices. Bundling ftlman, Hyperspace, Frida, Python or Python wheels also requires their artifact-specific notices and any applicable source/attribution obligations. Keep game files and locally generated game resource packages out of public releases.
