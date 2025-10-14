Summary: RPM installer/updater
Name: yum
Version: 1.0.3
Release: 1_73
License: GPL
Group: System Environment/Base
Source: %{name}-%{version}.tar.gz
URL: http://www.dulug.duke.edu/yum/
BuildRoot: %{_tmppath}/%{name}-%{version}root
BuildArchitectures: noarch
BuildRequires: rpm-python python >= 1.5.2
Requires: rpm-python >= 4.0.4 python >= 1.5.2  rpm >= 4.0.4
Prereq: /sbin/chkconfig, /sbin/service

%description
Yum is a utility that can check for and automatically download and
install updated RPM packages. Dependencies are obtained and downloaded 
automatically prompting the user as necessary.

%prep
%setup -q

%build
%configure 
make


%install
[ "$RPM_BUILD_ROOT" != "/" ] && rm -rf $RPM_BUILD_ROOT
make DESTDIR=$RPM_BUILD_ROOT install



%clean
[ "$RPM_BUILD_ROOT" != "/" ] && rm -rf $RPM_BUILD_ROOT


%post
/sbin/chkconfig --add yum
#/sbin/chkconfig yum on
/sbin/service yum condrestart >> /dev/null
exit 0


%preun
if [ $1 = 0 ]; then
 /sbin/chkconfig --del yum
 /sbin/service yum stop >> /dev/null
fi
exit 0




%files 
%defattr(-, root, root)
%doc README AUTHORS COPYING TODO INSTALL
%config(noreplace) %{_sysconfdir}/yum.conf
%config %{_sysconfdir}/cron.daily/yum.cron
%config %{_sysconfdir}/init.d/%{name}
%config %{_sysconfdir}/logrotate.d/%{name}
%{_datadir}/yum/*
%{_bindir}/yum
%{_bindir}/yum-arch
/var/cache/yum
%{_mandir}/man*/*

%changelog
* Mon Sep  8 2003 Seth Vidal <skvidal@phy.duke.edu>
- brown paper-bag 1.0.3

* Mon Sep  8 2003 Seth Vidal <skvidal@phy.duke.edu>
- ver to 1.0.2

* Mon May 19 2003 Seth Vidal <skvidal@phy.duke.edu>
- ver to 1.0.1

* Mon Apr 28 2003 Seth Vidal <skvidal@phy.duke.edu>
- fix up for changes and fhs compliance

* Tue Mar 11 2003 Seth Vidal <skvidal@phy.duke.edu>
- bump ver to 1.0
- fix conf file
- for rhl 7.3

* Sun Dec 22 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped to ver 0.9.4
- split spec file for rhl 7x vs 8

* Sun Oct 20 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped ver to 0.9.3

* Mon Aug 26 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped ver to 0.9.2

* Thu Jul 11 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped ver to 0.9.1

* Thu Jul 11 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped ver  to 0.9.0

* Thu Jul 11 2002 Seth Vidal <skvidal@phy.duke.edu>
- added rpm require

* Sun Jun 30 2002 Seth Vidal <skvidal@phy.duke.edu>
- 0.8.9

* Fri Jun 14 2002 Seth Vidal <skvidal@phy.duke.edu>
- 0.8.7

* Thu Jun 13 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped to 0.8.5

* Thu Jun 13 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped to 0.8.4

* Sun Jun  9 2002 Seth Vidal <skvidal@phy.duke.edu>
- bumped to 0.8.2
* Thu Jun  6 2002 Seth Vidal <skvidal@phy.duke.edu>
- First packaging
