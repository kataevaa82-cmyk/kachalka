#!/usr/bin/env bash
# Custom Godot 4.7.1 web release template with everything this game never
# touches compiled out. The stock wasm is 37.7 MiB and is ~98% of the download;
# the project side is 0.7 MiB, so this is the only real lever. See README.md.
set -euo pipefail
godot_src="${GODOT_SRC:-$(pwd)}"
source "${EMSDK_ENV:?set EMSDK_ENV to emsdk/emsdk_env.sh}" >/dev/null
cd "$godot_src"

# Unused at runtime, verified by grepping the shipped scripts: no RegEx, no
# networking, no ogg/mp3/video (all audio is synthesised WAV), no navigation,
# no CSG/GridMap, no XR. The image and VRAM codecs run at import time in the
# editor, never in the exported build.
scons platform=web target=template_release threads=no production=yes \
  optimize=size deprecated=no \
  module_bmp_enabled=no module_dds_enabled=no module_hdr_enabled=no \
  module_jpg_enabled=no module_ktx_enabled=no module_tga_enabled=no \
  module_tinyexr_enabled=no module_bcdec_enabled=no module_betsy_enabled=no \
  module_astcenc_enabled=no module_cvtt_enabled=no module_etcpak_enabled=no \
  module_basis_universal_enabled=no \
  module_ogg_enabled=no module_vorbis_enabled=no module_mp3_enabled=no \
  module_theora_enabled=no module_interactive_music_enabled=no \
  module_enet_enabled=no module_multiplayer_enabled=no module_webrtc_enabled=no \
  module_websocket_enabled=no module_upnp_enabled=no module_jsonrpc_enabled=no \
  module_openxr_enabled=no module_webxr_enabled=no module_mobile_vr_enabled=no \
  module_csg_enabled=no module_gridmap_enabled=no \
  module_navigation_2d_enabled=no module_navigation_3d_enabled=no \
  module_vhacd_enabled=no module_raycast_enabled=no \
  module_lightmapper_rd_enabled=no module_xatlas_unwrap_enabled=no \
  module_meshoptimizer_enabled=no module_noise_enabled=no \
  module_camera_enabled=no module_visual_shader_enabled=no \
  module_msdfgen_enabled=no \
  module_zip_enabled=no module_regex_enabled=no module_fbx_enabled=no \
  module_glslang_enabled=no module_gltf_enabled=no module_objectdb_profiler_enabled=no \
  -j4
echo "BUILD_OK"
ls -l bin/
