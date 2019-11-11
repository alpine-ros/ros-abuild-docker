from setuptools import setup

setup(
    name='ros-abuild',
    version='0.0.0',
    description='generate-rospkg-apkbuild',
    url='https://github.com/alpine-ros/generate-rospkg-apkbuild',
    author='Atsushi Watanabe',
    author_email='atsushi.w@ieee.org',
    packages=['generate_rospkg_apkbuild'],
    package_data={'generate_rospkg_apkbuild': "*.em"},
    install_requires=[
        'catkin_pkg',
        'empy',
        'pyyaml',
        'requests',
        'rosdep',
        'rosdistro',
        'wstool',
    ],
    entry_points={
        'console_scripts': [
            'generate-rospkg-apkbuild=generate_rospkg_apkbuild.genapkbuild:main',
            'generate-rospkg-apkbuild-multi=generate_rospkg_apkbuild.genapkbuild:main_multi'
        ]
    },
    license="BSD"
)
