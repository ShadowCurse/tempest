{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  LIBC_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.glibc]}";
  SDL3_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.sdl3]}";
  VULKAN_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.vulkan-headers]}";
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [pkgs.glibc pkgs.sdl3 pkgs.libclang pkgs.vulkan-loader]}";
  VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";

  buildInputs = with pkgs; [
    renderdoc
    spirv-cross
    shaderc
    pkg-config
    sdl3
    libclang
  ];
}
