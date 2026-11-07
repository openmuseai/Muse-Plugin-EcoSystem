# Original Flutter math renderer compatibility

Pinned public package `flutter_math_fork 0.7.3`, the same version/checksum in the pinned AppFlowy client. Original package and KaTeX font licenses remain included. `upstream-package.tar.gz` is the original public archive (SHA-256 in openmuse-upstream.json); 381 original files are listed in upstream-files.json.

One controlled patch adapts the baseline LayoutBuilder to the current Flutter callback contract: add RenderObjectWithLayoutCallbackMixin and invoke runLayoutCallback during performLayout. All math parsing, AST, layout, font metrics and fonts otherwise retain original bytes. The patch is reversible; no global package cache or original AppFlowy checkout is changed.

The document adapter keeps TeX source in the original math_equation/formula block. Rendering limits and unsupported syntax never replace source. This package does not certify full SiYuan KaTeX/mhchem compatibility or inline math editing.
