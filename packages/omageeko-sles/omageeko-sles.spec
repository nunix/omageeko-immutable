# omageeko-sles: the only system files the SLES Immutable target needs.
# Omarchy itself lives in ~/.local/share/omarchy (sles layer 03, option B); a
# display manager and PAM can only read system paths, so these two stay here.
# Built by sles/layers/03-omarchy in the SLES builder; installed transactionally.

Name:           omageeko-sles
Version:        1
Release:        1.omageeko%{?dist}
Summary:        System hooks for the userland Omarchy desktop on SLES Immutable
License:        MIT
URL:            https://github.com/omacom/omarchy
Source0:        omarchy.desktop
Source1:        omarchy-lock-password
# sddm/: upstream's SDDM theme + greeter config, vendored (see sddm/README)
BuildArch:      noarch
Requires:       uwsm
Requires:       hyprland
Requires:       quickshell
Requires:       pam

%description
The "Omarchy (Hyprland uwsm)" Wayland session for the display manager and the
PAM stack the Quickshell lock screen authenticates against
(/etc/pam.d/omarchy-lock-password, upstream's file with SUSE's common-account).
Everything else of Omarchy is installed per user under ~/.local/share/omarchy.

%package sddm
Summary:        Omarchy's SDDM login: Wayland greeter in Hyprland, Omarchy theme
Requires:       sddm-qt6
Requires:       hyprland
# Main.qml uses JetBrainsMono Nerd Font; the greeter (sddm user) can't see the userland copy
Requires:       jetbrains-mono-nerd-fonts

%description sddm
Upstream Omarchy's SDDM setup for SLES: /etc/sddm.conf.d/10-omarchy.conf (Wayland greeter
started by start-hyprland with /usr/share/sddm/hyprland.lua) and the "omarchy" theme.
Installed by sles/layers/03-omarchy when SDDM is the display manager.

%prep

%build

%install
install -Dm644 %{SOURCE0} %{buildroot}%{_datadir}/wayland-sessions/omarchy.desktop
install -Dm644 %{SOURCE1} %{buildroot}%{_sysconfdir}/pam.d/omarchy-lock-password
install -Dm644 %{_sourcedir}/sddm/10-omarchy.conf %{buildroot}%{_sysconfdir}/sddm.conf.d/10-omarchy.conf
install -Dm644 %{_sourcedir}/sddm/hyprland.lua %{buildroot}%{_datadir}/sddm/hyprland.lua
install -d %{buildroot}%{_datadir}/sddm/themes/omarchy
install -m644 %{_sourcedir}/sddm/omarchy/* %{buildroot}%{_datadir}/sddm/themes/omarchy/

%files
%{_datadir}/wayland-sessions/omarchy.desktop
%config(noreplace) %{_sysconfdir}/pam.d/omarchy-lock-password

%files sddm
%config(noreplace) %{_sysconfdir}/sddm.conf.d/10-omarchy.conf
%{_datadir}/sddm/hyprland.lua
%{_datadir}/sddm/themes/omarchy
