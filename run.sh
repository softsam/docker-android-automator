#!/bin/bash

PYBOT_ARGS="--variable locale:fr"

# CONSTANTS
# Automation directory
AUTOMATION_DIR=~/automation
# Directory containing the apk to install
APK_DIR=${AUTOMATION_DIR}/apk
# Directory containing the robot framework tests
ROBOT_DIR=${AUTOMATION_DIR}/robot
# Directory containing the output of the tests
OUTPUT_DIR=${AUTOMATION_DIR}/output

# Shell colors
RED="\033[31m"
GREEN="\033[32m"
NO_COLOR="\033[0m"


# Parse arguments
parse_arguments()
{
    args=`getopt -l sdk:,devices,help s:dh $*`
    set -- $args
    while true;do
        case $1 in
            -s|--sdk)
                sdk_list=`eval echo $2 | tr -s "," "  "`;shift;shift;continue
            ;;
            -d|--devices)
                run_on_physical_device="yes";shift;continue
            ;;
            -h|--help)
                show_help;exit;
            ;;
            --)
               break
            ;;
        esac
    done
}

show_help()
{
    echo "Automator tool to run tests on android devices and emulators."
    echo ""
    echo "Provide at least one of the following options:"
    echo "    [ -d | --devices ] Tests will run on every physical device available."
    echo "    [ -s | --sdk ] Tests will run on the given sdk. Ex: --sdk 16,18,22"
    echo "    [ -h | --help ] Display this message."
}

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

    # Create output dir if it does not exist
    if [ ! -d $OUTPUT_DIR ]
    then
        mkdir $OUTPUT_DIR
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
    local android_api=$1
    log_info "Starting emulator for SDK $android_api"
    docker run -d -p 5555:5555 -p 5900:5900 --name android softsam/android-${android_api}
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
    local device=""
    while [[ "${device}" = "" ]]; do
       docker exec appium adb connect android:5555
       device=`docker exec appium adb devices|awk 'NR>1 {print $1}'`
       sleep 1
    done
}

# Run robot framework tests
# First argument: the sdk version of the device / emulator
# Second argument: the output directory of the tests
run_tests()
{
    local android_api=$1
    local output_dir=$2
    local pybot_args="$PYBOT_ARGS --log /output/log.html --report /output/report.html --output /output/output.xml"
    log_info "Running robot framework tests for android api ${android_api}"
    docker run --rm --link appium:robot2appium --name robot -v ${ROBOT_DIR}:/robot -v ${output_dir}:/output softsam/robotframework-appium $pybot_args --variable android_api:$android_api .
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
        local output_dir=$OUTPUT_DIR/$device
        if [ ! -d $output_dir ]
        then
            mkdir $output_dir
        fi
        run_tests $sdk_version $output_dir
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
    local sdk_version=`adb -s $1 shell getprop ro.build.version.sdk | tr -d '\r'`
    adb kill-server &> /dev/null
    echo $sdk_version
}

run_tests_on_emulator()
{
    local sdk_list=$@
    for sdk_version in $sdk_list
    do
        log_info "Starting test on emulator SDK=${sdk_version}"
        run_emulator $sdk_version
        run_appium_server
        log_info "Wait for appium server to be ready"
        sleep 10
        connect_appium_to_emulator
        wait_for_emulator
        local output_dir=$OUTPUT_DIR/emulator-${sdk_version}
        if [ ! -d $output_dir ]
        then
            mkdir $output_dir
        fi
        start_recording $output_dir
        run_tests $sdk_version $output_dir
        stop_recording
        docker rm -f appium
        docker rm -f android
        docker rm -f vncrecorder
    done
}

# Start to record the vnc feed of the emulator
# Argument: the output directory of the video
start_recording()
{
    local output_dir=$1
    log_info "Starting video recording"
    docker run -d --link android:vncrecorder2android --name vncrecorder -v ${output_dir}:/vnc softsam/vncrecorder -o /vnc/record.flv android
}

stop_recording()
{
    log_info "Stopping video recording"
    docker kill -s INT vncrecorder
}

# Main program
sdk_list=""
run_on_physical_device=""
parse_arguments $@
check_directory_structure
cleanup
if [[ $run_on_physical_device = "yes" ]]
then
	run_tests_on_all_physical_devices
fi
run_tests_on_emulator $sdk_list
cleanup

