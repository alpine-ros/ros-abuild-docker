from setuptools import setup, find_packages

setup(
    name='ros-abuild',
    version='0.0.0',
    description='generate-rospkg-apkbuild',
    url='https://github.com/alpine-ros/generate-rospkg-apkbuild',
    author='Atsushi Watanabe',
    author_email='atsushi.w@ieee.org',
    packages=find_packages(),
    install_requires=['catkin_pkg', 'requests', 'rosdep', 'rosdistro', 'pyyaml'],
    entry_points={
        'console_scripts': [
            'generate-rospkg-apkbuild=generate_rospkg_apkbuild.genapkbuild:main',
            'generate-rospkg-apkbuild-multi=generate_rospkg_apkbuild.genapkbuild:main_multi'
        ]
    },
    license="BSD"
)
