# Prism — third-party software and source code

**Prism** is a media player by Nathaniel Labs (Nathaniel School of Music). This page lists the open-source software that is bundled inside `Prism.app` (in `Contents/Frameworks` and `Contents/Resources`), where to get its source code, and the licence it comes under. The full licence texts are also inside the app, in `Prism.app/Contents/Resources/ThirdParty`.

Prism itself is proprietary software. It does not modify any of the components below; they are copied unchanged from their official builds and are used as separate libraries and programs.

## What is bundled

| Component | Version | Used for | Licence | Source |
|---|---|---|---|---|
| VLC media player (libVLC and its plug-ins) | 3.0.23 | Playing MKV, WebM, AVI, FLAC, Opus and other formats | LGPL-2.1 or later (libVLC); some plug-ins GPL-2.0 or later | https://download.videolan.org/pub/videolan/vlc/3.0.23/vlc-3.0.23.tar.xz |
| FFmpeg (`ffmpeg`, `ffprobe` and its libraries) | 8.1.2 | Waveforms, thumbnails, media details and local conversion | GPL-3.0 or later (this build enables GPL components) | https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz |
| x264 | r3222 | Linked into FFmpeg | GPL-2.0 or later | https://code.videolan.org/videolan/x264 |
| x265 | 4.2 | Linked into FFmpeg | GPL-2.0 or later | https://download.videolan.org/pub/videolan/x265/ |
| dav1d | 1.5.3 | AV1 decoding | BSD-2-Clause | https://code.videolan.org/videolan/dav1d |
| SVT-AV1 | 4.1.0 | Linked into FFmpeg | BSD-3-Clause-Clear with AOM patent licence | https://gitlab.com/AOMediaCodec/SVT-AV1 |
| libvmaf | 3.2.0 | Linked into FFmpeg | BSD-2-Clause-Patent | https://github.com/Netflix/vmaf |
| libvpx | 1.16.0 | VP8/VP9 | BSD-3-Clause | https://github.com/webmproject/libvpx |
| LAME | 3.100 | MP3 | LGPL-2.0 or later | https://sourceforge.net/projects/lame/files/lame/3.100/ |
| Opus | 1.6.1 | Opus audio | BSD-3-Clause | https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz |
| OpenSSL | 3.6.3 | Secure connections used by FFmpeg | Apache-2.0 | https://www.openssl.org/source/ |

## Staff notation

The local staff renderer uses Nathaniel Labs Lipi code, VexFlow 4.2.5 (MIT) and Bravura glyph outlines (SIL Open Font License 1.1). VexFlow source: https://github.com/0xfe/vexflow/tree/4.2.5. Bravura source: https://github.com/steinbergmedia/bravura. Their full notices are bundled in `Contents/Resources/ThirdParty`. The VexFlow library and Bravura outlines retain their upstream licences; the Nathaniel Labs importer and UI integration are proprietary.

## Written offer for source code

For the GPL- and LGPL-licensed components above, you can get the complete corresponding source code for the exact component versions shipped in Prism 1.0.0 through 1.0.4 from the links in the table. If a link is ever unavailable, email **music@nathanielschool.com** and Nathaniel Labs will send you the source, at no more than the cost of providing it, for at least three years after you received Prism.

## Your rights

You may replace, rebuild or study the GPL/LGPL components under the terms of their licences. Prism does not stop you from doing so: they are ordinary libraries and programs inside the app folder.

## Other services

Prism plays YouTube and Instagram links through those services' own players or, when GrabIt is installed, through GrabIt's engine. Those services have their own terms; you are responsible for having the right to play what you open.

_Prism 1.0.4 (build 9) · 6 October 2026_
