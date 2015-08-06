# docker-android-automator
Run Android tests on emulators, using appium and robot framework, in a single command line.

Using the docker in docker script made by @jpettazo (https://github.com/jpetazzo/dind).

## Built with
- latest debian
- openjdk 7
- Using the following docker images:
 - softsam/adb
 - softsam/android-*
 - softsam/appium
 - softsam/robotframework-appium

## Prerequisites

This container MUST be run with the __--privileged__ option. This is needed since it will run other docker containers inside. It is also required to be able to access to physical devices plugged on USB ports.

You will also need to provide the apk of the application to test, and the tests to run (written with [robot framework](http://robotframework.org)).

We recommand the following file structure:

    /my_work_directory/automation
    /my_work_directory/automation/apk
    /my_work_directory/automation/apk/my_app_to_test.apk
    /my_work_directory/automation/robot # my robot framework tests

Output files will be written in the /my_work_directory/automation/output directory.

## The volumes

The image requires several volumes to be mounted in order to work.

### The tests volumes
This volume is mandatory.

The __/automation__ directory must contain the robot framework tests and the apk (see before).

### The docker volume
This volume is mandatory.

You must mount the __/var/lib/docker__ directory in __/var/lib/docker__, or the image will not work.

## Displaying the help

The container has a minimal help wich may guide you through the different options you can pass to the image.

Run the following command:

    docker run --privileged -v ~/automation:/automation -v /var/lib/docker:/var/lib/docker softsam/android-automator --help

## Running tests

In order to run tests, you will have to specify if you wish to run them on physical devices, or emulators (or both).

All the example assume your automation directory is in your home directory (e.g. /home/myuser/automation).

### Running the tests on physical devices

Run the following command:

    docker run --privileged -v ~/automation:/automation -v /var/lib/docker:/var/lib/docker -v /dev/bus/usb:/dev/bus/usb softsam/android-automator -d

The tests will run on all the connected devices.

Note that you must mount the __/dev/bus/usb__ directory so the docker container can access to your devices.

### Running the tests on emulators

Specify the sdks of the emulators you wish to run the tests on, and the image will automatically run them for you.


Run the following command to execute your tests on APIs 17 and 21:

    docker run --privileged -v ~/automation:/automation -v /var/lib/docker:/var/lib/docker softsam/android-automator -s 17,21

This will also generate a video of the test session in the output directory, along with the tests logs.

You can run tests on the following SDKs:
- 16
- 17
- 18
- 19
- 21
- 22

Note: you can run at the same time tests on the connected device and on emulators.

### Running the tests behind a proxy

Assuming your docker installation is properly configured, adding the http_proxy environment variable to the run docker command will to the job.

    docker run --privileged -v ~/automation:/root/automation -v /var/lib/docker:/var/lib/docker -e http_proxy=http://proxy:8080 softsam/android-automator -s 22

### Running tests in parallel

You may want to run tests in parallel to get a faster feedback. In order to achieve this, simply run the container several times, specifying a prefix (or else they will collide and no test will be run).

To run tests on SDKs 17 and 22 in parallel, run the following commands (in 2 shells):


    docker run --privileged -v ~/automation:/root/automation -v /var/lib/docker:/var/lib/docker -e http_proxy=http://proxy:8080 softsam/android-automator -s 17 -p sdk17


    docker run --privileged -v ~/automation:/root/automation -v /var/lib/docker:/var/lib/docker -e http_proxy=http://proxy:8080 softsam/android-automator -s 22 -p sdk22

## Visualizing the tests in real time on an emulator

When running tests on an emulator, a video is recorded, but you can still see the tests in live, via VNC. Run the docker container with the __-p 5900:5900__ option:
    docker run --privileged -p 5900:5900 -v ~/automation:/root/automation -v /var/lib/docker:/var/lib/docker softsam/android-automator -s 22


## Arguments passed to your robot framework tests

The robot framework tests are run using the pybot command. When run, the tests are given the following arguments (as variables):
- automator_android_api: the value of the SDK on which the test is run. You will need this since appium needs a different automation name depending on the SDK version (Selendroid if your API is lower than 17, Appium else).
- automator_locale: the locale of the device on which the tests runs.

## You want more?

If this image does not provide the level of control you seek, take a look at the images it uses, they may save you some time.
This image heavily relies on the following images:
- [softsam/adb](https://registry.hub.docker.com/u/softsam/adb/)
- [softsam/android](https://registry.hub.docker.com/u/softsam/android/)
- [softsam/android-22](https://registry.hub.docker.com/u/softsam/android-22/) (and all the other SDKs)
- [softsam/appium](https://registry.hub.docker.com/u/softsam/appium/)
- [softsam/robotframework-appium](https://registry.hub.docker.com/u/softsam/robotframework-appium/)

