# Ghostty for omageeko's SLES target: built from the upstream release with the
# official Zig toolchain (SLES ships Zig 0.12; Ghostty 1.3 needs 0.15.2), fetched
# like packages/herdr does. Dependencies are fetched by zig (hash-verified) and
# linked statically, so the result only needs GTK 4 + libadwaita at runtime.
# sles/layers/03-omarchy unpacks it into ~/.local/opt/ghostty (never installed).
%global debug_package %{nil}
%global zigver 0.15.2

Name:           ghostty
Version:        1.3.1
Release:        1.omageeko%{?dist}
Summary:        Fast, native, feature-rich terminal emulator
License:        MIT
URL:            https://ghostty.org
Source0:        https://release.files.ghostty.org/%{version}/ghostty-%{version}.tar.gz
Source1:        https://ziglang.org/download/%{zigver}/zig-x86_64-linux-%{zigver}.tar.xz
ExclusiveArch:  x86_64
BuildRequires:  xz
BuildRequires:  gettext-tools
BuildRequires:  pkgconfig
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(libadwaita-1)
BuildRequires:  pkgconfig(gtk4-layer-shell-0)
BuildRequires:  pkgconfig(x11)
# tic compiles the xterm-ghostty terminfo (SLES ships it in ncurses-devel)
BuildRequires:  ncurses-devel

%description
Ghostty is a fast, feature-rich, cross-platform terminal emulator that uses
platform-native UI and GPU acceleration.

%prep
%setup -q
tar -xf %{SOURCE1} -C ..

%build
export ZIG_GLOBAL_CACHE_DIR="$PWD/../zig-cache"
../zig-x86_64-linux-%{zigver}/zig build \
  --prefix %{_prefix} -Doptimize=ReleaseFast -Dcpu=baseline -Dpie=true \
  -Demit-docs=false -Dversion-string=%{version}

%install
export ZIG_GLOBAL_CACHE_DIR="$PWD/../zig-cache"
DESTDIR=%{buildroot} ../zig-x86_64-linux-%{zigver}/zig build \
  --prefix %{_prefix} -Doptimize=ReleaseFast -Dcpu=baseline -Dpie=true \
  -Demit-docs=false -Dversion-string=%{version}

%files
%license LICENSE
# Never installed (unpacked into userland), so it can own the whole payload
%{_prefix}/*
