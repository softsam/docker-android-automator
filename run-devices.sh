
# Run appium server on real device
run_appium_server_on_physical_device()
{
    log_info "Starting appium server"
    docker pull softsam/appium:latest
    docker run -d --privileged -v /dev/bus/usb:/dev/bus/usb -p 4723:4723 --name $docker_appium -e APPIUM_ARGS="-U $1" -v ${APK_DIR}:/apk softsam/appium:latest
}

# Wait for a specific device boot sequence to be over
# Param: the id of the device to check
wait_for_device()
{
    local bootanim=""
    until [[ "$bootanim" =~ "stopped" ]]; do
       bootanim=`docker exec $docker_appium adb -s $1 shell getprop init.svc.bootanim 2>&1`
       echo "Waiting for device to start...$bootanim"
       sleep 1
    done
}

run_tests_on_all_physical_devices()
{
    local devices=$(list_devices)
    for device in $devices
    do
        local sdk_version=$(get_device_sdk $device)
        local device_locale=$(get_device_locale $device)
        log_info "Running test on device $device with sdk $sdk_version and locale $device_locale"
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
        run_tests $device $sdk_version $device_locale $output_dir
        # remove appium server
        docker rm -f $docker_appium
    done
}

# List all connected physical devices
list_devices()
{
    adb start-server &> /dev/null
    local devices=`adb devices | grep -v "*" | awk 'NR>1 {print $1}'`
    adb kill-server &> /dev/null
    echo $devices
}

# Get the sdk version of the given device
get_device_sdk()
{
    adb start-server &> /dev/null
    local sdk_version=`adb -s $1 shell getprop ro.build.version.sdk | grep -v "*" | tr -d '\r'`
    adb kill-server &> /dev/null
    echo $sdk_version
}

# Get the locale of the given device.
# First argument: the device to connect to
get_device_locale()
{
    adb start-server &> /dev/null
    local device_locale=`adb -s $1 shell getprop persist.sys.language | grep -v "*" | tr -d '\r'`
    adb kill-server &> /dev/null
    echo $device_locale
}

