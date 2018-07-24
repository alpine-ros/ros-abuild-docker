#!/usr/bin/env python
# Copyright (c) 2018, SEQSENSE, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the Willow Garage, Inc. nor the names of its
#       contributors may be used to endorse or promote products derived from
#       this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

from __future__ import print_function
import sys

from urllib2 import urlopen

from catkin_pkg.package import parse_package_string
import rosdep2

def ros_pkgname_to_pkgname(ros_distro, pkgname):
    return '-'.join(['ros', ros_distro, pkgname.replace('_', '-')])

def load_lookup():
    sources_loader = rosdep2.sources_list.SourcesListLoader.create_default(
        sources_cache_dir=rosdep2.sources_list.get_sources_cache_dir())
    lookup = rosdep2.RosdepLookup.create_from_rospkg(sources_loader=sources_loader)

    return lookup

def resolve(ros_distro, names):
    lookup = load_lookup()
    installer_context = rosdep2.create_default_installer_context()
    os_name, os_version = installer_context.get_os_name_and_version()                         
    installer_keys = installer_context.get_os_installer_keys(os_name)                         
    default_key = installer_context.get_default_os_installer_key(os_name)                     

    keys = []
    not_provided = []
    for rosdep_name in names:
        view = lookup.get_rosdep_view(rosdep2.rospkg_loader.DEFAULT_VIEW_KEY)
        try:
            d = view.lookup(rosdep_name)
        except KeyError as e:
            keys.append(ros_pkgname_to_pkgname(ros_distro, rosdep_name))
            continue
        rule_installer, rule = d.get_rule_for_platform(os_name, os_version, installer_keys, default_key)
        if type(rule) == dict:
            not_provided.append(rosdep_name)
        installer = installer_context.get_installer(rule_installer)
        resolved = installer.resolve(rule)
        for r in resolved:
            keys.append(r)
    if len(not_provided) > 0:
        print('Some package is not provided by native installer: ' + ' '.join(not_provided), file=sys.stderr)
        return None
    return keys

def package_to_apkbuild(ros_distro, uri):
    ret = []
    response = urlopen(uri)
    pkg_xml = response.read()
    pkg = parse_package_string(pkg_xml)
    install_space = '/'.join(['/usr/lib/ros', ros_distro])

    ret.append(''.join(['pkgname=', ros_pkgname_to_pkgname(ros_distro, pkg.name)]))
    ret.append(''.join(['pkgver=', pkg.version]))
    ret.append(''.join(['pkgrel=', '1']))
    ret.append(''.join(['pkgdesc=', '"', pkg.description, '"']))
    ret.append(''.join(['url=', '"', pkg.urls[0].url, '"']))
    ret.append(''.join(['arch=', '"all"']))
    ret.append(''.join(['license=', '"', pkg.licenses[0], '"']))
    depends = []
    for dep in pkg.exec_depends:
        depends.append(dep.name)
    for dep in pkg.buildtool_export_depends:
        depends.append(dep.name)
    for dep in pkg.build_export_depends:
        depends.append(dep.name)
    depends_keys = resolve(ros_distro, depends)
    if depends_keys == None:
        sys.exit(1)
    ret.append(''.join(['depends=', '"', ' '.join(depends_keys), '"']))
    makedepends = []
    catkin = False
    cmake = False
    for dep in pkg.buildtool_depends:
        makedepends.append(dep.name)
        if dep.name == 'catkin':
            catkin = True
        elif dep.name == 'cmake':
            cmake = True
    if (catkin and cmake) or ((not catkin) and (not cmake)):
        print('Un-supported buildtool ' + ' '.join(makedepends), file=sys.stderr)
        sys.exit(1)

    for dep in pkg.build_depends:
        makedepends.append(dep.name)
    for dep in pkg.test_depends:
        makedepends.append(dep.name)
    makedepends_keys = resolve(ros_distro, makedepends)
    if makedepends_keys == None:
        sys.exit(1)
    ret.append(''.join(['makedepends=', '"', ' '.join(makedepends_keys), '"']))
    ret.append(''.join(['subpackages=', '"$pkgname-dev"']))
    ret.append(''.join(['source=', '""']))
    ret.append(''.join(['builddir=', '"$srcdir"']))

    ret.append('build() {')
    ret.append('  cd "$builddir"')
    ret.append('  mkdir -p src')
    ret.append(' '.join([
        '  rosinstall_generator', '--rosdistro', ros_distro, '--tar', pkg.name,
        '>', 'pkg.rosinstall']))
    ret.append('  wstool init src pkg.rosinstall')
    if catkin:
        ret.append(' '.join([
            '  catkin_make_isolated --install-space', install_space]))
    if cmake:
        ret.append(''.join(['  mkdir src/', pkg.name, '/build']))
        ret.append(''.join(['  cd src/', pkg.name, '/build']))
        ret.append(' '.join([
            '  cmake .. -DCMAKE_INSTALL_PREFIX=', install_space]))
        ret.append('  make')
    ret.append('}')

    ret.append('check() {')
    ret.append('  cd "$builddir"')
    if catkin:
        ret.append(' '.join([
            '  catkin_make_isolated --install-space', install_space, '--cmake-args run_tests']))
        ret.append('  catkin_test_results')
    if cmake:
        ret.append(''.join(['  cd src/', pkg.name, '/build']))
        ret.append('  make test')
    ret.append('}')

    ret.append('package() {')
    ret.append('  cd "$builddir"')
    if catkin:
        ret.append(' '.join([
            '  catkin_make_isolated --install --install-space', install_space]))
    if cmake:
        ret.append(''.join(['  cd src/', pkg.name, '/build']))
        ret.append('  make install')
    ret.append('}')

    return '\n'.join(ret)

if __name__ == '__main__':
    argv = sys.argv
    if len(argv) < 3:
        sys.stderr.write(
            ''.join(['usage: ', argv[0], ' ROS_DISTRO MANIFEST_URI', '\n']))
        sys.exit(1)
    print(package_to_apkbuild(argv[1], argv[2]))
