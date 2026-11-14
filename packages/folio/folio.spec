# Port of omarchy-pkgs/pkgbuilds/folio (Files, Omarchy's file manager since
# quattro edge 795dfb2 "Replace Nautilus with Files"). Builds on Tumbleweed and
# on SLES 16.1 (sles layer 02).

Name:           folio
Version:        0.4.0
Release:        1.omageeko%{?dist}
Summary:        Files: Omarchy's file manager, quiet, keyboard-first and following the theme
License:        MIT
URL:            https://github.com/omacom/folio
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz#/%{name}-%{version}.tar.gz
BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6Qml)
BuildRequires:  cmake(Qt6Quick)
BuildRequires:  cmake(Qt6QuickControls2)
BuildRequires:  cmake(Qt6DBus)
BuildRequires:  cmake(Qt6Concurrent)
BuildRequires:  cmake(Qt6Test)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(gio-unix-2.0)
BuildRequires:  pkgconfig(zlib)
# QML modules are loaded at runtime (QtQuick.*, Controls.Material, QtMultimedia)
Requires:       qt6-declarative-imports
Requires:       qt6-multimedia-imports
Requires:       qt6-imageformats
Requires:       qt6-wayland
Requires:       hicolor-icon-theme
Requires:       xdg-utils
# PKGBUILD optdepends
Recommends:     qt6-pdf-imports
Recommends:     ffmpegthumbnailer
Suggests:       xdg-terminal-exec

%description
Files (folio) is Omarchy's file manager: quiet, keyboard-first, following the
Omarchy theme, with bundled Tailscale, Dropbox and LocalSend plugins.

%prep
%autosetup -n %{name}-%{version}

%build
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build folio

%install
install -Dm755 build/folio %{buildroot}%{_bindir}/folio
install -Dm644 share/folio.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/folio.svg
install -Dm644 share/folio.desktop %{buildroot}%{_datadir}/applications/folio.desktop
# Bundled plugins (Tailscale, Dropbox, LocalSend), executables kept executable
find plugins -type f | while read -r file; do
  mode=644
  [ -x "$file" ] && mode=755
  install -Dm$mode "$file" "%{buildroot}%{_datadir}/folio/$file"
done

%files
%license LICENSE
%doc README.md docs/plugins.md
%{_bindir}/folio
%{_datadir}/applications/folio.desktop
%{_datadir}/icons/hicolor/scalable/apps/folio.svg
%{_datadir}/folio/
