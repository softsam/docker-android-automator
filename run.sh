#!/bin/bash

# Automation directory
AUTOMATION_DIR=~/automation
PYBOT_ARGS="--variable locale:fr"
ANDROID_API=19

# Directory containing the apk to install
APK_DIR=${AUTOMATION_DIR}/apk
# Directory containing the robot framework tests
ROBOT_DIR=${AUTOMATION_DIR}/robot
# Directory containing the VNC recorded videos
VNC_DIR=${AUTOMATION_DIR}/vnc


# Shell colors
RED="\033[31m"
GREEN="\033[32m"
NO_COLOR="\033[0m"

# Check directories are created
check_directory_structure()
{
    if [ ! -d $APK_DIR ]
    then
        echo "${RED}The directory $APK_DIR does not exist. Create it and put the apk to test in it.${NO_COLOR}"
        exit 1
    fi

    if [ ! -d $ROBOT_DIR ]
    then
        echo "${RED}The directory $ROBOT_DIR does not exist. Create it and put the robot framework test code in it.${NO_COLOR}"
        exit 2
    fi

    if [ ! -d $VNC_DIR ]
    then
        mkdir $VNC_DIR
    fi
}

log_info()
{
    echo -e "${GREEN}${1}${NO_COLOR}"
}

log_error()
{
    echo -e "${RED}${1}${NO_COLOR}"
}

# Cleanup dockers
cleanup()
{
    log_info "Removing previous containers"
    docker rm -f android 2> /dev/null 
    docker rm -f appium 2> /dev/null
    docker rm -f robot 2> /dev/null
    docker rm -f vncrecorder 2> /dev/null
}

# Run emulator
run_emulator()
{
    log_info "Starting emulator"
    docker run -d -p 5555:5555 -p 5900:5900 --name android softsam/android-${ANDROID_API}
}

# Run appium server
run_appium_server()
{
    log_info "Starting appium server"
    docker run -d --link android:appium2android -p 4723:4723 --name appium -e APPIUM_ARGS="--suppress-adb-kill-server" -v ${APK_DIR}:/apk softsam/appium
}

# Run appium server on real device
run_appium_server_on_physical_device()
{
    log_info "Starting appium server"
    docker run -d --privileged -v /dev/bus/usb:/dev/bus/usb -p 4723:4723 --name appium -e APPIUM_ARGS="-U $1" -v ${APK_DIR}:/apk softsam/appium
}

# Wait for the emulator boot sequence to be over
wait_for_emulator()
{
    local bootanim=""
    until [[ "$bootanim" =~ "stopped" ]]; do
       bootanim=`docker exec appium adb -e shell getprop init.svc.bootanim 2>&1`
       echo "Waiting for emulator to start...$bootanim"
       sleep 1
    done
}

# Wait for a specific device boot sequence to be over
# Param: the id of the device to check
wait_for_device()
{
    local bootanim=""
    until [[ "$bootanim" =~ "stopped" ]]; do
       bootanim=`docker exec appium adb -s $1 shell getprop init.svc.bootanim 2>&1`
       echo "Waiting for device to start...$bootanim"
       sleep 1
    done
}

# Connect appium & emulator
connect_appium_to_emulator()
{
    log_info "Connect appium to emulator"
    docker exec -i -t appium adb connect android:5555
}

# Run robot framework tests
run_tests()
{
    local android_api=$1
    log_info "Running robot framework tests for android api $android_api"
    docker run --rm --link appium:robot2appium --name robot -v ${ROBOT_DIR}:/robot softsam/robotframework-appium $PYBOT_ARGS --variable android_api:$android_api .
}

run_tests_on_all_physical_devices()
{
    local devices=$(list_devices)
    for device in $devices
    do
        local sdk_version=$(get_device_sdk $device)
        log_info "Running test on device $device with sdk $sdk_version"
        # Release connection to device
        run_appium_server_on_physical_device $device
        log_info "Wait for appium server to be ready"
        sleep 10
        #wait_for_device $device
        run_tests $sdk_version
        # remove appium server
        docker rm -f appium
    done
}

# List all connected physical devices
list_devices()
{
    adb start-server &> /dev/null
    local devices=`adb devices | awk 'NR>1 {print $1}'`
    adb kill-server &> /dev/null
    echo $devices
}

# Get the sdk version of the given device
get_device_sdk()
{
    adb start-server &> /dev/null
    local sdk_version=`adb -s $1 shell getprop ro.build.version.sdk`
    adb kill-server &> /dev/null
    echo $sdk_version
}

run_tests_on_emulator()
{
    run_emulator
    run_appium_server
    log_info "Wait for appium server to be ready"
    sleep 10
    connect_appium_to_emulator
    wait_for_emulator
    start_recording
    run_tests $ANDROID_API
    stop_recording
}

start_recording()
{
    log_info "Starting video recording"
    docker run -d --link android:vncrecorder2android --name vncrecorder -v ${VNC_DIR}:/vnc softsam/vncrecorder -o /vnc/record.flv android
}

stop_recording()
{
    log_info "Stopping video recording"
    docker kill -s INT vncrecorder
}

# Main program
check_directory_structure
cleanup
run_tests_on_all_physical_devices
run_tests_on_emulator
cleanup

