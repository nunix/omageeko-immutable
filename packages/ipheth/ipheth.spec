#
# spec file for package ipheth (omageeko-immutable)
#
# SLES 16.1 builds its kernel with "# CONFIG_USB_IPHETH is not set": the Apple iPhone USB
# Ethernet driver (iPhone Personal Hotspot over USB) is in neither kernel-default nor
# kernel-default-extra. This KMP builds that one driver out of tree from the same
# kernel-source SLES ships, so the code is exactly the kernel's own. weak-modules2 carries it
# across kernel updates with the same kABI; rebuild-on (kernel-default-devel) rebuilds it when
# the kernel changes. Unsigned: fine with Secure Boot off (the ThinkPad); with it on, the
# module would need a MOK-enrolled signing key.
#
Name:           ipheth
Version:        6.12
Release:        0%{?dist}
Summary:        Apple iPhone USB Ethernet driver (ipheth) for the SLES kernel
License:        GPL-2.0-only
URL:            https://www.kernel.org/
BuildRequires:  kernel-default-devel
BuildRequires:  kernel-source
BuildRequires:  modutils
BuildRequires:  suse-module-tools
BuildRequires:  libelf-devel

%description
The ipheth kernel module (USB tethering to an iPhone's Personal Hotspot), which the SLES 16.1
kernel doesn't build. Pairing needs usbmuxd and imobiledevice-tools (idevicepair).

%kernel_module_package -n %{name}

%prep
%setup -q -c -T
src=$(ls -d /usr/src/linux-[0-9]*/drivers/net/usb | grep -v -- -obj | sort -V | tail -n1)
test -f "$src/ipheth.c" || { echo "ipheth.c not in kernel-source ($src)"; exit 1; }
mkdir source obj
cp "$src/ipheth.c" source/
echo 'obj-m := ipheth.o' > source/Kbuild

%build
for flavor in %{flavors_to_build}; do
  rm -rf obj/$flavor
  cp -a source obj/$flavor
  make -C %{kernel_source $flavor} modules M=$PWD/obj/$flavor
done

%install
export INSTALL_MOD_PATH=%{buildroot}
export INSTALL_MOD_DIR=updates
for flavor in %{flavors_to_build}; do
  make -C %{kernel_source $flavor} modules_install M=$PWD/obj/$flavor
done

%changelog
