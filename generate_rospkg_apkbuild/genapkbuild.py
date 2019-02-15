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
import argparse
import os
import subprocess
import sys
import yaml

from catkin_pkg.package import parse_package_string
import rosdep2
from rosdistro import get_cached_distribution, get_index, get_index_url
from rosdistro.manifest_provider import get_release_tag
from rosinstall_generator.generator import generate_rosinstall, get_wet_distro


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
        try:
            rule_installer, rule = d.get_rule_for_platform(os_name, os_version, installer_keys, default_key)
        except rosdep2.lookup.ResolutionError as e:
            # ignoring ROS packages since Alpine ROS packages are not solvable at now
            if e.rosdep_data['_is_ros']:
                keys.append(ros_pkgname_to_pkgname(ros_distro, rosdep_name))
                continue
            not_provided.append(rosdep_name)
            continue
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


def git_date(target_dir='./'):
    try:
        d = subprocess.check_output([
            'git', '-C', target_dir, 'show',
            '-s', '--format=%ad', '--date=format:%Y%m%d%H%M%S', 'HEAD'])
        return d.decode('ascii').replace('\r', '').replace('\n', '')
    except subprocess.CalledProcessError as e:
        return None


def package_to_apkbuild(ros_distro, package_name,
                        check=True, upstream=False, src=False, rev=0,
                        ver_suffix='', commit_hash=None):
    ret = []
    pkg_xml = ''
    if package_name.startswith('http://') or package_name.startswith('https://'):
        import requests

        res = requests.get(package_name)
        pkg_xml = res.text
    elif package_name.endswith('.xml'):
        with open(package_name, 'r') as f:
            pkg_xml = f.read()
    else:
        distro = get_wet_distro(ros_distro)
        pkg_xml = distro.get_release_package_xml(package_name)
    pkg = parse_package_string(pkg_xml)

    install_space = ''.join(['/usr/ros/', ros_distro])
    install_space_fakeroot = ''.join(['"$pkgdir"', '/usr/ros/', ros_distro])

    # generate rosinstall
    rosinstall = None
    if not src:
        rosinstall = generate_rosinstall(
            ros_distro, [pkg.name], flat=True, tar=False,
            upstream_source_version=(True if upstream else False))
        if upstream:
            if commit_hash is not None:
                rosinstall[0]['git']['version'] = commit_hash
            if ver_suffix == '':
                import tempfile
                with tempfile.TemporaryDirectory() as tmpd:
                    f = open(tmpd + '/.rosinstall', 'w')
                    f.write(yaml.dump(rosinstall))
                    f.close()
                    subprocess.check_output(['wstool', 'update', '-t', tmpd])
                    date = git_date(
                        '/'.join([tmpd, rosinstall[0]['git']['local-name']]))
                    if date is not None:
                        ver_suffix = '_git' + date
    elif ver_suffix == '':
        date = git_date()
        if date is not None:
            ver_suffix = '_git' + date

    ret.append(''.join(['pkgname=', ros_pkgname_to_pkgname(ros_distro, pkg.name)]))
    ret.append(''.join(['_pkgname=', pkg.name]))
    ret.append(''.join(['pkgver=', pkg.version, ver_suffix]))
    ret.append(''.join(['pkgrel=', str(rev)]))
    ret.append(''.join(['pkgdesc=', '"$_pkgname package for ROS ', ros_distro, '"']))
    if len(pkg.urls) > 0:
        ret.append(''.join(['url=', '"', pkg.urls[0].url, '"']))
    else:
        ret.append(''.join(['url=', '"http://wiki.ros.org/$_pkgname"']))
    ret.append(''.join(['arch=', '"all"']))
    ret.append(''.join(['license=', '"', pkg.licenses[0], '"']))
    if not check:
        ret.append(''.join(['options=', '"!check"']))

    depends = []
    for dep in pkg.exec_depends:
        depends.append(dep.name)
    depends_keys = resolve(ros_distro, depends)

    depends_export = []
    for dep in pkg.buildtool_export_depends:
        depends_export.append(dep.name)
    for dep in pkg.build_export_depends:
        depends_export.append(dep.name)
    depends_export_keys = resolve(ros_distro, depends_export)

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

    if depends_keys is None or depends_export_keys is None or makedepends_keys is None:
        sys.exit(1)

    makedepends_implicit = [
        'py-setuptools', 'py-rosdep', 'py-rosinstall',
        'py-rosinstall-generator', 'py-wstool', 'chrpath']

    ret.append(''.join(['depends=', '"',
                        ' '.join(depends_keys), ' ',
                        ' '.join(depends_export_keys),
                        '"']))
    ret.append(''.join(['makedepends="', ' '.join(makedepends_implicit + makedepends_keys), '"']))
    ret.append('subpackages=""')
    ret.append('source=""')
    ret.append('builddir="$startdir/apk-build-temporary"')
    ret.append('srcdir="/tmp/dummy-src-dir"')
    ret.append('buildlog="$builddir/ros-abuild-build.log"')
    ret.append('checklog="$builddir/ros-abuild-check.log"')
    ret.append('statuslog="$builddir/ros-abuild-status.log"')
    ret.append('if [ x${GENERATE_BUILD_LOGS} != "xyes" ]; then')
    ret.append('  buildlog="/dev/null"')
    ret.append('  checklog="/dev/null"')
    ret.append('  statuslog="/dev/null"')
    ret.append('fi')

    if not src:
        ret.append(''.join(['rosinstall="', yaml.dump(rosinstall), '"']))

    ret.append('prepare() {')
    ret.append('  set -o pipefail')
    ret.append('  mkdir -p $builddir')
    ret.append('  echo "preparing" > $statuslog')
    ret.append('  cd "$builddir"')
    ret.append('  rm -rf src || true')
    ret.append('  mkdir -p src')
    if src:
        ret.append('  cp -r $startdir src/$_pkgname || true  # ignore recursion error')
    else:
        ret.append('  echo "$rosinstall" > pkg.rosinstall')
        if upstream and commit_hash is not None:
            ret.append('  wstool init src pkg.rosinstall')
        else:
            ret.append('  wstool init --shallow src pkg.rosinstall')

        if upstream:
            ret.append('  find src -name package.xml | while read manifest; do')
            ret.append('    dir=`dirname $manifest`')
            ret.append('    pkg=`sed $manifest \\')
            ret.append('         -e \':l1;N;$!b l1;s/.*<\s*name\s*>\s*\(.*\)\s*<\s*\/name\s*>.*/\\1/;\'`')
            ret.append('    if [ $pkg != $_pkgname ]; then')
            ret.append('      echo Ignoring $pkg which is not $_pkgname')
            ret.append('      touch $dir/CATKIN_IGNORE')
            ret.append('    fi')
            ret.append('  done')
    ret.append('  find $startdir -name "*.patch" | while read patchfile; do')
    ret.append('    echo "Applying $patchfile"')
    ret.append('    (cd src/* && patch -p1 -i $patchfile)')
    ret.append('  done')
    ret.append('}')

    ret.append('build() {')
    ret.append('  set -o pipefail')
    ret.append('  echo "building" > $statuslog')
    ret.append('  cd "$builddir"')
    if catkin:
        ret.append(''.join(['  source /usr/ros/', ros_distro, '/setup.sh']))
        ret.append('  catkin_make_isolated -DCMAKE_BUILD_TYPE=Release 2>&1 | tee $buildlog')
    if cmake:
        ret.append('  mkdir src/$_pkgname/build')
        ret.append('  cd src/$_pkgname/build')
        ret.append(''.join([
            '  cmake .. -DCMAKE_INSTALL_PREFIX=', install_space,
            ' -DCMAKE_INSTALL_LIBDIR=lib 2>&1 | tee $buildlog']))
        ret.append('  make 2>&1 | tee -a $buildlog')
    ret.append('}')

    if check:
        ret.append('check() {')
        ret.append('  if [ -f $startdir/NOCHECK ]; then')
        ret.append('    echo "Check skipped" | tee $checklog')
        ret.append('    return 0')
        ret.append('  fi')
        ret.append('  set -o pipefail')
        ret.append('  echo "checking" >> $statuslog')
        ret.append('  cd "$builddir"')
        if catkin:
            ret.append(''.join(['  source /usr/ros/', ros_distro, '/setup.sh']))
            ret.append('  source devel_isolated/setup.sh')
            ret.append('  catkin_make_isolated -DCMAKE_BUILD_TYPE=Release \\')
            ret.append('    --catkin-make-args run_tests 2>&1 | tee $checklog')
            ret.append('  catkin_test_results 2>&1 | tee $checklog')
        if cmake:
            ret.append('  cd src/$_pkgname/build')
            ret.append('  if [ `make -q test > /dev/null 2> /dev/null; echo $?` -eq 1 ]; then')
            ret.append('    make test 2>&1 | tee $checklog')
            ret.append('  fi')
        ret.append('}')

    ret.append('package() {')
    ret.append('  echo "packaging" >> $statuslog')
    ret.append('  mkdir -p "$pkgdir"')
    ret.append('  cd "$builddir"')
    ret.append('  export DESTDIR="$pkgdir"')
    if catkin:
        ret.append(''.join(['  source /usr/ros/', ros_distro, '/setup.sh']))
        ret.append(' '.join([
            '  catkin_make_isolated -DCMAKE_BUILD_TYPE=Release --install-space', install_space]))
        ret.append(' '.join([
            '  catkin_make_isolated -DCMAKE_BUILD_TYPE=Release --install --install-space', install_space]))
        ret.append(''.join([
            '  rm ',
            install_space_fakeroot, '/setup.* ',
            install_space_fakeroot, '/.rosinstall ',
            install_space_fakeroot, '/_setup_util.py ',
            install_space_fakeroot, '/env.sh ',
            install_space_fakeroot, '/.catkin']))
    if cmake:
        ret.append('  cd src/$_pkgname/build')
        ret.append('  make install')

    ret.append('  find $pkgdir -name "*.so" | while read so; do')
    ret.append('    chrpath_out=$(chrpath ${so} || true)')
    ret.append('    if echo ${chrpath_out} | grep -q "RPATH="; then')
    ret.append('      rpath=$(echo -n "${chrpath_out}" | sed -e "s/^.*RPATH=//")')
    ret.append('      if echo "${rpath}" | grep -q home; then')
    ret.append('        echo "RPATH contains home!: ${rpath}"')
    ret.append('        rpathfix=$(echo -n "${rpath}" | tr ":" "\\n" \\')
    ret.append('          | grep -v -e home | tr "\\n" ":" | sed -e "s/:$//; s/::/:/;")')
    ret.append('        echo "Fixing to ${rpathfix}"')
    ret.append('        chrpath -r ${rpathfix} ${so} || (echo chrpath failed; false)')
    ret.append('      fi')
    ret.append('    fi')
    ret.append('  done')

    ret.append('  echo "finished" >> $statuslog')
    ret.append('}')

    return '\n'.join(ret)


def main():
    parser = argparse.ArgumentParser(description='Generate APKBUILD of ROS package')
    parser.add_argument('ros_distro', metavar='ROS_DISTRO', nargs=1,
                        help='name of the ROS distribution')
    parser.add_argument('package', metavar='PACKAGE', nargs=1,
                        help='package name or URL/file path to package.xml')
    parser.add_argument('--nocheck', dest='check', action='store_const',
                        const=False, default=True,
                        help='disable test (default: test enabled)')
    parser.add_argument('--rev', dest='rev', type=int, default=0,
                        help='set revision number (default: 0)')
    parser.add_argument('--ver-suffix', dest='vsuffix', type=str, default='',
                        help='set version suffix (default: \'\') ' +
                        '[note: if not specified and --upstream is set, ' +
                        'automatic detection by cloning the repo will be performed.]')
    parser.add_argument('--commit-hash', dest='commit', type=str, default=None,
                        help='set commit hash of upstream (default: None)')
    parser.add_argument('--src', dest='src', action='store_const',
                        const=True, default=False,
                        help='build from source (default: disabled)')
    parser.add_argument('--upstream', action='store_const',
                        const=True, default=False,
                        help='use upstream repository (default: False)')
    args = parser.parse_args()

    print(package_to_apkbuild(args.ros_distro[0], args.package[0],
                              check=args.check, upstream=args.upstream,
                              src=args.src, rev=args.rev,
                              ver_suffix=args.vsuffix,
                              commit_hash=args.commit))


def main_multi():
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description='''Generate multiple APKBUILDs of ROS packages

This command reads a list of package names and output paths.
example:
  roscpp ros/kinetic/roscpp/APKBUILD
  rospy ros/kinetic/rospy/APKBUILD''')
    parser.add_argument('ros_distro', metavar='ROS_DISTRO', nargs=1,
                        help='name of the ROS distribution')
    parser.add_argument('--rev', dest='rev', type=int, default=0,
                        help='set revision number (default: 0)')
    parser.add_argument('--upstream', action='store_const',
                        const=True, default=False,
                        help='use upstream repository (default: False)')
    args = parser.parse_args()

    for line in sys.stdin:
        [pkgname, filepath] = line.split()
        if pkgname == '':
            continue

        apkbuild = package_to_apkbuild(
            args.ros_distro[0], pkgname, upstream=args.upstream, rev=args.rev)

        directory = os.path.dirname(filepath)
        if not os.path.exists(directory):
            os.makedirs(directory)

        with open(filepath, 'w') as f:
            f.write(apkbuild)


if __name__ == '__main__':
    main()
